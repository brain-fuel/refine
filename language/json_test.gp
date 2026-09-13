package language

import (
    "strings"
    "testing"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

const jsonLanguageContract=`
sameJSON :: JSON -> JSON -> Bool
sameJSON left right = left == right
kind :: JSON -> String
kind value = case value of {
  JSONNull -> "null";
  JSONBoolean _ -> "boolean";
  JSONNumber _ -> "number";
  JSONString _ -> "string";
  JSONArray _ -> "array";
  JSONObject _ -> "object"
}
type Root = JSON where kind it /= "" && sameJSON it it @code "json.kind"
`

func TestIntrinsicJSONConstructorsCoverageAndCanonicalCodec(t *testing.T){
    program,err:=Compile(jsonLanguageContract);if err!=nil{t.Fatal(err)}
    cases:=[]string{
        `JSONNull`, `JSONBoolean True`, `JSONNumber (1 / 3)`, `JSONString "text"`,
        `JSONArray [JSONNull, JSONBoolean False]`,
        `JSONObject (map {"b" = JSONNumber 2.5, "a" = JSONString "x"})`,
    }
    for _,raw:=range cases{text,err:=value.TextFromUTF8(raw);if err!=nil{t.Fatal(err)};data,report:=program.ReadData("Root",text,validation.Limits{});if validation.StateName(report.State())!="valid"{t.Fatalf("%s: %+v",raw,report.Diagnostics())};shown,err:=ShowDataWithoutValidation(data,validation.Limits{});if err!=nil{t.Fatal(err)};again,next:=program.ReadData("Root",shown,validation.Limits{});if validation.StateName(next.State())!="valid"{t.Fatalf("reread %s: %+v",shown.Show(),next.Diagnostics())};same,err:=data.EqualWith(again,func(uint64)error{return nil});if err!=nil||!same{t.Fatalf("JSON canonical round trip changed %s",raw)}}
    if _,err:=Compile(strings.Replace(jsonLanguageContract,"  JSONObject _ -> \"object\"\n", "",1));err==nil||!strings.Contains(err.Error(),"not exhaustive"){t.Fatalf("missing JSON constructor was not rejected: %v",err)}
}

func TestIntrinsicJSONRejectsMalformedDataAndReservedNames(t *testing.T){
    program,err:=Compile("type Root = JSON\n");if err!=nil{t.Fatal(err)}
    number:=value.OfNumber(value.Integer(1));rawText,_:=value.TextFromUTF8("x");text:=value.OfText(rawText)
    cases:=[]value.Data{}
    for _,item:=range []struct{name string;args []value.Data}{{"Unknown",nil},{"JSONNull",[]value.Data{number}},{"JSONBoolean",nil},{"JSONBoolean",[]value.Data{text}},{"JSONArray",[]value.Data{number}},{"JSONObject",[]value.Data{number}}}{data,_:=value.Variant(item.name,item.args);cases=append(cases,data)}
    cases=append(cases,number)
    for i,data:=range cases{report:=program.ValidateData("Root",data,validation.Limits{});if validation.StateName(report.State())!="invalid"||report.Incomplete(){t.Fatalf("malformed JSON %d accepted: %+v",i,report.Diagnostics())}}
    for _,source:=range []string{"type JSON = Int\n","data Other = JSONNull\n","type Bad = JSON Int\n","bad :: JSON -> JSON\nbad value = value + value\n","bad :: JSON -> Bool\nbad value = value < value\n","bad :: JSON\nbad = JSONBoolean 1\n"}{if _,err:=Compile(source);err==nil{t.Fatalf("reserved, misapplied, or implicitly coerced JSON accepted: %s",source)}}
}
