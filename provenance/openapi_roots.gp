package provenance

import (
    "sort"
    "strings"

    "goforge.dev/refine/schemajson"
)

// OpenAPISchemaRoot identifies a physical Schema Object root reached through a
// checked OpenAPI wrapper role. Schema keywords below this root deliberately
// remain the responsibility of a JSON Schema catalog and resolver.
type OpenAPISchemaRoot struct { Resource string; Pointer string; Dialect string }

// IndexOpenAPISchemaRoots returns the sorted, deduplicated physical Schema
// Object roots in an explicit OpenAPI resource closure. Every explicit
// Document is indexed under its own OpenAPI version and schema dialect.
// Wrapper references are resolved with the same role-aware traversal used by
// provenance discovery; Schema Object references, IDs, and anchors are not
// interpreted here.
func IndexOpenAPISchemaRoots(resources []OpenAPIResource,options OpenAPIOptions)([]OpenAPISchemaRoot,error){return indexOpenAPISchemaRootsWithPathLimit(resources,options,schemajson.DefaultBytes)}

func indexOpenAPISchemaRootsWithPathLimit(resources []OpenAPIResource,options OpenAPIOptions,pathLimit int)([]OpenAPISchemaRoot,error){
    if len(resources)==0{return nil,&Error{Code:"openapi.resources",Message:"at least one explicit OpenAPI resource is required"}}
    if len(resources)>openAPIProvenanceResources{return nil,&Error{Code:"openapi.limit",Message:"explicit resource count limit exceeded"}}
    if pathLimit<1{return nil,&Error{Code:"openapi.limit",Message:"OpenAPI wrapper traversal path limit must be positive"}}
    limits,err:=openAPIProvenanceLimits(options.Limits);if err!=nil{return nil,err}
    roots:=map[OpenAPISchemaRoot]bool{}
    walker:=&openAPIProvenanceWalker{docs:map[string]*openAPIProvenanceDoc{},constraintNames:map[string]bool{},seen:map[string]bool{},maxSteps:limits.Nodes,maxDepth:limits.Depth,maxRefs:limits.Nodes,maxRetainedBytes:pathLimit}
    walker.schemaRoot=func(node openAPIProvenanceNode,dialect string)error{roots[OpenAPISchemaRoot{Resource:node.doc.resource.URI,Pointer:node.pointer,Dialect:dialect}]=true;return nil}
    copied:=make([]OpenAPIResource,len(resources));uris:=map[string]bool{};totalBytes:=0
    for i,item:=range resources{copy:=copyOpenAPIResource(item);if err:=validateOpenAPIResource(copy,limits);err!=nil{return nil,err};if uris[copy.URI]{return nil,&Error{Code:"openapi.resources",Pointer:copy.URI,Message:"duplicate resource URI"}};uris[copy.URI]=true;if len(copy.Source)>limits.Bytes-totalBytes{return nil,&Error{Code:"openapi.limit",Pointer:copy.URI,Message:"aggregate resource byte limit exceeded"}};totalBytes+=len(copy.Source);copied[i]=copy}
    for _,copy:=range copied{doc,err:=parseOpenAPIProvenanceResource(copy,limits);if err!=nil{return nil,err};walker.docs[copy.URI]=doc}
    entry:=options.EntryResource;if entry==""{return nil,&Error{Code:"openapi.resources",Message:"EntryResource is required"}};entryDoc,ok:=walker.docs[entry];if !ok||entryDoc.resource.Role!=OpenAPIDocument{return nil,&Error{Code:"openapi.resources",Pointer:entry,Message:"entry resource must be an explicit OpenAPI document"}}
    version,err:=openAPIVersion(entryDoc.root);if err!=nil{return nil,err};walker.openAPI30=strings.HasPrefix(version,"3.0.");if !walker.openAPI30&&!strings.HasPrefix(version,"3.1.")&&!strings.HasPrefix(version,"3.2."){return nil,&Error{Code:"openapi.version",Pointer:entry+"#/openapi",Message:"schema-root indexing requires OpenAPI 3.0.x, 3.1.x, or 3.2.x"}};walker.openAPI32=strings.HasPrefix(version,"3.2.")
    dialect:=openAPIBase;if walker.openAPI30{dialect=openAPI30Dialect}else{if raw,ok:=yamlMappingValue(entryDoc.root,"jsonSchemaDialect");ok{dialect,err=yamlScalarString(raw);if err!=nil{return nil,&Error{Code:"openapi.dialect",Pointer:entry+"#/jsonSchemaDialect",Message:err.Error()}}};if err:=supportedOpenAPIDialect(dialect,entry+"#/jsonSchemaDialect");err!=nil{return nil,err}}
    if err:=walker.walkDocument(openAPIProvenanceNode{doc:entryDoc,node:entryDoc.root,pointer:""},dialect,0);err!=nil{return nil,err}
    documents:=[]string{};for _,item:=range copied{if item.Role==OpenAPIDocument&&item.URI!=entry{documents=append(documents,item.URI)}};sort.Strings(documents);for _,uri:=range documents{doc:=walker.docs[uri];if err:=walker.walkDocument(openAPIProvenanceNode{doc:doc,node:doc.root,pointer:""},dialect,0);err!=nil{return nil,err}}
    for _,item:=range copied{if item.Role!=OpenAPISchema{continue};if walker.openAPI30{return nil,&Error{Code:"openapi.resources",Pointer:item.URI,Message:"OpenAPI 3.0 external Schema Objects must be explicit referenced fragments, not standalone JSON Schema resources"}};doc:=walker.docs[item.URI];schemaDialect:=item.Dialect;if raw,ok:=yamlMappingValue(doc.root,"$schema");ok{declared,scalarErr:=yamlScalarString(raw);if scalarErr!=nil{return nil,&Error{Code:"openapi.dialect",Pointer:item.URI+"#/$schema",Message:scalarErr.Error()}};if schemaDialect!=""&&strings.TrimSuffix(schemaDialect,"#")!=strings.TrimSuffix(declared,"#"){return nil,&Error{Code:"openapi.dialect",Pointer:item.URI+"#/$schema",Message:"resource Dialect conflicts with its $schema"}};schemaDialect=declared};if schemaDialect==""{return nil,&Error{Code:"openapi.dialect",Pointer:item.URI,Message:"standalone schema resources require Dialect or a root $schema"}};if err:=supportedOpenAPIDialect(schemaDialect,item.URI+"#/$schema");err!=nil{return nil,err};root:=openAPIProvenanceNode{doc:doc,node:doc.root,pointer:""};if err:=walker.walkSchema(root,schemaDialect,item.URI,root,0);err!=nil{return nil,err}}
    out:=make([]OpenAPISchemaRoot,0,len(roots));for root:=range roots{out=append(out,root)};sort.Slice(out,func(i,j int)bool{if out[i].Resource!=out[j].Resource{return out[i].Resource<out[j].Resource};if out[i].Pointer!=out[j].Pointer{return out[i].Pointer<out[j].Pointer};return out[i].Dialect<out[j].Dialect});return out,nil
}
