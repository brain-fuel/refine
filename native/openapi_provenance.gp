package native

import (
    "errors"
    "sort"
    "strings"

    "goforge.dev/refine/provenance"
    "goforge.dev/refine/schemajson"
)

// openAPIConstraintOrigin scopes a multi-resource OpenAPI discovery result to
// one immutable resource. Generated declaration identities remain globally
// resource-qualified, while bundle edits stay independently addressable.
type openAPIConstraintOrigin struct {
    projection *provenance.OpenAPI
    resource string
    constraints []provenance.Constraint
}

func copyOpenAPIOriginConstraint(in provenance.Constraint)provenance.Constraint{in.Builtins=append([]string(nil),in.Builtins...);return in}
func (o *openAPIConstraintOrigin)Constraints()[]provenance.Constraint{if o==nil{return nil};out:=make([]provenance.Constraint,len(o.constraints));for i,item:=range o.constraints{out[i]=copyOpenAPIOriginConstraint(item)};return out}
func (o *openAPIConstraintOrigin)ConstraintSource()string{if o==nil{return ""};var source strings.Builder;for _,constraint:=range o.constraints{source.WriteString("type "+constraint.Name+" = "+constraint.Scope+" where "+constraint.Predicate+"\n")};return source.String()}
func (o *openAPIConstraintOrigin)AuditSource(source string)([]provenance.Finding,error){if o==nil||o.projection==nil{return nil,errors.New("OpenAPI provenance is absent")};return o.projection.AuditResourceSource(o.resource,source)}
func (o *openAPIConstraintOrigin)RecoverNative(name,source string)(string,error){if o==nil||o.projection==nil{return "",errors.New("OpenAPI provenance is absent")};return o.projection.RecoverResourceNative(o.resource,name,source)}

// Modern OpenAPI provenance consumes the same physical Schema Object catalog
// as validation. Unsupported lexical constraints stay opaque; catalog and
// resource-limit failures must not silently erase supported correspondence.
func discoverOpenAPIConstraintOrigins(resources []Resource,entry string)(map[string]nativeConstraintOrigin,map[string]string,error){
    inputs:=make([]provenance.OpenAPIResource,len(resources))
    canonical:=make([]Resource,len(resources));modern:=false
    for i,resource:=range resources{
        syntax:=provenance.OpenAPIYAML;if _,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});err==nil{syntax=provenance.OpenAPIJSON}
        encoded,err:=openAPIResourceJSON([]byte(resource.Source));if err!=nil{return nil,nil,err};canonical[i]=Resource{URI:resource.URI,Source:string(encoded)};doc,err:=schemajson.Parse(encoded,schemajson.Limits{});if err!=nil{return nil,nil,err}
        role:=provenance.OpenAPIFragment;if versionNode,ok:=doc.Root().Lookup("openapi");ok{role=provenance.OpenAPIDocument;if resource.URI==entry{version,_:=nodeString(versionNode);modern=strings.HasPrefix(version,"3.1.")||strings.HasPrefix(version,"3.2.")}}else if _,ok:=doc.Root().Lookup("$schema");ok{role=provenance.OpenAPISchema}
        inputs[i]=provenance.OpenAPIResource{URI:resource.URI,Source:[]byte(resource.Source),Syntax:syntax,Role:role}
    }
    var projection *provenance.OpenAPI;var err error
    if modern{catalog,problem:=newOpenAPIProjectionCatalog(canonical,entry);if problem!=nil{return nil,nil,problem};keys:=make([]string,0,len(catalog.locations));for key:=range catalog.locations{keys=append(keys,key)};sort.Strings(keys);locations:=make([]provenance.OpenAPISchemaRoot,0,len(keys));for _,key:=range keys{node:=catalog.locations[key];locations=append(locations,provenance.OpenAPISchemaRoot{Resource:node.resource,Pointer:node.pointer,Dialect:node.dialect})};projection,err=provenance.DiscoverOpenAPIIndexed(inputs,provenance.OpenAPIOptions{EntryResource:entry},locations);if err!=nil{return nil,nil,wrap(OpenAPI,"native.provenance",entry,err)}}else{projection,err=provenance.DiscoverOpenAPI(inputs,provenance.OpenAPIOptions{EntryResource:entry});if err!=nil{return map[string]nativeConstraintOrigin{},map[string]string{},nil}}
    grouped:=map[string][]provenance.Constraint{};for _,constraint:=range projection.Constraints(){grouped[constraint.Resource]=append(grouped[constraint.Resource],constraint)}
    origins:=map[string]nativeConstraintOrigin{};units:=map[string]string{}
    for _,resource:=range resources{constraints:=grouped[resource.URI];if len(constraints)==0{continue};origin:=&openAPIConstraintOrigin{projection:projection,resource:resource.URI,constraints:constraints};origins[resource.URI]=origin;units[resource.URI]=origin.ConstraintSource()}
    return origins,units,nil
}

func installOpenAPIConstraintOrigins(project *Project,entry string)error{
    if project==nil||project.Format()!=OpenAPI{return nil}
    origins,units,err:=discoverOpenAPIConstraintOrigins(project.resources,entry);if err!=nil{return err};project.nativeOrigins=origins
    if project.nativeUnitSources==nil{project.nativeUnitSources=map[string]string{}};if project.nativeUnitsInEditable==nil{project.nativeUnitsInEditable=map[string]bool{}}
    for resource,source:=range units{project.nativeUnitSources[resource]=source;project.nativeUnitsInEditable[resource]=false}
    return nil
}
