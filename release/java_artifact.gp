package release

import (
    "archive/zip"
    "bytes"
    "crypto/sha256"
    "encoding/binary"
    "fmt"
    "hash"
    "io"
    "os"
    "path"
    "sort"
    "strings"
    "unicode"
    "unicode/utf8"
)

// JavaArtifactLimits bounds both ZIP metadata and streamed decompression.
// Zero fields select defaults; nonzero fields may only tighten hard limits.
type JavaArtifactLimits struct {
    InputBytes int64
    Entries int
    ExpandedBytes int64
    EntryBytes int64
    NameBytes int
}

var javaArtifactHardLimits=JavaArtifactLimits{InputBytes:256<<20,Entries:100000,ExpandedBytes:1<<30,EntryBytes:128<<20,NameBytes:4096}
var javaArtifactDefaultLimits=JavaArtifactLimits{InputBytes:64<<20,Entries:20000,ExpandedBytes:256<<20,EntryBytes:32<<20,NameBytes:1024}

func DefaultJavaArtifactLimits()JavaArtifactLimits{return javaArtifactDefaultLimits}
func checkedJavaArtifactLimits(input JavaArtifactLimits)(JavaArtifactLimits,error){
    limits:=input;if limits.InputBytes==0{limits.InputBytes=javaArtifactDefaultLimits.InputBytes};if limits.Entries==0{limits.Entries=javaArtifactDefaultLimits.Entries};if limits.ExpandedBytes==0{limits.ExpandedBytes=javaArtifactDefaultLimits.ExpandedBytes};if limits.EntryBytes==0{limits.EntryBytes=javaArtifactDefaultLimits.EntryBytes};if limits.NameBytes==0{limits.NameBytes=javaArtifactDefaultLimits.NameBytes}
    if limits.InputBytes<=0||limits.Entries<=0||limits.ExpandedBytes<=0||limits.EntryBytes<=0||limits.NameBytes<=0{return JavaArtifactLimits{},fmt.Errorf("release.java_artifact: limits must be positive")}
    if limits.InputBytes>javaArtifactHardLimits.InputBytes||limits.Entries>javaArtifactHardLimits.Entries||limits.ExpandedBytes>javaArtifactHardLimits.ExpandedBytes||limits.EntryBytes>javaArtifactHardLimits.EntryBytes||limits.NameBytes>javaArtifactHardLimits.NameBytes{return JavaArtifactLimits{},fmt.Errorf("release.java_artifact: limits may only tighten hard limits")}
    return limits,nil
}

// JavaArtifactInventory is immutable evidence derived from explicitly supplied
// JAR bytes. It is not evidence that the bytes were published or authentic.
type JavaArtifactInventory struct { artifactSHA256 ContentID; classes []PublicationFile; entries int; expandedBytes int64 }
func (i *JavaArtifactInventory) ArtifactSHA256()ContentID{if i==nil{return ""};return i.artifactSHA256}
func (i *JavaArtifactInventory) Classes()[]PublicationFile{if i==nil{return nil};return append([]PublicationFile(nil),i.classes...)}
func (i *JavaArtifactInventory) EntryCount()int{if i==nil{return 0};return i.entries}
func (i *JavaArtifactInventory) ExpandedBytes()int64{if i==nil{return 0};return i.expandedBytes}

func javaArtifactName(name string,directory bool)string{if directory{return strings.TrimSuffix(name,"/")};return name}
func validJavaArtifactName(name string,directory bool)bool{clean:=javaArtifactName(name,directory);return clean!=""&&clean!="."&&clean!=".."&&utf8.ValidString(clean)&&path.Clean(clean)==clean&&!path.IsAbs(clean)&&!strings.HasPrefix(clean,"../")&&!strings.ContainsAny(clean,"\\:\x00")}
func javaArtifactFold(name string)string{var result strings.Builder;for _,r:=range name{smallest:=r;for next:=unicode.SimpleFold(r);next!=r;next=unicode.SimpleFold(next){if next<smallest{smallest=next}};result.WriteRune(smallest)};return result.String()}

