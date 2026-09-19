package java

import (
    "fmt"
    "sort"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
    "goforge.dev/refine/schemajson"
)

const nativeStringPropertyDefaultLength=24
const nativeStringPropertyMaximumLength=1024
const nativeStringValidationMaximumLength=1<<20
const nativeStringTypeWork=512

type nativeStringPattern struct { alphabet []int; minimum int; maximum int }

// GenerateProjectPropertyTests retains the ordinary property suite and only
// specializes its raw root generator when the authoritative native Schema
// Object proves a small ASCII language. Every emitted candidate still passes
// through the generated native adapter and Refine validator.
func GenerateProjectPropertyTests(project *native.Project,namespace,contractName string,options PropertyTestOptions)([]File,error){
    if project==nil{return nil,&GenerationError{Message:"a checked native project is required for project properties"}}
    program,err:=language.Compile(project.EditableSource());if err!=nil{return nil,err}
    overrides:=map[string]string{};if source,ok:=nativeRootStringPropertyGenerator(project,program);ok{overrides[project.Root().TypeName]=source}
    return generatePropertyTests(program,namespace,contractName,options,overrides)
}

func nativeRootStringPropertyGenerator(project *native.Project,program *language.Program)(string,bool){
    if project==nil||program==nil{return "",false};format:=project.Format();if format!=native.JSONSchema&&format!=native.OpenAPI{return "",false}
    root:=project.Root();if root.TypeName==""||!nativeStringSemanticTarget(program,root.TypeName){return "",false}
    resources,err:=project.CanonicalJSONResources();if err!=nil{return "",false};var source string;found:=false
    for _,resource:=range resources{if resource.URI==root.Resource{source=resource.Source;found=true;break}}
    if !found{return "",false};document,err:=schemajson.Parse([]byte(source),schemajson.Limits{});if err!=nil{return "",false};node,err:=document.At(root.Pointer);if err!=nil{return "",false}
    strategy,ok:=nativeStringPatternAt(node);if !ok{return "",false};parts:=make([]string,len(strategy.alphabet));for i,item:=range strategy.alphabet{parts[i]=fmt.Sprintf("(char)%d",item)}
    return fmt.Sprintf("org.jetbrains.jetCheck.Generator.stringsOf(org.jetbrains.jetCheck.IntDistribution.uniform(%d,%d),org.jetbrains.jetCheck.Generator.<Character>sampledFrom(%s)).<Data>map(Data.Text::new)",strategy.minimum,strategy.maximum,strings.Join(parts,",")),true
}

func nativeStringSemanticTarget(program *language.Program,target string)bool{
    declarations:=map[string]language.TypeDecl{};for _,decl:=range program.Syntax().Types{declarations[decl.Name]=decl};work:=0
    return nativeStringSemanticType(&language.Type{Form:language.NamedType(target)},declarations,&work)
}
func nativeStringSemanticType(typ *language.Type,declarations map[string]language.TypeDecl,work *int)bool{
    if typ==nil{return false};*work++;if *work>nativeStringTypeWork{return false}
    match typ.Form{
    case language.RefinedType(base,_):return nativeStringSemanticType(base,declarations,work)
    case language.NamedType(name):
        if name=="String"{return true};decl,ok:=declarations[name];if !ok||len(decl.Parameters)!=0||decl.Body==nil{return false};return nativeStringSemanticType(decl.Body,declarations,work)
    case language.AppliedType(_,_):
        name,args:=applied(typ);decl,ok:=declarations[name];if !ok||decl.Body==nil||len(args)!=len(decl.Parameters){return false};bindings:=map[string]*language.Type{};for i,parameter:=range decl.Parameters{bindings[parameter]=args[i]};closed,err:=language.SubstituteTypeBounded(decl.Body,bindings,nativeStringTypeWork-*work);if err!=nil{return false};return nativeStringSemanticType(closed,declarations,work)
    case _:return false
    }
}

