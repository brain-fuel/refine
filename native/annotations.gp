package native

import (
    "fmt"

    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

func checkAnnotation(format Format,pointer,source,root string)(Annotation,error){
    program,err:=language.Compile(source);if err!=nil{return Annotation{},wrap(format,"native.refinement",pointer,err)}
    if root!=""{if _,err:=program.PayloadType(root);err!=nil{return Annotation{},wrap(format,"native.refinement",pointer+"/root",err)}}
    return Annotation{Pointer:pointer,Source:source,Root:root,Formatted:program.Formatted()},nil
}

func jsonAnnotation(format Format,pointer string,node schemajson.Node)(Annotation,error){
    if source,ok:=nodeString(node);ok{return checkAnnotation(format,pointer,source,"")}
    if schemajson.KindName(node.Kind())!="object"{return Annotation{},&Error{Code:"native.refinement",Format:format,Pointer:pointer,Message:"x-refine must be a source string or an object containing source and optional root strings"}}
    allowed:=map[string]bool{"source":true,"root":true};for _,member:=range node.Members(){key,err:=member.Key.UTF8();if err!=nil||!allowed[key]{return Annotation{},&Error{Code:"native.refinement",Format:format,Pointer:pointer,Message:"x-refine object permits only source and root"}}}
    sourceNode,ok:=node.Lookup("source");if !ok{return Annotation{},&Error{Code:"native.refinement",Format:format,Pointer:pointer,Message:"x-refine.source is required"}}
    source,ok:=nodeString(sourceNode);if !ok{return Annotation{},&Error{Code:"native.refinement",Format:format,Pointer:pointer+"/source",Message:"source must be a string"}}
    root:="";if rootNode,exists:=node.Lookup("root");exists{root,ok=nodeString(rootNode);if !ok{return Annotation{},&Error{Code:"native.refinement",Format:format,Pointer:pointer+"/root",Message:"root must be a string"}}}
    return checkAnnotation(format,pointer,source,root)
}

func jsonSchemaAnnotations(root schemajson.Node)([]Annotation,error){
    result:=[]Annotation{};var walk func(schemajson.Node,string)error
    walk=func(node schemajson.Node,path string)error{
        if schemajson.KindName(node.Kind())!="object"{return nil}
        if ext,ok:=node.Lookup("x-refine");ok{annotation,err:=jsonAnnotation(JSONSchema,path+"/x-refine",ext);if err!=nil{return err};result=append(result,annotation)}
        for _,key:=range []string{"additionalProperties","unevaluatedProperties","propertyNames","contains","items","unevaluatedItems","if","then","else","not","contentSchema"}{if child,ok:=node.Lookup(key);ok{if err:=walk(child,path+"/"+key);err!=nil{return err}}}
        for _,key:=range []string{"$defs","properties","patternProperties","dependentSchemas"}{if children,ok:=node.Lookup(key);ok&&schemajson.KindName(children.Kind())=="object"{for _,member:=range children.Members(){name,_:=member.Key.UTF8();if err:=walk(member.Value,path+"/"+key+"/"+escapePointer(name));err!=nil{return err}}}}
        for _,key:=range []string{"allOf","anyOf","oneOf","prefixItems"}{if children,ok:=node.Lookup(key);ok&&schemajson.KindName(children.Kind())=="array"{for i,child:=range children.Elements(){if err:=walk(child,fmt.Sprintf("%s/%s/%d",path,key,i));err!=nil{return err}}}}
        return nil
    }
    if err:=walk(root,"");err!=nil{return nil,err};return result,nil
}

func avroAnnotations(root schemajson.Node)([]Annotation,error){
    result:=[]Annotation{};var walk func(schemajson.Node,string)error
    walk=func(node schemajson.Node,path string)error{
        if schemajson.KindName(node.Kind())=="array"{for i,child:=range node.Elements(){if err:=walk(child,fmt.Sprintf("%s/%d",path,i));err!=nil{return err}};return nil}
        if schemajson.KindName(node.Kind())!="object"{return nil}
        if ext,ok:=node.Lookup("x-refine");ok{annotation,err:=jsonAnnotation(Avro,path+"/x-refine",ext);if err!=nil{return err};result=append(result,annotation)}
        typ,ok:=node.Lookup("type");if !ok{return nil};if schemajson.KindName(typ.Kind())!="string"{return walk(typ,path+"/type")};name,_:=nodeString(typ)
        switch name{
        case "record","error":if fields,ok:=node.Lookup("fields");ok&&schemajson.KindName(fields.Kind())=="array"{for i,field:=range fields.Elements(){if child,ok:=field.Lookup("type");ok{if err:=walk(child,fmt.Sprintf("%s/fields/%d/type",path,i));err!=nil{return err}}}}
        case "array":if child,ok:=node.Lookup("items");ok{return walk(child,path+"/items")}
        case "map":if child,ok:=node.Lookup("values");ok{return walk(child,path+"/values")}
        };return nil
    }
    if err:=walk(root,"");err!=nil{return nil,err};return result,nil
}

func yamlRootAnnotation(root *yaml.Node)([]Annotation,error){
    if root.Kind!=yaml.MappingNode{return nil,nil};for i:=0;i<len(root.Content);i+=2{if root.Content[i].Value=="x-refine"{source,rootType,err:=yamlAnnotationValue(root.Content[i+1],"/x-refine");if err!=nil{return nil,err};annotation,err:=checkAnnotation(OpenAPI,"/x-refine",source,rootType);if err!=nil{return nil,err};return []Annotation{annotation},nil}}
    return nil,nil
}

func yamlAnnotationValue(node *yaml.Node,pointer string)(string,string,error){
    if node.Kind==yaml.ScalarNode&&node.Tag=="!!str"{return node.Value,"",nil}
    if node.Kind!=yaml.MappingNode{return "","",&Error{Code:"native.refinement",Format:OpenAPI,Pointer:pointer,Message:"x-refine must be a source string or an object containing source and optional root strings"}}
    source,root:="","";seenSource:=false
    for i:=0;i<len(node.Content);i+=2{key,value:=node.Content[i].Value,node.Content[i+1];if key!="source"&&key!="root"{return "","",&Error{Code:"native.refinement",Format:OpenAPI,Pointer:pointer,Message:"x-refine object permits only source and root"}};if value.Kind!=yaml.ScalarNode||value.Tag!="!!str"{return "","",&Error{Code:"native.refinement",Format:OpenAPI,Pointer:pointer+"/"+key,Message:key+" must be a string"}};if key=="source"{source=value.Value;seenSource=true}else{root=value.Value}}
    if !seenSource{return "","",&Error{Code:"native.refinement",Format:OpenAPI,Pointer:pointer,Message:"x-refine.source is required"}}
    return source,root,nil
}
