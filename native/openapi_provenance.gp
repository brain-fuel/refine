package native

import (
    "errors"
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

// discoverOpenAPIConstraintOrigins is deliberately best-effort. Native
// ingestion has already validated the complete OpenAPI resource closure.
// Provenance's smaller exact subset (3.1/3.2, supported dialects/references and
// lexical forms) must never make another valid native project unimportable.
func discoverOpenAPIConstraintOrigins(resources []Resource,entry string)(map[string]nativeConstraintOrigin,map[string]string){
    inputs:=make([]provenance.OpenAPIResource,len(resources))
    for i,resource:=range resources{
        syntax:=provenance.OpenAPIYAML;if _,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});err==nil{syntax=provenance.OpenAPIJSON}
        role:=provenance.OpenAPIFragment;if resource.URI==entry{role=provenance.OpenAPIDocument}
        inputs[i]=provenance.OpenAPIResource{URI:resource.URI,Source:[]byte(resource.Source),Syntax:syntax,Role:role}
    }
    projection,err:=provenance.DiscoverOpenAPI(inputs,provenance.OpenAPIOptions{EntryResource:entry});if err!=nil{return map[string]nativeConstraintOrigin{},map[string]string{}}
    grouped:=map[string][]provenance.Constraint{};for _,constraint:=range projection.Constraints(){grouped[constraint.Resource]=append(grouped[constraint.Resource],constraint)}
    origins:=map[string]nativeConstraintOrigin{};units:=map[string]string{}
    for _,resource:=range resources{constraints:=grouped[resource.URI];if len(constraints)==0{continue};origin:=&openAPIConstraintOrigin{projection:projection,resource:resource.URI,constraints:constraints};origins[resource.URI]=origin;units[resource.URI]=origin.ConstraintSource()}
    return origins,units
}

func installOpenAPIConstraintOrigins(project *Project,entry string){
    if project==nil||project.Format()!=OpenAPI{return}
    origins,units:=discoverOpenAPIConstraintOrigins(project.resources,entry);project.nativeOrigins=origins
    if project.nativeUnitSources==nil{project.nativeUnitSources=map[string]string{}};if project.nativeUnitsInEditable==nil{project.nativeUnitsInEditable=map[string]bool{}}
    for resource,source:=range units{project.nativeUnitSources[resource]=source;project.nativeUnitsInEditable[resource]=false}
}
