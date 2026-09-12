package native

import (
    "testing"

    "goforge.dev/refine/validation"
)

func TestDecodeAndValidateJSONComposesNativeExactAndRefined(t *testing.T){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["age"],"properties":{"age":{"type":"integer","minimum":0},"nickname":{"type":"string"}},"x-refine":{"source":"type ExactAdult = Int where it > 900719925474099300000000 @code \"adult\"\ntype Person = {age :: ExactAdult, nickname :: Maybe String}\n","root":"Person"}}`
    project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Person"},Metadata:WireMetadata{ExtraFields:map[string]ExtraFieldMode{"Person":PreserveExtraFields}}});if err!=nil{t.Fatal(err)}
    data,report,err:=project.DecodeAndValidateJSON([]byte(`{"age":900719925474099300000001,"extra":{"exact":123456789012345678901234567890}}`),validation.Limits{});if err!=nil{t.Fatal(err)};if validation.StateName(report.State())!="valid"{t.Fatal(report.Diagnostics())};if data.Size()!=3{t.Fatalf("optional and preserved fields missing: %+v",data.Fields())};nickname,_:=data.Lookup("nickname");if tag,_:=nickname.Constructor();tag!="Nothing"{t.Fatalf("absent Maybe decoded as %s",tag)};extra,_:=data.Lookup("extra");exact,_:=extra.Lookup("exact");number,_:=exact.Number();if number.Show()!="123456789012345678901234567890"{t.Fatalf("number lost precision: %s",number.Show())}
    _,report,err=project.DecodeAndValidateJSON([]byte(`{"age":900719925474099300000000}`),validation.Limits{});if err!=nil{t.Fatal(err)};if validation.StateName(report.State())!="invalid"||len(report.Diagnostics())!=1||report.Diagnostics()[0].Code!="adult"{t.Fatalf("language refinement not composed: %+v",report)}
    if _,_,err:=project.DecodeAndValidateJSON([]byte(`{"age":-1}`),validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("native constraint not composed: %v",err)}
}

func TestDecodeAndValidateJSONUsesExplicitScalarAndUnionWireMetadata(t *testing.T){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["payment"],"properties":{"payment":{"type":"object"}},"x-refine":{"source":"type Exact = Real\ndata Payment = Ratio Exact | Empty\ntype Root = {payment :: Payment}\n","root":"Root"}}`
    metadata:=WireMetadata{Scalars:map[string]ScalarEncoding{"Exact":{Kind:RationalRecord}},Discriminators:map[string]Discriminator{"Payment":{Field:"kind",Values:map[string]string{"Ratio":"ratio","Empty":"empty"},Arguments:map[string][]string{"Ratio":{"amount"},"Empty":{}}}}}
    project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Root"},Metadata:metadata});if err!=nil{t.Fatal(err)}
    data,report,err:=project.DecodeAndValidateJSON([]byte(`{"payment":{"kind":"ratio","amount":{"numerator":2,"denominator":6}}}`),validation.Limits{});if err!=nil{t.Fatal(err)};if validation.StateName(report.State())!="valid"{t.Fatal(report.Diagnostics())};payment,_:=data.Lookup("payment");args:=payment.Elements();number,_:=args[0].Number();if number.Show()!="1/3"{t.Fatalf("rational record not decoded exactly: %s",number.Show())}
    if _,_,err:=project.DecodeAndValidateJSON([]byte(`{"payment":{"kind":"ratio","amount":{"numerator":1,"denominator":0}}}`),validation.Limits{});problemCode(err)!="native.decode"{t.Fatalf("zero rational denominator accepted: %v",err)}
    data,report,err=project.DecodeAndValidateJSON([]byte(`{"payment":{"kind":"ratio","amount":{"numerator":1.0,"denominator":2e0}}}`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("mathematically integral JSON number rejected: %v %+v",err,report)};payment,_=data.Lookup("payment");args=payment.Elements();number,_=args[0].Number();if number.Show()!="1/2"{t.Fatalf("integral exponent/decimal forms lost exact value: %s",number.Show())}
    if _,_,err:=project.DecodeAndValidateJSON([]byte(`{"payment":{"kind":"other"}}`),validation.Limits{});problemCode(err)!="native.decode"{t.Fatalf("unknown union tag accepted: %v",err)}
}

func TestDecodeAndValidateJSONRejectsUnsupportedFormat(t *testing.T){
    project,err:=IngestProject(Avro,[]byte(`"long"`),ProjectOptions{Root:ResourceSelector{TypeName:"Count"}});if err!=nil{t.Fatal(err)};if _,_,err:=project.DecodeAndValidateJSON([]byte(`1`),validation.Limits{});problemCode(err)!="native.enforcement"{t.Fatalf("Avro was treated as JSON: %v",err)}
}