// preflightJavaArtifact bounds central-directory allocation before archive/zip
// constructs a File for each entry. ZIP64 and multi-disk JARs fail closed in
// this bounded verifier.
func preflightJavaArtifact(input []byte,limits JavaArtifactLimits)error{
    const endSize=22;const maxComment=65535;end:=-1;lowest:=len(input)-endSize-maxComment;if lowest<0{lowest=0};for at:=len(input)-endSize;at>=lowest;at--{if binary.LittleEndian.Uint32(input[at:])!=0x06054b50{continue};comment:=int(binary.LittleEndian.Uint16(input[at+20:]));if at+endSize+comment==len(input){end=at;break}};if end<0{return fmt.Errorf("release.java_artifact: malformed JAR: end of central directory is absent")}
    if end>=20&&binary.LittleEndian.Uint32(input[end-20:])==0x07064b50{return fmt.Errorf("release.java_artifact: ZIP64 JARs are unsupported")};disk:=binary.LittleEndian.Uint16(input[end+4:]);directoryDisk:=binary.LittleEndian.Uint16(input[end+6:]);onDisk:=binary.LittleEndian.Uint16(input[end+8:]);declared:=binary.LittleEndian.Uint16(input[end+10:]);size:=binary.LittleEndian.Uint32(input[end+12:]);offset:=binary.LittleEndian.Uint32(input[end+16:]);if disk!=0||directoryDisk!=0||onDisk!=declared{return fmt.Errorf("release.java_artifact: multi-disk JARs are unsupported")};if declared==0xffff||size==0xffffffff||offset==0xffffffff{return fmt.Errorf("release.java_artifact: ZIP64 JARs are unsupported")};if int(declared)>limits.Entries{return fmt.Errorf("release.java_artifact: JAR entry limit exceeded")};directoryEnd:=uint64(offset)+uint64(size);if directoryEnd!=uint64(end)||directoryEnd>uint64(len(input)){return fmt.Errorf("release.java_artifact: malformed JAR: inconsistent central directory range")}
    cursor:=int(offset);count:=0;for cursor<end{if end-cursor<46||binary.LittleEndian.Uint32(input[cursor:])!=0x02014b50{return fmt.Errorf("release.java_artifact: malformed JAR: invalid central directory entry")};compressed:=binary.LittleEndian.Uint32(input[cursor+20:]);expanded:=binary.LittleEndian.Uint32(input[cursor+24:]);nameBytes:=int(binary.LittleEndian.Uint16(input[cursor+28:]));extraBytes:=int(binary.LittleEndian.Uint16(input[cursor+30:]));commentBytes:=int(binary.LittleEndian.Uint16(input[cursor+32:]));localOffset:=binary.LittleEndian.Uint32(input[cursor+42:]);if compressed==0xffffffff||expanded==0xffffffff||localOffset==0xffffffff{return fmt.Errorf("release.java_artifact: ZIP64 JARs are unsupported")};if nameBytes>limits.NameBytes{return fmt.Errorf("release.java_artifact: JAR entry name byte limit exceeded")};recordBytes:=46+nameBytes+extraBytes+commentBytes;if recordBytes<46||recordBytes>end-cursor{return fmt.Errorf("release.java_artifact: malformed JAR: truncated central directory entry")};cursor+=recordBytes;count++;if count>limits.Entries{return fmt.Errorf("release.java_artifact: JAR entry limit exceeded")}}
    if cursor!=end||count!=int(declared){return fmt.Errorf("release.java_artifact: malformed JAR: central directory count does not match its declaration")};return nil
}

