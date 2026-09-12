package project

import (
    "encoding/json"
    "errors"
    "fmt"
    "os"
    "path/filepath"
    "sort"
    "strings"

    "goforge.dev/refine/release"
    "goforge.dev/refine/schemajson"
)

type ownedManifest struct { Version int `json:"version"`; Files map[string]release.ContentID `json:"files"` }
var linkOwned=os.Link

func safeRelative(name string)(string,error){if name==""||filepath.IsAbs(name){return "",fmt.Errorf("project.path: paths must be relative")};clean:=filepath.Clean(name);if clean=="."||clean==".."||strings.HasPrefix(clean,".."+string(filepath.Separator)){return "",fmt.Errorf("project.path: path escapes root")};return clean,nil}
func noSymlink(root,relative string,leaf bool)error{current:=root;parts:=strings.Split(relative,string(filepath.Separator));limit:=len(parts);if !leaf{limit--};for i:=0;i<limit;i++{current=filepath.Join(current,parts[i]);info,err:=os.Lstat(current);if errors.Is(err,os.ErrNotExist){continue};if err!=nil{return err};if info.Mode()&os.ModeSymlink!=0{return fmt.Errorf("project.symlink: %s",relative)};if i<limit-1&&!info.IsDir(){return fmt.Errorf("project.path: non-directory parent")}};return nil}
func readManifest(root,name string)(ownedManifest,error){manifest:=ownedManifest{Version:1,Files:map[string]release.ContentID{}};data,err:=os.ReadFile(filepath.Join(root,name));if errors.Is(err,os.ErrNotExist){return manifest,nil};if err!=nil{return manifest,err};if _,err=schemajson.Parse(data,schemajson.Limits{});err!=nil{return manifest,fmt.Errorf("project.manifest: invalid or duplicate-key JSON: %w",err)};if err=json.Unmarshal(data,&manifest);err!=nil||manifest.Version!=1||manifest.Files==nil{return manifest,fmt.Errorf("project.manifest: invalid owned-output manifest")};for path,digest:=range manifest.Files{clean,e:=safeRelative(path);if e!=nil||clean!=path||!digest.Valid(){return manifest,fmt.Errorf("project.manifest: unsafe entry")}};return manifest,nil}

