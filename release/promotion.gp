package release

import (
    "encoding/json"
    "errors"
    "fmt"
    "io/fs"
    "os"
    "path/filepath"
    "sort"
    "strings"
)

type ImportKind uint8
const (ExactRelease ImportKind=iota+1; SnapshotImport; VersionRangeImport)

// PromotionImport is typed so callers cannot accidentally erase whether the
// source used an exact version, SNAPSHOT, or a floating range.
type PromotionImport struct { Family string; Kind ImportKind; Version Version; Content ContentID }
type PublishedRelease struct { Family string; Version Version; Content ContentID }
type Artifact struct { Path string; Content []byte }
type PromotionFamily struct {
    Family string
    Version Version
    SnapshotPath string
    // SnapshotFileContent protects the editable file against a plan/apply race.
    // It differs from ReleaseContent when promotion materializes exact pins.
    SnapshotFileContent ContentID
    ReleasePath string
    ReleaseContent []byte
    Imports []PromotionImport
    Generated []Artifact
}
type PromotionInput struct { Root string; Families []PromotionFamily; Available []PublishedRelease }
type PromotionResult struct { Released []PublishedRelease; SnapshotPending map[string]bool }

type transactionEntry struct { Destination string `json:"destination"`; Stage string `json:"stage"`; Digest ContentID `json:"sha256"` }
type transactionJournal struct { Version int `json:"version"`; State string `json:"state"`; Entries []transactionEntry `json:"entries"` }

const transactionPrefix=".refine-release-txn-"
const lockName=".refine-release.lock"
var linkFile=os.Link

func cleanRelative(path string)(string,error){
    if path==""||filepath.IsAbs(path){return "",fmt.Errorf("release.path: path must be relative")}
    clean:=filepath.Clean(path);if clean=="."||clean==".."||strings.HasPrefix(clean,".."+string(filepath.Separator)){return "",fmt.Errorf("release.path: path escapes promotion root")}
    return clean,nil
}
func resolvedRoot(root string)(string,error){
    if root==""{return "",fmt.Errorf("release.root: root is required")}
    absolute,err:=filepath.Abs(root);if err!=nil{return "",err}
    info,err:=os.Lstat(absolute);if err!=nil{return "",err};if !info.IsDir()||info.Mode()&os.ModeSymlink!=0{return "",fmt.Errorf("release.root: root must be an existing non-symlink directory")}
    return absolute,nil
}
func checkNoSymlink(root,relative string,includeLeaf bool)error{
    current:=root;parts:=strings.Split(relative,string(filepath.Separator));limit:=len(parts);if !includeLeaf{limit--}
    for i:=0;i<limit;i++{current=filepath.Join(current,parts[i]);info,err:=os.Lstat(current);if errors.Is(err,os.ErrNotExist){continue};if err!=nil{return err};if info.Mode()&os.ModeSymlink!=0{return fmt.Errorf("release.symlink: %s contains a symbolic link",relative)};if i<limit-1&&!info.IsDir(){return fmt.Errorf("release.path: parent of %s is not a directory",relative)}}
    return nil
}
func makeParents(root,relative string)([]string,error){
    parent:=filepath.Dir(relative);if parent=="."{return nil,nil}
    parts:=strings.Split(parent,string(filepath.Separator));current:=root;created:=[]string{}
    for _,part:=range parts{current=filepath.Join(current,part);info,err:=os.Lstat(current);if err==nil{if info.Mode()&os.ModeSymlink!=0||!info.IsDir(){return created,fmt.Errorf("release.path: unsafe parent for %s",relative)};continue};if !errors.Is(err,os.ErrNotExist){return created,err};if err:=os.Mkdir(current,0755);err!=nil{if errors.Is(err,fs.ErrExist){continue};return created,err};created=append(created,current)}
    return created,nil
}
func syncDir(path string)error{file,err:=os.Open(path);if err!=nil{return err};defer file.Close();return file.Sync()}
func writeExclusive(path string,content []byte)error{file,err:=os.OpenFile(path,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0644);if err!=nil{return err};if _,err= file.Write(content);err==nil{err=file.Sync()};closeErr:=file.Close();if err==nil{err=closeErr};return err}
func writeJournal(path string,j transactionJournal)error{
    data,err:=json.Marshal(j);if err!=nil{return err};temporary:=path+".next";_ = os.Remove(temporary)
    file,err:=os.OpenFile(temporary,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600);if err!=nil{return err};if _,err=file.Write(data);err==nil{err=file.Sync()};closeErr:=file.Close();if err==nil{err=closeErr};if err!=nil{_ = os.Remove(temporary);return err}
    if err:=os.Rename(temporary,path);err!=nil{_ = os.Remove(temporary);return err};return syncDir(filepath.Dir(path))
}
func releaseKey(family string,version Version)string{return family+"\x00"+version.String()}

