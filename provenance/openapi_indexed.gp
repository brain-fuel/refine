package provenance

import (
    "sort"
    "strconv"
    "strings"

    yaml "github.com/oasdiff/yaml3"
)

type openAPIIndexedTrie struct { pointer string;children map[string]*openAPIIndexedTrie;location *OpenAPISchemaRoot }

// DiscoverOpenAPIIndexed discovers lexical constraint units at explicitly
// supplied, already schema-checked physical locations. It does not resolve
// references or validate an OpenAPI document. Embedders must obtain locations
// and effective dialects from a complete schema-aware resource catalog, never
// from a recursive search for keyword-shaped instance data. This separation
// lets native validators share one reference authority with provenance.
func DiscoverOpenAPIIndexed(resources []OpenAPIResource,options OpenAPIOptions,locations []OpenAPISchemaRoot)(*OpenAPI,error){
    limits,err:=openAPIProvenanceLimits(options.Limits);if err!=nil{return nil,err}
    limited:=func()error{return &Error{Code:"openapi.limit",Message:"indexed OpenAPI provenance exceeds its aggregate work or retained-path limit"}}
    if len(resources)==0||len(resources)>openAPIProvenanceResources||len(locations)>limits.Nodes{return nil,limited()}
    copied:=make([]OpenAPIResource,len(resources));walker:=&openAPIProvenanceWalker{docs:map[string]*openAPIProvenanceDoc{},constraintNames:map[string]bool{},seen:map[string]bool{},maxSteps:limits.Nodes,maxDepth:limits.Depth,maxRetainedBytes:limits.Bytes};total:=0
    for i,item:=range resources{if err:=validateOpenAPIResource(item,limits);err!=nil{return nil,err};if len(item.Source)>limits.Bytes-total{return nil,limited()};total+=len(item.Source);if _,duplicate:=walker.docs[item.URI];duplicate{return nil,&Error{Code:"openapi.resources",Message:"duplicate indexed provenance resource URI"}};copied[i]=copyOpenAPIResource(item);doc,err:=parseOpenAPIProvenanceResource(copied[i],limits);if err!=nil{return nil,err};walker.docs[item.URI]=doc}
    entry,ok:=walker.docs[options.EntryResource];if !ok||entry.resource.Role!=OpenAPIDocument{return nil,&Error{Code:"openapi.resources",Message:"indexed provenance requires an explicit OpenAPI entry document"}};version,err:=openAPIVersion(entry.root);if err!=nil{return nil,err};if !strings.HasPrefix(version,"3.1.")&&!strings.HasPrefix(version,"3.2."){return nil,&Error{Code:"openapi.version",Message:"indexed provenance requires OpenAPI 3.1 or 3.2"}}
    tries:=map[string]*openAPIIndexedTrie{};retained:=0;work:=0;charge:=func(size int)error{if size<0||size>limits.Bytes-retained{return limited()};retained+=size;return nil};step:=func(count int)error{if count<0||count>limits.Nodes-work{return limited()};work+=count;return nil}
    for _,location:=range locations{
        if err:=step(1);err!=nil{return nil,err};if err:=charge(len(location.Resource)+len(location.Pointer)+len(location.Dialect));err!=nil{return nil,err}
        if _,exists:=walker.docs[location.Resource];!exists{return nil,&Error{Code:"openapi.resources",Pointer:location.Resource,Message:"indexed schema resource is absent"}};if err:=supportedOpenAPIDialect(location.Dialect,location.Resource+"#"+location.Pointer);err!=nil{return nil,err}
        root:=tries[location.Resource];if root==nil{root=&openAPIIndexedTrie{children:map[string]*openAPIIndexedTrie{}};tries[location.Resource]=root};tokens,err:=openAPIPointerTokens(location.Pointer);if err!=nil{return nil,err};current:=root
        for _,token:=range tokens{if err:=step(1);err!=nil{return nil,err};child:=current.children[token];if child==nil{size:=len(current.pointer)+1+len(token);for _,r:=range token{if r=='~'||r=='/'{size++}};if err:=charge(size);err!=nil{return nil,err};child=&openAPIIndexedTrie{pointer:current.pointer+"/"+pointerKeyOpenAPI(token),children:map[string]*openAPIIndexedTrie{}};current.children[token]=child};current=child}
        if current.location!=nil{if strings.TrimSuffix(current.location.Dialect,"#")!=strings.TrimSuffix(location.Dialect,"#"){return nil,&Error{Code:"openapi.dialect",Message:"indexed schema has conflicting effective dialects"}};continue};copy:=location;current.location=&copy
    }
    var visit func(*openAPIProvenanceDoc,*yaml.Node,*openAPIIndexedTrie)error
    visit=func(doc *openAPIProvenanceDoc,node *yaml.Node,trie *openAPIIndexedTrie)error{
        if err:=step(1);err!=nil{return err}
        if trie.location!=nil{kind:=node.ShortTag();if node.Kind==yaml.MappingNode{dialect:=trie.location.Dialect;if declared,ok:=yamlMappingValue(node,"$schema");ok{actual,err:=yamlScalarString(declared);if err!=nil||strings.TrimSuffix(actual,"#")!=strings.TrimSuffix(dialect,"#"){return &Error{Code:"openapi.dialect",Pointer:doc.resource.URI+"#"+trie.pointer,Message:"indexed dialect conflicts with explicit $schema"}}};if err:=walker.discoverSchemaAssertions(openAPIProvenanceNode{doc:doc,node:node,pointer:trie.pointer},dialect);err!=nil{return err}}else if node.Kind!=yaml.ScalarNode||kind!="!!bool"{return &Error{Code:"openapi.position",Pointer:doc.resource.URI+"#"+trie.pointer,Message:"indexed position is not an object or Boolean schema"}}}
        if len(trie.children)==0{return nil};found:=0
        switch node.Kind{case yaml.MappingNode:if err:=step(len(node.Content)/2);err!=nil{return err};for i:=0;i<len(node.Content);i+=2{if child:=trie.children[node.Content[i].Value];child!=nil{found++;if err:=visit(doc,node.Content[i+1],child);err!=nil{return err}}};case yaml.SequenceNode:if err:=step(len(node.Content));err!=nil{return err};for index,nodeChild:=range node.Content{if child:=trie.children[strconv.Itoa(index)];child!=nil{found++;if err:=visit(doc,nodeChild,child);err!=nil{return err}}}}
        if found!=len(trie.children){return &Error{Code:"openapi.position",Pointer:doc.resource.URI+"#"+trie.pointer,Message:"indexed schema pointer does not exist"}};return nil
    }
    uris:=make([]string,0,len(tries));for uri:=range tries{uris=append(uris,uri)};sort.Strings(uris);for _,uri:=range uris{if err:=visit(walker.docs[uri],walker.docs[uri].root,tries[uri]);err!=nil{return nil,err}}
    sort.Slice(walker.constraints,func(i,j int)bool{a,b:=walker.constraints[i],walker.constraints[j];if a.Resource!=b.Resource{return a.Resource<b.Resource};if a.Pointer!=b.Pointer{return a.Pointer<b.Pointer};return a.Keyword<b.Keyword});grouped:=map[string][]Constraint{};for _,constraint:=range walker.constraints{grouped[constraint.Resource]=append(grouped[constraint.Resource],constraint)};return &OpenAPI{resources:copied,constraints:walker.constraints,constraintsByResource:grouped},nil
}
