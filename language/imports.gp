package language

import (
    "crypto/sha256"
    "fmt"
    "path"
    "strings"
    "unicode"
    "unicode/utf8"
)

// SourceFile retains the original import source, not only its flattened form.
// Imports contains resolved source IDs in declaration order.
type SourceFile struct { ID string; Source string; Digest string; Namespace string; Imports []string }
type SourceBundle struct { entry string; files []SourceFile; program *Program }
func (b *SourceBundle) Entry()string{if b==nil{return ""};return b.entry}
func (b *SourceBundle) Program()*Program{if b==nil{return nil};return b.program}
func (b *SourceBundle) Files()[]SourceFile{if b==nil{return nil};out:=append([]SourceFile(nil),b.files...);for i:=range out{out[i].Imports=append([]string(nil),out[i].Imports...)};return out}
func (b *SourceBundle) Sources()map[string]string{out:=map[string]string{};if b!=nil{for _,file:=range b.files{out[file.ID]=file.Source}};return out}

// ImportError attributes original parse/import errors to their source file.
// Errors from flattened cross-module type checking identify the owning file,
// but their span belongs to the canonical flattened source, not original bytes.
type ImportError struct { Code string; SourceID string; Message string; Cause error }
func (e *ImportError) Error()string{return e.Code+" in "+e.SourceID+": "+e.Message}
func (e *ImportError) Unwrap()error{return e.Cause}

func sourceID(name string)bool{
    if name==""||name=="."||!utf8.ValidString(name)||path.IsAbs(name)||path.Clean(name)!=name||strings.HasPrefix(name,"../")||strings.ContainsAny(name,"\\:\x00"){return false}
    for _,r:=range name{if unicode.IsControl(r){return false}}
    return true
}

type sourceResolver struct { sources map[string]string; modules map[string]*Module; state map[string]uint8; files []SourceFile; bytes int }