func nativeStringPatternAt(node schemajson.Node)(nativeStringPattern,bool){
    if schemajson.KindName(node.Kind())!="object"||node.MemberCount()>32{return nativeStringPattern{},false};allowed:=map[string]bool{"$schema":true,"$id":true,"$anchor":true,"$comment":true,"title":true,"description":true,"default":true,"examples":true,"deprecated":true,"readOnly":true,"writeOnly":true,"x-refine":true,"type":true,"pattern":true,"minLength":true,"maxLength":true}
    for _,member:=range node.Members(){key,err:=member.Key.UTF8();if err!=nil||!allowed[key]{return nativeStringPattern{},false}}
    typeNode,ok:=node.Lookup("type");if !ok{return nativeStringPattern{},false};kind,ok:=nativeStringNodeText(typeNode);if !ok||kind!="string"{return nativeStringPattern{},false}
    patternNode,ok:=node.Lookup("pattern");if !ok{return nativeStringPattern{},false};pattern,ok:=nativeStringNodeText(patternNode);if !ok{return nativeStringPattern{},false};result,ok:=parseNativeStringPattern(pattern);if !ok{return nativeStringPattern{},false}
    minimum:=0;if item,exists:=node.Lookup("minLength");exists{var valid bool;minimum,valid=nativeStringLength(item);if !valid||minimum>nativeStringValidationMaximumLength{return nativeStringPattern{},false}}
    maximum:=nativeStringValidationMaximumLength;if item,exists:=node.Lookup("maxLength");exists{var valid bool;maximum,valid=nativeStringLength(item);if !valid{return nativeStringPattern{},false};if maximum>nativeStringValidationMaximumLength{maximum=nativeStringValidationMaximumLength}}
    if minimum>result.minimum{result.minimum=minimum};if result.maximum<0||maximum<result.maximum{result.maximum=maximum};if result.minimum>result.maximum||result.minimum>nativeStringPropertyMaximumLength{return nativeStringPattern{},false}
    generatedMaximum:=nativeStringPropertyDefaultLength;if generatedMaximum<result.minimum{generatedMaximum=result.minimum};if generatedMaximum>result.maximum{generatedMaximum=result.maximum};if generatedMaximum>nativeStringPropertyMaximumLength{generatedMaximum=nativeStringPropertyMaximumLength};result.maximum=generatedMaximum
    return result,result.minimum<=result.maximum
}

func nativeStringNodeText(node schemajson.Node)(string,bool){text,ok:=node.Text();if !ok{return "",false};value,err:=text.UTF8();return value,err==nil}
func nativeStringLength(node schemajson.Node)(int,bool){if schemajson.KindName(node.Kind())!="number"{return 0,false};return nativeStringDecimal(node.Raw())}
func nativeStringDecimal(text string)(int,bool){
    if text==""||len(text)>1&&text[0]=='0'{return 0,false};value:=0;for i:=0;i<len(text);i++{digit:=text[i];if digit<'0'||digit>'9'{return 0,false};if value>nativeStringValidationMaximumLength{continue};value=value*10+int(digit-'0');if value>nativeStringValidationMaximumLength{value=nativeStringValidationMaximumLength+1}}
    return value,true
}

func parseNativeStringPattern(pattern string)(nativeStringPattern,bool){
    if len(pattern)<4||!strings.HasPrefix(pattern,"^[")||pattern[len(pattern)-1]!='$'{return nativeStringPattern{},false};close:=strings.IndexByte(pattern[2:],']');if close<0{return nativeStringPattern{},false};close+=2;if close==2{return nativeStringPattern{},false};class:=pattern[2:close];quantifier:=pattern[close+1:len(pattern)-1]
    alphabet:=map[int]bool{};for i:=0;i<len(class);{
        start:=class[i];if !nativeStringClassByte(start){return nativeStringPattern{},false}
        if i+2<len(class)&&class[i+1]=='-'{end:=class[i+2];if !nativeStringClassByte(end)||start>end{return nativeStringPattern{},false};for item:=int(start);item<=int(end);item++{alphabet[item]=true};i+=3;continue}
        if start=='-'&&i!=0&&i!=len(class)-1{return nativeStringPattern{},false};alphabet[int(start)]=true;i++
    }
    values:=make([]int,0,len(alphabet));for item:=range alphabet{values=append(values,item)};sort.Ints(values);if len(values)==0{return nativeStringPattern{},false};minimum,maximum,ok:=nativeStringQuantifier(quantifier);return nativeStringPattern{alphabet:values,minimum:minimum,maximum:maximum},ok
}
func nativeStringClassByte(value byte)bool{return value>=0x20&&value<=0x7e&&value!='\\'&&value!=']'&&value!='^'}
func nativeStringQuantifier(source string)(int,int,bool){
    switch source{case "":return 1,1,true;case "?":return 0,1,true;case "*":return 0,-1,true;case "+":return 1,-1,true}
    if len(source)<3||source[0]!='{'||source[len(source)-1]!='}'{return 0,0,false};body:=source[1:len(source)-1];comma:=strings.IndexByte(body,',');if comma<0{value,ok:=nativeStringDecimal(body);return value,value,ok};if strings.IndexByte(body[comma+1:],',')>=0{return 0,0,false};minimum,ok:=nativeStringDecimal(body[:comma]);if !ok{return 0,0,false};if comma==len(body)-1{return minimum,-1,true};maximum,ok:=nativeStringDecimal(body[comma+1:]);if !ok||minimum>maximum{return 0,0,false};return minimum,maximum,true
}
