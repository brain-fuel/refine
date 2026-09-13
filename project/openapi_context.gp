package project

import (
    "fmt"

    "goforge.dev/refine/java"
    "goforge.dev/refine/native"
)

const openAPIOperationsClass="RefineOpenAPIOperations"

func projectWireConfigured(metadata native.WireMetadata)bool{return metadata.PublicationNamespace!=""||metadata.NumericExpansion!=0||metadata.OpenAPI!=nil||metadata.Examples!=nil||len(metadata.Scalars)>0||len(metadata.ExtraFields)>0||len(metadata.Discriminators)>0}

func contractJavaSources(contract Contract,namespace,class string,formats []native.Format)([]java.File,error){
    if contract.NativeProject!=nil&&contract.NativeProject.Kind()==native.OpenAPIOperationsProject{configured,err:=nativeProjectWithNamespace(contract.NativeProject,namespace);if err!=nil{return nil,err};return java.GenerateProjectOpenAPIContext(configured,class,openAPIOperationsClass)}
    files,err:=contractSerde(contract,namespace,class,formats);if err!=nil{return nil,err};return mergeOpenAPIContext(contract,namespace,class,files)
}

func nativeProjectWithNamespace(project *native.Project,namespace string)(*native.Project,error){metadata:=project.Metadata();metadata.PublicationNamespace=namespace;return project.WithMetadata(metadata)}

// mergeOpenAPIContext deliberately regenerates the shared checked validator
// and requires byte-identical sources. A facade can never replace a model or
// serde runtime with a differently configured contract class.
func mergeOpenAPIContext(contract Contract,namespace,class string,files []java.File)([]java.File,error){
    if contract.Wire.OpenAPI==nil{return files,nil};var context []java.File;var err error;if contract.Wire.OpenAPI.Native!=nil{if contract.NativeProject==nil||!contract.NativeProject.HasOpenAPINativeBindings(){return nil,fmt.Errorf("native.enforcement: checked native OpenAPI operation bindings are required")};configured,configureErr:=nativeProjectWithNamespace(contract.NativeProject,namespace);if configureErr!=nil{return nil,configureErr};context,err=java.GenerateProjectOpenAPIContext(configured,class,openAPIOperationsClass)}else{context,err=java.GenerateOpenAPIContext(contract.Program,namespace,class,openAPIOperationsClass,*contract.Wire.OpenAPI)};if err!=nil{return nil,err};out:=append([]java.File(nil),files...);seen:=map[string]string{};for _,file:=range out{seen[file.Path]=file.Source}
    for _,file:=range context{if source,ok:=seen[file.Path];ok{if source!=file.Source{return nil,fmt.Errorf("project.openapi: operation facade disagrees on shared Java file %s",file.Path)};continue};seen[file.Path]=file.Source;out=append(out,file)};return out,nil
}