// Promote validates and stages the whole batch before installing any output.
// Installation uses hard links, which fail rather than overwrite a colliding
// immutable destination. Returned errors are rolled back. A process crash is
// recovered by Recover, using inode identity so unrelated files are untouched.
func Promote(input PromotionInput)(PromotionResult,error){
    root,err:=resolvedRoot(input.Root);if err!=nil{return PromotionResult{},err}
    lock:=filepath.Join(root,lockName);lockFile,err:=os.OpenFile(lock,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600);if err!=nil{return PromotionResult{},fmt.Errorf("release.lock: %w (run Recover after a crashed promotion)",err)};_ = lockFile.Close();defer os.Remove(lock)
    result:=PromotionResult{SnapshotPending:map[string]bool{}}
    if len(input.Families)==0{return result,fmt.Errorf("release.batch: at least one family is required")}
    available:=map[string]ContentID{};for _,r:=range input.Available{if !validFamily(r.Family)||!r.Version.Valid()||!r.Content.Valid(){return result,fmt.Errorf("release.available: invalid published release identity")};key:=releaseKey(r.Family,r.Version);if old,ok:=available[key];ok&&old!=r.Content{return result,fmt.Errorf("release.available: conflicting contents for %s %s",r.Family,r.Version.String())};available[key]=r.Content}
    destinations:=map[string]bool{};batch:=map[string]ContentID{};entries:=[]transactionEntry{};contents:=map[string][]byte{}
    add:=func(path string,content []byte)error{relative,e:=cleanRelative(path);if e!=nil{return e};if destinations[relative]{return fmt.Errorf("release.collision: duplicate destination %s",relative)};destinations[relative]=true;if e=checkNoSymlink(root,relative,false);e!=nil{return e};if _,e=os.Lstat(filepath.Join(root,relative));e==nil{return fmt.Errorf("release.immutable: destination already exists: %s",relative)}else if !errors.Is(e,os.ErrNotExist){return e};digest:=Digest(content);entries=append(entries,transactionEntry{Destination:relative,Digest:digest});contents[relative]=append([]byte(nil),content...);return nil}
    seenFamilies:=map[string]bool{}
    for _,family:=range input.Families{
        if !validFamily(family.Family)||seenFamilies[family.Family]{return result,fmt.Errorf("release.family: invalid or duplicate family %q",family.Family)};seenFamilies[family.Family]=true
        if !family.Version.Valid(){return result,fmt.Errorf("release.version: invalid release version for %s",family.Family)}
        if !family.SnapshotFileContent.Valid(){return result,fmt.Errorf("release.snapshot_digest: invalid digest for %s",family.Family)}
        snapshotRel,e:=cleanRelative(family.SnapshotPath);if e!=nil{return result,e};if e=checkNoSymlink(root,snapshotRel,true);e!=nil{return result,e};snapshotFull:=filepath.Join(root,snapshotRel);snapshotInfo,e:=os.Lstat(snapshotFull);if e!=nil||!snapshotInfo.Mode().IsRegular(){return result,fmt.Errorf("release.snapshot: %s must be a regular file",family.Family)};snapshotBytes,e:=os.ReadFile(snapshotFull);if e!=nil{return result,fmt.Errorf("release.snapshot: %w",e)};if Digest(snapshotBytes)!=family.SnapshotFileContent{return result,fmt.Errorf("release.snapshot_changed: %s no longer matches planned content",family.Family)}
        releaseDigest:=Digest(family.ReleaseContent)
        key:=releaseKey(family.Family,family.Version);if _,ok:=batch[key];ok{return result,fmt.Errorf("release.batch: duplicate release %s %s",family.Family,family.Version.String())};batch[key]=releaseDigest
        if e=add(family.ReleasePath,family.ReleaseContent);e!=nil{return result,e};for _,artifact:=range family.Generated{if e=add(artifact.Path,artifact.Content);e!=nil{return result,e}}
        result.Released=append(result.Released,PublishedRelease{Family:family.Family,Version:family.Version,Content:releaseDigest});result.SnapshotPending[family.Family]=false
    }
    for _,family:=range input.Families{for _,pin:=range family.Imports{
        if pin.Kind!=ExactRelease{return PromotionResult{},fmt.Errorf("release.import: %s import of %s is not an exact released version",family.Family,pin.Family)}
        if !validFamily(pin.Family)||!pin.Version.Valid()||!pin.Content.Valid(){return PromotionResult{},fmt.Errorf("release.import: invalid exact pin in %s",family.Family)}
        key:=releaseKey(pin.Family,pin.Version);actual,ok:=batch[key];if !ok{actual,ok=available[key]};if !ok||actual!=pin.Content{return PromotionResult{},fmt.Errorf("release.import: %s does not resolve %s %s to the pinned content",family.Family,pin.Family,pin.Version.String())}
    }}
    sort.Slice(entries,func(i,j int)bool{return entries[i].Destination<entries[j].Destination})
    transaction,err:=os.MkdirTemp(root,transactionPrefix);if err!=nil{return PromotionResult{},err};journalPath:=filepath.Join(transaction,"journal.json")
    cleanup:=func(){_ = os.RemoveAll(transaction)}
    for i:=range entries{stage:=fmt.Sprintf("entry-%06d",i);entries[i].Stage=stage;if err=writeExclusive(filepath.Join(transaction,stage),contents[entries[i].Destination]);err!=nil{cleanup();return PromotionResult{},err}}
    journal:=transactionJournal{Version:1,State:"installing",Entries:entries};if err=writeJournal(journalPath,journal);err!=nil{cleanup();return PromotionResult{},err};if err=syncDir(transaction);err!=nil{cleanup();return PromotionResult{},err}
    createdDirs:=[]string{}
    rollback:=func(){rollbackEntries(root,transaction,entries);for i:=len(createdDirs)-1;i>=0;i--{_ = os.Remove(createdDirs[i])};cleanup()}
    for _,entry:=range entries{
        var made []string;made,err=makeParents(root,entry.Destination);createdDirs=append(createdDirs,made...);if err!=nil{rollback();return PromotionResult{},err}
        if err=checkNoSymlink(root,entry.Destination,false);err!=nil{rollback();return PromotionResult{},err}
        destination:=filepath.Join(root,entry.Destination);if err=linkFile(filepath.Join(transaction,entry.Stage),destination);err!=nil{rollback();return PromotionResult{},fmt.Errorf("release.install: %s: %w",entry.Destination,err)};if err=syncDir(filepath.Dir(destination));err!=nil{rollback();return PromotionResult{},err}
    }
    journal.State="committed";if err=writeJournal(journalPath,journal);err!=nil{rollback();return PromotionResult{},err};if err=syncDir(root);err!=nil{rollback();return PromotionResult{},err};cleanup();return result,nil
}

