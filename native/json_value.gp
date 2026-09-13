package native

import (
    "fmt"

    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/value"
)

// jsonValue decodes the intrinsic JSON algebra without erasing token kinds or
// imposing a discriminator on native JSON. The current node was charged by
// decode; recursive children share the same decoder and ordering budgets.
func (d *jsonValueDecoder) jsonValue(node schemajson.Node,path string,depth int)(value.Data,error){
    if depth>d.maxDepth{return value.Data{},d.limit(path,"JSON value nesting exceeds the checked decoder limit")}
    switch schemajson.KindName(node.Kind()){
    case "null":return value.Variant("JSONNull",nil)
    case "boolean":return value.Variant("JSONBoolean",[]value.Data{value.OfBool(node.Raw()=="true")})
    case "number":number,err:=d.number(node,path,false);if err!=nil{return value.Data{},err};return value.Variant("JSONNumber",[]value.Data{number})
    case "string":text,_:=node.Text();if _,err:=text.UTF8();err!=nil{return value.Data{},d.failure(path,"JSON string is not Unicode scalar text")};return value.Variant("JSONString",[]value.Data{value.OfText(text)})
    case "array":
        count:=node.ElementCount();if count>d.maxNodes-d.nodes{return value.Data{},d.limit(path,"JSON array exceeds the remaining checked decoder node limit")};elements:=node.Elements();items:=make([]value.Data,count)
        for i,child:=range elements{childPath:=jsonValuePath(path,fmt.Sprint(i));if err:=d.enter(childPath,depth+1);err!=nil{return value.Data{},err};item,err:=d.jsonValue(child,childPath,depth+1);if err!=nil{return value.Data{},err};items[i]=item};return value.Variant("JSONArray",[]value.Data{value.List(items)})
    case "object":
        count:=node.MemberCount();if count>d.maxNodes-d.nodes{return value.Data{},d.limit(path,"JSON object exceeds the remaining checked decoder node limit")};members:=node.Members();entries:=make([]value.MapEntry,count)
        for i,member:=range members{name,err:=member.Key.UTF8();if err!=nil{return value.Data{},d.failure(path,"JSON object key is not Unicode scalar text")};childPath:=jsonValuePath(path,name);if err=d.enter(childPath,depth+1);err!=nil{return value.Data{},err};item,err:=d.jsonValue(member.Value,childPath,depth+1);if err!=nil{return value.Data{},err};entries[i]=value.MapEntry{Key:member.Key,Value:item}}
        if err:=consumeNativeMapOrdering(d.format,path,entries,&d.mapOrderingUsed,nativeMapOrderingWorkLimit);err!=nil{return value.Data{},err};mapping,err:=value.Map(entries);if err!=nil{return value.Data{},d.failure(path,"JSON object contains duplicate decoded keys")};return value.Variant("JSONObject",[]value.Data{mapping})
    }
    return value.Data{},d.failure(path,"unsupported intrinsic JSON token kind")
}