// WriteOwned replaces only files proven unchanged since the preceding generated
// manifest. All new bytes are staged before any output changes. Returned install
// failures restore backups; process-crash atomicity is not promised.
func WriteOwned(rootPath string,bundle Bundle,manifestPath string)error{
    root,err:=filepath.Abs(rootPath);if err!=nil{return err};rootInfo,err:=os.Lstat(root);if err!=nil||!rootInfo.IsDir()||rootInfo.Mode()&os.ModeSymlink!=0{return fmt.Errorf("project.root: existing non-symlink directory required")};lock:=filepath.Join(root,".refine-project.lock");lockFile,err:=os.OpenFile(lock,os.O_CREATE|os.O_EXCL|os.O_WRONLY,0600);if err!=nil{return fmt.Errorf("project.lock: %w",err)};_ = lockFile.Close();defer os.Remove(lock);if manifestPath==""{manifestPath=".refine-generated.json"};manifestPath,err=safeRelative(manifestPath);if err!=nil{return err};if err=noSymlink(root,manifestPath,true);err!=nil{return err}
    old,err:=readManifest(root,manifestPath);if err!=nil{return err};desired:=map[string][]byte{};digests:=map[string]release.ContentID{}
    folded:=map[string]string{};for _,file:=range bundle.Files{relative,e:=safeRelative(file.Path);if e!=nil{return e};if relative==manifestPath{return fmt.Errorf("project.collision: output cannot replace its ownership manifest")};portable:=strings.ToLower(filepath.ToSlash(relative));if prior,ok:=folded[portable];ok{return fmt.Errorf("project.collision: portable paths %s and %s collide",prior,relative)};folded[portable]=relative;if _,ok:=desired[relative];ok{return fmt.Errorf("project.collision: duplicate %s",relative)};if e=noSymlink(root,relative,false);e!=nil{return e};desired[relative]=append([]byte(nil),file.Content...);digests[relative]=release.Digest(file.Content)}
    // Every existing destination and stale owned output is checked before stage.
    affected:=map[string]bool{};for name:=range desired{affected[name]=true};for name:=range old.Files{affected[name]=true}
    for name:=range affected{if e:=noSymlink(root,name,true);e!=nil{return e};full:=filepath.Join(root,name);info,e:=os.Lstat(full);if errors.Is(e,os.ErrNotExist){if _,wasOwned:=old.Files[name];wasOwned{return fmt.Errorf("project.owned_missing: generated file %s disappeared",name)};continue};if e!=nil{return e};if info.Mode()&os.ModeSymlink!=0||!info.Mode().IsRegular(){return fmt.Errorf("project.collision: unsafe existing output %s",name)};data,e:=os.ReadFile(full);if e!=nil{return e};prior,wasOwned:=old.Files[name];if !wasOwned{return fmt.Errorf("project.collision: refusing unowned output %s",name)};if release.Digest(data)!=prior{return fmt.Errorf("project.modified: generated file %s was edited",name)}}
    stage,err:=os.MkdirTemp(root,".refine-project-stage-");if err!=nil{return err};preserveStage:=false;defer func(){if !preserveStage{_ = os.RemoveAll(stage)}}()
    names:=make([]string,0,len(desired));for name:=range desired{names=append(names,name)};sort.Strings(names);for i,name:=range names{if err=os.WriteFile(filepath.Join(stage,fmt.Sprintf("new-%06d",i)),desired[name],0644);err!=nil{return err}}
    manifestData,err:=json.MarshalIndent(ownedManifest{Version:1,Files:digests},"","  ");if err!=nil{return err};manifestData=append(manifestData,'\n');if err=os.WriteFile(filepath.Join(stage,"manifest"),manifestData,0644);err!=nil{return err}
    // Back up every owned file as a same-inode hard link before installation.
    affectedNames:=make([]string,0,len(affected));for name:=range affected{affectedNames=append(affectedNames,name)};sort.Strings(affectedNames);backups:=map[string]string{};for i,name:=range affectedNames{full:=filepath.Join(root,name);if _,e:=os.Lstat(full);e==nil{backup:=filepath.Join(stage,fmt.Sprintf("old-%06d",i));if e=linkOwned(full,backup);e!=nil{return e};backups[name]=backup}}
    installed:=[]string{};rollback:=func()error{for i:=len(installed)-1;i>=0;i--{name:=installed[i];full:=filepath.Join(root,name);if data,e:=os.ReadFile(full);e==nil{wanted,keep:=digests[name];if !keep||release.Digest(data)!=wanted{return fmt.Errorf("project.rollback: concurrent replacement at %s",name)}};if e:=os.Remove(full);e!=nil&&!errors.Is(e,os.ErrNotExist){return e};if backup:=backups[name];backup!=""{if e:=os.Rename(backup,full);e!=nil{return e}}};return nil};fail:=func(cause error)error{if rb:=rollback();rb!=nil{preserveStage=true;return errors.Join(cause,rb)};return cause}
    ensure:=func(name string)error{parent:=filepath.Dir(filepath.Join(root,name));return os.MkdirAll(parent,0755)}
    for i,name:=range names{if err=ensure(name);err!=nil{return fail(err)};source:=filepath.Join(stage,fmt.Sprintf("new-%06d",i));destination:=filepath.Join(root,name);if _,owned:=backups[name];owned{err=os.Rename(source,destination)}else{err=linkOwned(source,destination)};if err!=nil{return fail(err)};installed=append(installed,name)}
    // Remove stale owned paths only after every desired output is installed.
    for _,name:=range affectedNames{if _,keep:=desired[name];keep{continue};if err=os.Remove(filepath.Join(root,name));err!=nil{return fail(err)};installed=append(installed,name)}
    if err=ensure(manifestPath);err!=nil{return fail(err)};manifestFull:=filepath.Join(root,manifestPath);manifestBackup:="";if _,e:=os.Lstat(manifestFull);e==nil{manifestBackup=filepath.Join(stage,"old-manifest");if e=linkOwned(manifestFull,manifestBackup);e!=nil{return fail(e)}};if err=os.Rename(filepath.Join(stage,"manifest"),manifestFull);err!=nil{return fail(err)}
    _ = manifestBackup;return nil
}