// InspectJavaArtifact reads every entry through archive/zip's CRC checker. It
// never extracts files and inventories only exact .class entry bytes.
func InspectJavaArtifact(input []byte,requested JavaArtifactLimits)(*JavaArtifactInventory,error){
    limits,err:=checkedJavaArtifactLimits(requested);if err!=nil{return nil,err};if int64(len(input))>limits.InputBytes{return nil,fmt.Errorf("release.java_artifact: JAR input byte limit exceeded")}
    if err:=preflightJavaArtifact(input,limits);err!=nil{return nil,err};reader,err:=zip.NewReader(bytes.NewReader(input),int64(len(input)));if err!=nil{return nil,fmt.Errorf("release.java_artifact: malformed JAR: %w",err)};if len(reader.File)>limits.Entries{return nil,fmt.Errorf("release.java_artifact: JAR entry limit exceeded")}
    seen:=map[string]bool{};folded:=map[string]bool{};classes:=[]PublicationFile{};expanded:=int64(0)
    for _,entry:=range reader.File{
        directory:=entry.FileInfo().IsDir();name:=javaArtifactName(entry.Name,directory);if len(entry.Name)>limits.NameBytes||!validJavaArtifactName(entry.Name,directory){return nil,fmt.Errorf("release.java_artifact: unsafe or overlong JAR entry name %q",entry.Name)};portable:=javaArtifactFold(name);if seen[name]||folded[portable]{return nil,fmt.Errorf("release.java_artifact: duplicate portable JAR entry %q",entry.Name)};seen[name]=true;folded[portable]=true
        if entry.Flags&(1|1<<6|1<<13)!=0{return nil,fmt.Errorf("release.java_artifact: encrypted or masked JAR entry %q is unsupported",entry.Name)};mode:=entry.Mode();if mode&os.ModeSymlink!=0{return nil,fmt.Errorf("release.java_artifact: symbolic-link JAR entry %q is unsupported",entry.Name)};if directory{if mode.Type()!=os.ModeDir{return nil,fmt.Errorf("release.java_artifact: non-directory JAR entry mode for %q",entry.Name)}}else if mode.Type()!=0{return nil,fmt.Errorf("release.java_artifact: nonregular JAR entry %q is unsupported",entry.Name)}
        if entry.UncompressedSize64>uint64(limits.EntryBytes)||entry.UncompressedSize64>uint64(limits.ExpandedBytes-expanded){return nil,fmt.Errorf("release.java_artifact: expanded byte limit exceeded at %q",entry.Name)}
        stream,err:=entry.Open();if err!=nil{return nil,fmt.Errorf("release.java_artifact: cannot open JAR entry %q: %w",entry.Name,err)};remaining:=limits.ExpandedBytes-expanded;allowed:=limits.EntryBytes;if remaining<allowed{allowed=remaining};var destination io.Writer=io.Discard;var digest hash.Hash
        if !directory&&strings.HasSuffix(name,".class"){digest=sha256.New();destination=digest};count,readErr:=io.Copy(destination,io.LimitReader(stream,allowed+1));closeErr:=stream.Close();if count>allowed{return nil,fmt.Errorf("release.java_artifact: expanded byte limit exceeded at %q",entry.Name)};if readErr!=nil{return nil,fmt.Errorf("release.java_artifact: malformed JAR entry %q: %w",entry.Name,readErr)};if closeErr!=nil{return nil,fmt.Errorf("release.java_artifact: cannot close JAR entry %q: %w",entry.Name,closeErr)};if count!=int64(entry.UncompressedSize64){return nil,fmt.Errorf("release.java_artifact: JAR entry %q size does not match its header",entry.Name)};expanded+=count
        if digest!=nil{classes=append(classes,PublicationFile{Path:name,SHA256:ContentID(fmt.Sprintf("%x",digest.Sum(nil)))})}
    }
    sort.Slice(classes,func(i,j int)bool{return classes[i].Path<classes[j].Path});return &JavaArtifactInventory{artifactSHA256:Digest(input),classes:classes,entries:len(reader.File),expandedBytes:expanded},nil
}

// JavaArtifactVerification checks a ledger's historical byte claims. It makes
// no Java ABI compatibility or publication-authenticity conclusion.
type JavaArtifactVerification struct { ready bool; unknown bool; issues []Issue }
func (v JavaArtifactVerification) Ready()bool{return v.ready}
func (v JavaArtifactVerification) Unknown()bool{return v.unknown}
func (v JavaArtifactVerification) Issues()[]Issue{return append([]Issue(nil),v.issues...)}
func javaArtifactVerificationIssue(v *JavaArtifactVerification,code,message string,unknown bool){v.issues=append(v.issues,Issue{Code:code,Message:message});if unknown{v.unknown=true}}

// VerifyPublishedArtifact compares a valid publication ledger with inventory
// obtained from explicitly supplied JAR bytes. Nil evidence is Unknown.
func VerifyPublishedArtifact(ledger *PublicationLedger,inventory *JavaArtifactInventory)JavaArtifactVerification{
    result:=JavaArtifactVerification{};if ledger==nil{javaArtifactVerificationIssue(&result,"maven.publication_unknown","publication ledger is unavailable",true);return result};result.issues=append(result.issues,validatePublicationLedger(ledger)...);if len(result.issues)>0{return result}
    published:=[]PublicationRecord{};for _,record:=range ledger.Records{if record.State==PublicationPublished{published=append(published,record)}};if len(published)==0{result.ready=true;return result};if inventory==nil{javaArtifactVerificationIssue(&result,"maven.publication_artifact_unknown","actual published JAR bytes are unavailable",true);return result}
    actual:=map[string]ContentID{};for _,class:=range inventory.classes{actual[class.Path]=class.SHA256};artifactMismatch:=false;for _,record:=range published{if record.ArtifactSHA256!=inventory.artifactSHA256{artifactMismatch=true};for _,class:=range record.Classes{digest,ok:=actual[class.Path];if !ok{javaArtifactVerificationIssue(&result,"maven.publication_class_missing",fmt.Sprintf("published class claim %s is absent from the supplied JAR",class.Path),false)}else if digest!=class.SHA256{javaArtifactVerificationIssue(&result,"maven.publication_class_digest",fmt.Sprintf("published class claim %s does not match the supplied JAR bytes; this mismatch alone is not an ABI conclusion",class.Path),false)}}};if artifactMismatch{javaArtifactVerificationIssue(&result,"maven.publication_artifact_digest","supplied JAR bytes do not match the published artifact SHA-256",false)};result.ready=len(result.issues)==0;return result
}
