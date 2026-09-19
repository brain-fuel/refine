package provenance

import (
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

// discoverOpenAPIJSONExactAssertions projects only exact JSON-source values.
// OpenAPI 3.0 admits enum but not const; 3.1/3.2 call this with both keywords.
// YAML values remain opaque until their complete lexical JSON mapping has a
// separately bounded correspondence.
func (w *openAPIProvenanceWalker) discoverOpenAPIJSONExactAssertions(node openAPIProvenanceNode,dialect string,keywords []string)error{
    if !node.doc.isJSON{return nil}
    jsonNode,err:=node.doc.json.At(node.pointer);if err!=nil{return err};builder:=&JSONSchema{maxValueNodes:1000000,maxValueDepth:508}
    for _,keyword:=range keywords{
        value,ok:=jsonNode.Lookup(keyword);if !ok{continue};values:=[]schemajson.Node{value}
        if keyword=="enum"{if schemajson.KindName(value.Kind())!="array"{return &Error{Code:"openapi.assertion",Pointer:node.doc.resource.URI+"#"+node.pointer+"/enum",Message:"enum must be an array"}};values=value.Elements()}
        expressions:=make([]*language.Expr,len(values));projectable:=true
        for i,item:=range values{expression,buildErr:=builder.canonicalJSONValue(item,2);if valueLimit(buildErr){projectable=false;break};if buildErr!=nil{return buildErr};expressions[i]=expression};if !projectable{continue}
        var predicate *language.Expr;builtins:=[]string{}
        if keyword=="const"{predicate=&language.Expr{Form:language.Binary("==",&language.Expr{Form:language.Variable("it")},expressions[0])}}else{predicate=&language.Expr{Form:language.Apply(&language.Expr{Form:language.Apply(&language.Expr{Form:language.Variable("oneOf")},&language.Expr{Form:language.Variable("it")})},&language.Expr{Form:language.ListLiteral(expressions)})};builtins=[]string{"oneOf"}}
        if err:=w.add(node,keyword,"JSON",language.FormatExpression(predicate),value.Raw(),dialect,builtins);err!=nil{return err}
    }
    return nil
}