func TestJSONNumericExpansionBudgetPrecedesExactParsing(t *testing.T){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"array","items":{"type":"number"}}`
    project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Values"}});if err!=nil{t.Fatal(err)}
    huge:=[]byte(`[1e1000000000]`);if err:=project.ValidateJSON(huge);problemCode(err)!="native.limit"{t.Fatalf("huge exponent reached exact oracle: %v",err)};if _,_,err:=project.DecodeAndValidateJSON(huge,validation.Limits{});problemCode(err)!="native.limit"{t.Fatalf("huge exponent reached refinement decoder: %v",err)}
    bounded,err:=project.WithMetadata(WireMetadata{NumericExpansion:12});if err!=nil{t.Fatal(err)};if err:=bounded.ValidateJSON([]byte(`[1e3,1e3]`));err!=nil{t.Fatalf("budget boundary rejected: %v",err)};if err:=bounded.ValidateJSON([]byte(`[1e4,1e4]`));problemCode(err)!="native.limit"{t.Fatalf("aggregate expansion was not bounded: %v",err)}
    if _,err:=project.WithMetadata(WireMetadata{NumericExpansion:MaxNumericExpansion+1});problemCode(err)!="native.metadata"{t.Fatalf("unsafe metadata budget accepted: %v",err)}
    if _,err:=ParseJSONSchema([]byte(`{"$schema":"https://json-schema.org/draft/2020-12/schema","minimum":1e1000000000}`),Options{});problemCode(err)!="native.encoding"{t.Fatalf("schema exponent reached oracle: %v",err)}
    resources:=[]Resource{{URI:"https://example.test/root.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"dep.json","maximum":1e40000}`},{URI:"https://example.test/dep.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"number","minimum":1e40000}`}};if _,err:=IngestProjectResources(JSONSchema,resources,ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/root.json",TypeName:"Value"}});problemCode(err)!="native.encoding"{t.Fatalf("resource-set aggregate expansion was not bounded: %v",err)}
    openAPI:="openapi: 3.1.2\ninfo: {title: T, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Value: {type: number, minimum: 1e1000000000}\n";if _,err:=ParseOpenAPI([]byte(openAPI),Options{});err==nil{t.Fatal("YAML schema exponent reached OpenAPI oracle")}
}

func TestDecodeAndValidateOpenAPISelectedSchemaAndRefinement(t *testing.T){
    api:="openapi: 3.2.0\ninfo: {title: Refined, version: '1'}\npaths: {}\nx-refine:\n  source: 'type Root = Int where it > 10 @code \"large\"'\n  root: Root\ncomponents:\n  schemas:\n    Root: {type: integer, minimum: 0}\n";project,err:=IngestProject(OpenAPI,[]byte(api),ProjectOptions{Root:ResourceSelector{Pointer:"/components/schemas/Root",TypeName:"Root"}});if err!=nil{t.Fatal(err)}
    _,report,err:=project.DecodeAndValidateJSON([]byte(`11`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("valid OpenAPI value failed: %v %+v",err,report)};_,report,err=project.DecodeAndValidateJSON([]byte(`5`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="invalid"||report.Diagnostics()[0].Code!="large"{t.Fatalf("OpenAPI refinement missing: %v %+v",err,report)};if _,_,err:=project.DecodeAndValidateJSON([]byte(`-1`),validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("OpenAPI native minimum missing: %v",err)}
}

func TestDecodeAndValidateJSONClosesNestedGenericArgumentsSimultaneously(t *testing.T){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["left","right"],"properties":{"left":{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}},"right":{"type":"object","required":["value"],"properties":{"value":{"type":"string"}}}},"x-refine":{"source":"type Box a = {value :: a}\ntype Pair a b = {left :: Box a, right :: Box b}\ntype Swap a b = Pair b a\ntype Root = Swap String Int\n","root":"Root"}}`;project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)}
    data,report,err:=project.DecodeAndValidateJSON([]byte(`{"left":{"value":7},"right":{"value":"ok"}}`),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("nested generic decode failed: %v %+v",err,report)};left,_:=data.Lookup("left");item,_:=left.Lookup("value");number,_:=item.Number();if number.Show()!="7"{t.Fatal("swapped generic argument decoded with rebound type")}
}

func FuzzDecodeAndValidateJSON(f *testing.F){
    schema:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["value"],"properties":{"value":{"type":"integer"}},"x-refine":{"source":"type Root = {value :: Int where it >= 0}\n","root":"Root"}}`;project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{f.Fatal(err)};for _,seed:=range []string{`{"value":0}`,`{"value":-1}`,`{"value":900719925474099300000000}`,`{"value":1.0}`,`null`,`{"value":0,"x":[null,true]}`}{f.Add(seed)};f.Fuzz(func(t *testing.T,input string){if len(input)>65536{t.Skip()};_,_,_ = project.DecodeAndValidateJSON([]byte(input),validation.Limits{Total:100000,Clause:10000})})
}