// CompileSources resolves Haskell-like imports exclusively from supplied source
// strings. It performs no I/O. IDs are canonical relative slash-separated paths;
// an import is relative to its importing file and must remain within that root.
// Shared dependencies are included once, in deterministic dependency-first
// order. Cycles and ambiguous cross-module declaration names reject explicitly.
// Packages are output namespaces, not automatic symbol qualification: the entry
// namespace controls the flattened program and each original namespace is kept.
func CompileSources(entry string,sources map[string]string)(*SourceBundle,error){
    if !sourceID(entry){return nil,&ImportError{Code:"language.import_path",SourceID:entry,Message:"entry must be a canonical relative source ID"}}
    if len(sources)>10000{return nil,&ImportError{Code:"language.import_limit",SourceID:entry,Message:"at most 10,000 source files may be supplied"}}
    r:=sourceResolver{sources:make(map[string]string,len(sources)),modules:map[string]*Module{},state:map[string]uint8{}}
    for id,source:=range sources{if !sourceID(id){return nil,&ImportError{Code:"language.import_path",SourceID:id,Message:"source IDs must be canonical relative paths"}};r.sources[id]=source}
    if err:=r.visit(entry,0);err!=nil{return nil,err}
    for _,file:=range r.files{if file.ID!=entry&&r.modules[file.ID].OpenAPI!=nil{return nil,&ImportError{Code:"language.import_openapi",SourceID:file.ID,Message:"only the entry source may declare OpenAPI operations; import reusable types and functions instead"}}}
    minimum:=func(current,next uint64)uint64{if current==0||next!=0&&next<current{return next};return current};effective:=SchemaLimits{};for _,file:=range r.files{declared:=r.modules[file.ID].Limits;effective.Total=minimum(effective.Total,declared.Total);effective.Clause=minimum(effective.Clause,declared.Clause)}
    types,terms:=map[string]string{},map[string]string{}
    var flattened strings.Builder
    if namespace:=r.modules[entry].Package;namespace!=""{flattened.WriteString("package "+namespace+"\n\n")}
    if effective.Total!=0||effective.Clause!=0{flattened.WriteString("@limits");if effective.Total!=0{flattened.WriteString(" total "+fmt.Sprint(effective.Total))};if effective.Clause!=0{flattened.WriteString(" clause "+fmt.Sprint(effective.Clause))};flattened.WriteString("\n\n")}
    if declaration:=r.modules[entry].OpenAPI;declaration!=nil{flattened.WriteString(FormatOpenAPI(declaration));flattened.WriteByte('\n')}
    type segment struct { id string; start int; end int };segments:=[]segment{}
    for _,file:=range r.files{
        module:=r.modules[file.ID]
        bind:=func(table map[string]string,name string)error{if owner,exists:=table[name];exists{return &ImportError{Code:"language.import_collision",SourceID:file.ID,Message:"declaration "+name+" conflicts with "+owner}};table[name]=file.ID;return nil}
        for _,decl:=range module.Types{if err:=bind(types,decl.Name);err!=nil{return nil,err};for _,variant:=range decl.Variants{if err:=bind(terms,variant.Name);err!=nil{return nil,err}}}
        for _,fn:=range module.Functions{if err:=bind(terms,fn.Name);err!=nil{return nil,err}}
        clean:=*module;clean.Package="";clean.Imports=nil;clean.Limits=SchemaLimits{};clean.ReleasePolicy=nil;clean.OpenAPI=nil
        text:=Format(&clean)
        if len(text)>(16<<20)-flattened.Len(){return nil,&ImportError{Code:"language.import_limit",SourceID:file.ID,Message:"flattened source exceeds 16 MiB"}}
        start:=flattened.Len();flattened.WriteString(text);flattened.WriteByte('\n');segments=append(segments,segment{id:file.ID,start:start,end:flattened.Len()})
    }
    flattenedSource:=flattened.String()
    if policy:=r.modules[entry].ReleasePolicy;policy!=nil{var err error;flattenedSource,err=AppendReleasePolicyFooter(flattenedSource,policy);if err!=nil{return nil,&ImportError{Code:"language.import_limit",SourceID:entry,Message:err.Error(),Cause:err}}}
    program,err:=Compile(flattenedSource);if err!=nil{
        owner:=entry;if detail,ok:=err.(*Error);ok{for _,part:=range segments{if detail.At.Start.Offset>=part.start&&detail.At.Start.Offset<part.end{owner=part.id;break}}}
        return nil,&ImportError{Code:"language.import_type",SourceID:owner,Message:"bundled type checking failed (positions refer to canonical flattened source): "+err.Error(),Cause:err}
    }
    return &SourceBundle{entry:entry,files:r.files,program:program},nil
}

func (r *sourceResolver) visit(id string,depth int)error{
    if depth>256{return &ImportError{Code:"language.import_limit",SourceID:id,Message:"import nesting exceeds 256"}}
    if r.state[id]==2{return nil};if r.state[id]==1{return &ImportError{Code:"language.import_cycle",SourceID:id,Message:"cyclic module imports are not supported; put mutually recursive declarations in one module"}}
    source,ok:=r.sources[id];if !ok{return &ImportError{Code:"language.import_missing",SourceID:id,Message:"import is not present in the supplied offline source map"}}
    if len(source)>(16<<20)-r.bytes{return &ImportError{Code:"language.import_limit",SourceID:id,Message:"reachable source files exceed 16 MiB"}};r.bytes+=len(source)
    module,err:=Parse(source);if err!=nil{return &ImportError{Code:"language.import_parse",SourceID:id,Message:err.Error(),Cause:err}}
    r.modules[id]=module;r.state[id]=1
    imported:=[]string{}
    for _,entry:=range module.Imports{
        relative:=entry.Path
        if relative==""||path.IsAbs(relative)||strings.ContainsAny(relative,"\\:\x00"){return &ImportError{Code:"language.import_path",SourceID:id,Message:"imports must use relative paths, not URLs or host filesystem paths"}}
        resolved:=path.Join(path.Dir(id),relative)
        if !sourceID(resolved){return &ImportError{Code:"language.import_path",SourceID:id,Message:"import escapes the supplied source root or has an invalid ID"}}
        imported=append(imported,resolved);if err:=r.visit(resolved,depth+1);err!=nil{return err}
    }
    r.state[id]=2
    r.files=append(r.files,SourceFile{ID:id,Source:source,Digest:fmt.Sprintf("%x",sha256.Sum256([]byte(source))),Namespace:module.Package,Imports:imported})
    return nil
}
