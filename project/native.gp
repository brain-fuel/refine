package project

import (
    "encoding/json"
    "fmt"
    "path"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func normalizeContract(c Contract)(Contract,error){
    var err error;c,err=normalizeAuthoredOpenAPI(c);if err!=nil{return c,err}
    if c.NativeProject==nil{return c,nil}
    if c.Program!=nil{return c,fmt.Errorf("project.native: Program and NativeProject are mutually exclusive")}
    if projectWireConfigured(c.Wire){return c,fmt.Errorf("project.native: wire metadata belongs in the versioned native bundle")}
    operations:=c.NativeProject.Kind()==native.OpenAPIOperationsProject
    if operations{if c.RootType!=""{return c,fmt.Errorf("project.native: an OpenAPI operations project has no payload root; configured root must be empty")};if c.NativeProject.Format()!=native.OpenAPI{return c,fmt.Errorf("project.native: an operations project must retain its OpenAPI origin")}}else{
        if !c.NativeProject.HasPayloadRoot(){return c,fmt.Errorf("project.native: native project target is incomplete")}
        root:=c.NativeProject.Root().TypeName;if c.RootType!=""&&c.RootType!=root{return c,fmt.Errorf("project.native: configured root disagrees with bundled root")};c.RootType=root
    }
    program,err:=language.Compile(c.NativeProject.EditableSource());if err!=nil{return c,err};c.Program=program;c.Wire=c.NativeProject.Metadata()
    if c.JavaPackage==""&&c.LogicalNamespace==""{c.LogicalNamespace=c.Wire.PublicationNamespace}
    if len(c.Formats)==0{return c,fmt.Errorf("project.native: explicitly select the native bundle's origin format; cross-format opaque constraints cannot yet be preserved")}
    for _,format:=range c.Formats{if format!=c.NativeProject.Format(){return c,fmt.Errorf("project.native: cannot preserve opaque %s constraints in %s",c.NativeProject.Format(),format)}}
    return c,nil
}

// Native exports keep the original URI-to-resource mapping. Filesystem names
// never derive from untrusted URIs, and neither dependencies nor wire metadata
// are discarded when the selected root is written as an ordinary schema.
func addNativeResources(files map[string][]byte,base string,p *native.Project,formats []native.Format)error{
    bundle,err:=p.Bundle();if err!=nil{return err};if err=addFile(files,path.Join(base,"contract.refined.json"),bundle);err!=nil{return err}
    for _,format:=range formats{for _,mode:=range []native.ExportMode{native.Ordinary,native.Refined}{
        exported,err:=p.Export(native.LowerOptions{Mode:mode,AllowDocumentedLoss:true});if err!=nil{return err}
        type mappedResource struct{URI string `json:"uri"`;Path string `json:"path"`}
        mappings:=[]mappedResource{};prefix:=string(mode)+"-"+string(format)
        for i,resource:=range exported.Resources(){name:=path.Join(prefix+"-resources",fmt.Sprintf("%04d.json",i));if resource.URI==exported.EntryResource(){name=prefix+".json"};if err=addFile(files,path.Join(base,name),[]byte(resource.Source));err!=nil{return err};mappings=append(mappings,mappedResource{URI:resource.URI,Path:name})}
        target:=exported.Target();var root *native.ResourceSelector;if target.Kind==native.PayloadProject{selected:=exported.Root();root=&selected}
        manifest:=struct{Format native.Format `json:"format"`;Version string `json:"version"`;Target native.ProjectTarget `json:"target"`;EntryResource string `json:"entryResource"`;Root *native.ResourceSelector `json:"root,omitempty"`;Metadata native.WireMetadata `json:"metadata"`;Resources []mappedResource `json:"resources"`;NativeConstraintSources []native.Resource `json:"nativeConstraintSources"`}{format,exported.Version(),target,exported.EntryResource(),root,exported.Metadata(),mappings,exported.NativeConstraintSources()}
        data,err:=json.MarshalIndent(manifest,"","  ");if err!=nil{return err};if err=addFile(files,path.Join(base,prefix+"-resources.json"),append(data,'\n'));err!=nil{return err}
        if mode==native.Ordinary&&exported.CompanionMarkdown()!=""{if err=addFile(files,path.Join(base,prefix+"-companion.md"),[]byte(exported.CompanionMarkdown()));err!=nil{return err}}
    }};return nil
}
