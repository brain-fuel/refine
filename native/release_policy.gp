package native

import (
    "encoding/json"
    "fmt"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

// ReleaseComparisonBundle returns the exact bundle bytes with only the final
// releasePolicy member and its owned comma removed. Every other byte remains
// comparison identity. A policy member in any other position is rejected.
func ReleaseComparisonBundle(input []byte)([]byte,*language.ReleasePolicy,error){
    document,err:=schemajson.Parse(input,schemajson.Limits{});if err!=nil{return nil,nil,wrap("","native.bundle","",err)}
    root:=document.Root();if schemajson.KindName(root.Kind())!="object"{return nil,nil,&Error{Code:"native.bundle",Message:"a bundle must be a JSON object"}};members:=root.Members();for _,member:=range members{key,keyErr:=member.Key.UTF8();if keyErr!=nil{return nil,nil,&Error{Code:"native.bundle",Message:"bundle member names must contain Unicode scalar values"}};if strings.EqualFold(key,"releasePolicy")&&key!="releasePolicy"{return nil,nil,&Error{Code:"native.bundle",Pointer:"/"+key,Message:"releasePolicy member name is case-sensitive and must use the exact spelling"}}}
    policyNode,present:=root.Lookup("releasePolicy");if !present{return append([]byte(nil),input...),nil,nil}
    if len(members)<=1{return nil,nil,&Error{Code:"native.bundle",Message:"releasePolicy cannot be the only bundle member"}};last,decodeErr:=members[len(members)-1].Key.UTF8();if decodeErr!=nil||last!="releasePolicy"{return nil,nil,&Error{Code:"native.bundle",Pointer:"/releasePolicy",Message:"releasePolicy must be the final top-level member so its exact owned delimiter can be masked"}}
    policy,err:=language.ParseReleasePolicyJSON([]byte(policyNode.Raw()));if err!=nil{return nil,nil,wrap("","native.bundle","/releasePolicy",err)}
    start,end,err:=finalBundleReleasePolicySpan(string(input));if err!=nil{return nil,nil,&Error{Code:"native.bundle",Pointer:"/releasePolicy",Message:err.Error()}}
    masked:=make([]byte,0,len(input)-(end-start));masked=append(masked,input[:start]...);masked=append(masked,input[end:]...);return masked,policy,nil
}

// AppendBundleReleasePolicy is a pure byte operation. Its comma/member suffix
// is owned by the carrier, so ReleaseComparisonBundle returns input exactly.
func AppendBundleReleasePolicy(input []byte,policy *language.ReleasePolicy)([]byte,error){
    document,parseErr:=schemajson.Parse(input,schemajson.Limits{});if parseErr!=nil{return nil,wrap("","native.bundle","",parseErr)};if schemajson.KindName(document.Root().Kind())!="object"||document.Root().MemberCount()==0{return nil,&Error{Code:"native.bundle",Message:"releasePolicy can be appended only to a nonempty bundle object"}}
    _,existing,err:=ReleaseComparisonBundle(input);if err!=nil{return nil,err};if existing!=nil{return nil,&Error{Code:"native.bundle",Pointer:"/releasePolicy",Message:"bundle already carries releasePolicy"}}
    encoded,err:=language.FormatReleasePolicyJSON(policy);if err!=nil{return nil,wrap("","native.bundle","/releasePolicy",err)};delimiter:=[]byte(",\"releasePolicy\":");if len(input)>schemajson.DefaultBytes-len(delimiter)||len(encoded)>schemajson.DefaultBytes-len(delimiter)-len(input){return nil,&Error{Code:"native.bundle",Pointer:"/releasePolicy",Message:"bundle with releasePolicy exceeds the 16 MiB native document limit"}};end:=len(input)-1;for end>=0&&strings.ContainsRune(" \t\r\n",rune(input[end])){end--};if end<0||input[end]!='}'{return nil,&Error{Code:"native.bundle",Message:"a bundle must end in a JSON object"}}
    result:=make([]byte,0,len(input)+len(encoded)+len(delimiter));result=append(result,input[:end]...);result=append(result,delimiter...);result=append(result,encoded...);result=append(result,input[end:]...);return result,nil
}

func copyNativeReleasePolicy(input *language.ReleasePolicy)*language.ReleasePolicy{if input==nil{return nil};out:=*input;out.Overrides=append([]language.CompatibilityApproval(nil),input.Overrides...);out.BreakingFixes=append([]language.BreakingFixApproval(nil),input.BreakingFixes...);return &out}

func finalBundleReleasePolicySpan(source string)(int,int,error){
    i:=skipBundleJSONSpace(source,0);if i>=len(source)||source[i]!='{'{return 0,0,fmt.Errorf("a bundle must be a JSON object")};i++;comma:=-1
    for{
        i=skipBundleJSONSpace(source,i);if i>=len(source)||source[i]=='}'{return 0,0,fmt.Errorf("releasePolicy member was not found")}
        keyStart:=i;keyEnd,err:=skipBundleJSONString(source,i);if err!=nil{return 0,0,err};var key string;if err=json.Unmarshal([]byte(source[keyStart:keyEnd]),&key);err!=nil{return 0,0,fmt.Errorf("invalid bundle member name")};i=skipBundleJSONSpace(source,keyEnd);if i>=len(source)||source[i]!=':'{return 0,0,fmt.Errorf("invalid bundle member")};i=skipBundleJSONSpace(source,i+1);valueEnd,err:=skipBundleJSONValue(source,i);if err!=nil{return 0,0,err};after:=skipBundleJSONSpace(source,valueEnd)
        if key=="releasePolicy"{if comma<0{return 0,0,fmt.Errorf("releasePolicy cannot be the first bundle member")};if after>=len(source)||source[after]!='}'{return 0,0,fmt.Errorf("releasePolicy must be the final top-level member")};return comma,valueEnd,nil}
        if after>=len(source)||source[after]!=','{return 0,0,fmt.Errorf("releasePolicy must be the final top-level member")};comma=after;i=after+1
    }
}

func skipBundleJSONSpace(source string,index int)int{for index<len(source)&&strings.ContainsRune(" \t\r\n",rune(source[index])){index++};return index}
func skipBundleJSONString(source string,index int)(int,error){if index>=len(source)||source[index]!='"'{return 0,fmt.Errorf("invalid JSON string")};index++;for index<len(source){if source[index]=='"'{return index+1,nil};if source[index]=='\\'{index++;if index>=len(source){break}};index++};return 0,fmt.Errorf("unterminated JSON string")}
func skipBundleJSONValue(source string,index int)(int,error){
    if index>=len(source){return 0,fmt.Errorf("missing JSON value")};if source[index]=='"'{return skipBundleJSONString(source,index)};if source[index]!='{'&&source[index]!='['{for index<len(source)&&!strings.ContainsRune(",]} \t\r\n",rune(source[index])){index++};return index,nil}
    stack:=[]byte{source[index]};index++;for index<len(source)&&len(stack)>0{if source[index]=='"'{next,err:=skipBundleJSONString(source,index);if err!=nil{return 0,err};index=next;continue};switch source[index]{case '{','[':stack=append(stack,source[index]);case '}':if stack[len(stack)-1]!='{'{return 0,fmt.Errorf("mismatched JSON object")};stack=stack[:len(stack)-1];case ']':if stack[len(stack)-1]!='['{return 0,fmt.Errorf("mismatched JSON array")};stack=stack[:len(stack)-1]};index++};if len(stack)!=0{return 0,fmt.Errorf("unterminated JSON value")};return index,nil
}
