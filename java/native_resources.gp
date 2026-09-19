package java

import (
    "goforge.dev/refine/internal/ecmaregex"
    "goforge.dev/refine/native"
)

// Resource is a non-source output required by generated Java. Its path is a
// classpath-relative slash-separated name and Content is always a defensive
// copy. It is deliberately separate from File's Java-source-only contract.
type Resource struct { Path string; Content []byte }

// GenerateProjectNativeJSONResources returns the checked runtime resources
// required by GenerateProjectNativeJSONValidator, GenerateProjectJSONSerde,
// and GenerateProjectOpenAPIContext. Callers writing sources directly must
// place these at their exact classpath-relative paths. Project generation does
// this automatically. Schemas without native patterns return no resources and
// acquire no Chicory linkage.
func GenerateProjectNativeJSONResources(project *native.Project)([]Resource,error){
    if project==nil{return nil,&GenerationError{Message:"a checked native project is required"}}
    if project.Format()==native.Avro{return nil,&GenerationError{Message:"Avro has no native JSON validator resources"}}
    locations,err:=project.JSONSchemaKeywordLocations("pattern","patternProperties");if err!=nil{return nil,&GenerationError{Message:"native schema-position indexing failed: "+err.Error()}}
    if len(locations)==0{return nil,nil}
    directory:=nativeRegexArtifactDirectory
    return []Resource{
        {Path:directory+"/refine-ecma262.wasm",Content:ecmaregex.Artifact()},
        {Path:directory+"/NOTICE.txt",Content:ecmaregex.DistributionNotice()},
        {Path:directory+"/manifest.json",Content:ecmaregex.DistributionManifest()},
    },nil
}
