package native

import (
    "errors"
    "net/url"
    "sort"

    "goforge.dev/refine/analysis"
    "goforge.dev/refine/validation"
)

func copySchemaReport(in analysis.SchemaReport)analysis.SchemaReport{out:=analysis.SchemaReport{Roots:append([]string(nil),in.Roots...),Findings:append([]analysis.SchemaFinding(nil),in.Findings...)};return out}

// SchemaEntrypoints returns the selected payload root together with every
// explicitly bound OpenAPI request, response and context type. The result is
// sorted and duplicate-free so proof scope is independent of metadata order.
func SchemaEntrypoints(root string,metadata WireMetadata)[]string{selected:=map[string]bool{};if root!=""{selected[root]=true};if metadata.OpenAPI!=nil{for _,operation:=range metadata.OpenAPI.Operations{if operation.RequestType!=""{selected[operation.RequestType]=true};for _,response:=range operation.Responses{if response.ResponseType!=""{selected[response.ResponseType]=true};if response.ContextType!=""{selected[response.ContextType]=true}}}};result:=make([]string,0,len(selected));for name:=range selected{result=append(result,name)};sort.Strings(result);return result}

// SchemaChecks returns the deterministic satisfiability classification for
// every checked declaration and the explicit entrypoints used as rejection
// gates. Unknown is retained as unknown and must not be presented as proof.
func (p *Project) SchemaChecks()analysis.SchemaReport{if p==nil{return analysis.SchemaReport{}};return copySchemaReport(p.schemaChecks)}

// validateProject is the single post-compilation gate shared by ingestion and
// edits. A proven-empty selected payload or explicitly bound OpenAPI type
// rejects; impossible unused declarations remain reported without making an
// inhabitable project fail. Conservative unknowns remain inspectable. Avro's
// exact reader-default checks run only after this scoped language gate.
func validateProject(p *Project)(*Project,error){if p==nil||p.program==nil{return nil,&Error{Code:"native.project",Message:"a checked project is required"}};if err:=normalizeAndValidateProjectTarget(p);err!=nil{return nil,err};root:="";if p.HasPayloadRoot(){root=p.root.TypeName};report,err:=analysis.CheckSchemaRoots(p.program,SchemaEntrypoints(root,p.metadata),validation.Limits{});p.schemaChecks=copySchemaReport(report);if err!=nil{var proof *analysis.SchemaError;if errors.As(err,&proof){return nil,&Error{Code:"native.schema",Format:p.Format(),Pointer:proof.Type,Message:proof.Error(),Cause:err}};return nil,wrap(p.Format(),"native.schema","",err)};checked,err:=validateAvroRefinementDefaults(p);if err!=nil{return nil,err};return validateOpenAPINativeBindings(checked)}

func normalizeAndValidateProjectTarget(p *Project)error{target:=normalizedProjectTarget(p.target,p.root);switch target.Kind{case PayloadProject:if target.Root!=p.root||target.Resource!=p.root.Resource||p.root.Resource==""||p.root.TypeName==""{return &Error{Code:"native.root",Format:p.Format(),Message:"payload project target must exactly identify its selected root"}};p.target=target;case OpenAPIOperationsProject:parsed,err:=url.Parse(target.Resource);if p.Format()!=OpenAPI||err!=nil||!parsed.IsAbs()||parsed.Fragment!=""||target.Root!=(ResourceSelector{})||p.root!=(ResourceSelector{}){return &Error{Code:"native.root",Format:p.Format(),Pointer:target.Resource,Message:"operations project target must identify one absolute OpenAPI entry resource and must not contain a payload root"}};found:=false;for _,resource:=range p.resources{if resource.URI==target.Resource{found=true;break}};if !found{return &Error{Code:"native.resource",Format:OpenAPI,Pointer:target.Resource,Message:"OpenAPI entry resource is absent"}};p.target=target;default:return &Error{Code:"native.project",Format:p.Format(),Message:"unknown project target kind"}};return nil}