func rollbackEntries(root,transaction string,entries []transactionEntry)error{for i:=len(entries)-1;i>=0;i--{entry:=entries[i];sourceInfo,e1:=os.Lstat(filepath.Join(transaction,entry.Stage));destination:=filepath.Join(root,entry.Destination);destInfo,e2:=os.Lstat(destination);if e1==nil&&e2==nil&&os.SameFile(sourceInfo,destInfo){if e:=os.Remove(destination);e!=nil{return e};if e:=syncDir(filepath.Dir(destination));e!=nil{return e}}};return nil}

// Recover rolls back incomplete transactions and removes committed transaction
// metadata. It refuses malformed journals and only removes destinations that
// are still hard links to this transaction's staged inode.
func Recover(rootPath string)error{
    root,err:=resolvedRoot(rootPath);if err!=nil{return err}
    matches,err:=filepath.Glob(filepath.Join(root,transactionPrefix+"*"));if err!=nil{return err};sort.Strings(matches)
    for _,transaction:=range matches{
        info,e:=os.Lstat(transaction);if e!=nil{return e};if !info.IsDir()||info.Mode()&os.ModeSymlink!=0{return fmt.Errorf("release.recovery: unsafe transaction path %s",filepath.Base(transaction))}
        journalPath:=filepath.Join(transaction,"journal.json");nextPath:=journalPath+".next";journalInfo,e:=os.Lstat(journalPath);if errors.Is(e,os.ErrNotExist){journalPath=nextPath;journalInfo,e=os.Lstat(journalPath)};if e!=nil||!journalInfo.Mode().IsRegular(){return fmt.Errorf("release.recovery: unsafe journal %s",filepath.Base(transaction))};data,e:=os.ReadFile(journalPath);if e!=nil{return fmt.Errorf("release.recovery: %s: %w",filepath.Base(transaction),e)};journal:=transactionJournal{};if e=json.Unmarshal(data,&journal);e!=nil||journal.Version!=1{return fmt.Errorf("release.recovery: invalid journal %s",filepath.Base(transaction))}
        if journal.State!="committed"&&journal.State!="installing"{return fmt.Errorf("release.recovery: invalid transaction state")}
        allowed:=map[string]bool{"journal.json":true,"journal.json.next":true}
        for i:=range journal.Entries{entry:=&journal.Entries[i];relative,e:=cleanRelative(entry.Destination);if e!=nil{return fmt.Errorf("release.recovery: unsafe destination")};entry.Destination=relative;stage,e:=cleanRelative(entry.Stage);if e!=nil||filepath.Dir(stage)!="."||!strings.HasPrefix(stage,"entry-"){return fmt.Errorf("release.recovery: unsafe stage")};entry.Stage=stage;if allowed[stage]{return fmt.Errorf("release.recovery: duplicate stage")};allowed[stage]=true;stageInfo,e:=os.Lstat(filepath.Join(transaction,stage));if e!=nil||!stageInfo.Mode().IsRegular(){return fmt.Errorf("release.recovery: missing stage")};stageBytes,e:=os.ReadFile(filepath.Join(transaction,stage));if e!=nil||Digest(stageBytes)!=entry.Digest{return fmt.Errorf("release.recovery: stage digest mismatch")}}
        children,e:=os.ReadDir(transaction);if e!=nil{return e};for _,child:=range children{if !allowed[child.Name()]{return fmt.Errorf("release.recovery: transaction contains unexpected file %s",child.Name())}}
        if journal.State=="installing"{if e=rollbackEntries(root,transaction,journal.Entries);e!=nil{return fmt.Errorf("release.recovery: rollback: %w",e)}}
        for _,entry:=range journal.Entries{if e=os.Remove(filepath.Join(transaction,entry.Stage));e!=nil&&!errors.Is(e,os.ErrNotExist){return e}};for _,path:=range []string{filepath.Join(transaction,"journal.json"),nextPath}{if e=os.Remove(path);e!=nil&&!errors.Is(e,os.ErrNotExist){return e}};if e=os.Remove(transaction);e!=nil{return e}
    }
    // Recovery is the explicit operator action that clears a crash-stale lock.
    removeErr:=os.Remove(filepath.Join(root,lockName));if removeErr!=nil&&!errors.Is(removeErr,os.ErrNotExist){return removeErr};return syncDir(root)
}
