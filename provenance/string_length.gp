package provenance

import (
    "encoding/json"

    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/value"
)

// JSON Schema counts Unicode code points for minLength/maxLength. The
// language String representation deliberately retains UTF-16 code units, so
// only the explicit codePointLength builtin has the same measure; length must
// never be substituted here.
func (s *JSONSchema)stringLengthConstraint(node schemajson.Node,path,key string,bound schemajson.Node)(bool,error){
    operator:="";switch key{case "minLength":operator=">=";case "maxLength":operator="<=";default:return false,nil};where:=pointer(path,key)
    if schemajson.KindName(bound.Kind())!="number"{return true,&Error{Code:"native.string_length",Pointer:where,Message:"string length bounds must be nonnegative integers"}}
    expansion,err:=jsonNumberExpansion(bound.Raw(),maxJSONNumericExpansion);if valueLimit(err){return true,nil};if err!=nil{return true,err};if expansion>maxJSONNumericExpansion-s.numericExpansion{return true,nil};s.numericExpansion+=expansion
    number,err:=value.ParseNumber(bound.Raw());if err!=nil||!number.IsInteger()||number.Sign()<0{return true,&Error{Code:"native.string_length",Pointer:where,Message:"string length bounds must be nonnegative integers"}}
    if !jsonSchemaExplicitString(node){return true,nil};expression,err:=language.ParseExpression("codePointLength it "+operator+" "+number.Show());if err!=nil{return true,err}
    err=s.addConstraint(path,where,key,"String",language.FormatExpression(expression),bound.Raw(),[]string{"codePointLength"});if valueLimit(err){return true,nil};return true,err
}

func jsonSchemaExplicitString(node schemajson.Node)bool{typ,ok:=node.Lookup("type");if !ok{return false};if schemajson.KindName(typ.Kind())=="array"{if typ.ElementCount()!=1{return false};typ=typ.Elements()[0]};name,ok:=scalar(typ);return ok&&name=="string"}

func (w *openAPIProvenanceWalker)discoverStringLengthAssertions(node openAPIProvenanceNode,dialect string)error{
    if !openAPIExplicitString(node.node){return nil};if w.openAPI30{if nullable,present:=openAPIChild(node,"nullable");present{enabled,exact:=openAPIExactBoolean(nullable);if !exact||enabled{return nil}}}
    encodedDomain,_:=json.Marshal("string");builder:=&JSONSchema{maxValueNodes:1000000,maxValueDepth:508,numericExpansion:w.cardinalityExpansion};defer func(){w.cardinalityExpansion=builder.numericExpansion}()
    for _,keyword:=range []string{"minLength","maxLength"}{bound,ok:=openAPIChild(node,keyword);if !ok{continue};raw,normalized,exact:=openAPINumericToken(bound);if !exact{continue};encodedKey,_:=json.Marshal(keyword);document,err:=schemajson.Parse([]byte("{\"type\":"+string(encodedDomain)+","+string(encodedKey)+":"+normalized+"}"),schemajson.Limits{});if err!=nil{return err};value,_:=document.Root().Lookup(keyword);prior:=len(builder.constraints);if _,err:=builder.stringLengthConstraint(document.Root(),"",keyword,value);err!=nil{return err};if len(builder.constraints)==prior{continue};constraint:=builder.constraints[prior];if err:=w.add(node,keyword,constraint.Scope,constraint.Predicate,raw,dialect,constraint.Builtins);err!=nil{return err}}
    return nil
}

func openAPIExplicitString(node *yaml.Node)bool{typ,ok:=yamlMappingValue(node,"type");if !ok{return false};if typ.Kind==yaml.SequenceNode{if len(typ.Content)!=1{return false};typ=typ.Content[0]};name,err:=yamlScalarString(typ);return err==nil&&name=="string"}
