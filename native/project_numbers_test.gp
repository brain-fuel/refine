package native

import (
    "strings"
    "testing"
    "goforge.dev/refine/validation"
)

func TestNativeNumberProjectExportsExactWireWithoutStandaloneOptOut(t *testing.T){
    for _,tc:=range []struct{format Format;source,pointer string}{
        {JSONSchema,`{"type":"number","multipleOf":0.125}`,""},
        {OpenAPI,`{"openapi":"3.1.0","info":{"title":"Numbers","version":"1"},"paths":{},"components":{"schemas":{"Amount":{"type":"number","multipleOf":0.125}}}}`,"/components/schemas/Amount"},
    }{p,err:=IngestProject(tc.format,[]byte(tc.source),ProjectOptions{Root:ResourceSelector{Pointer:tc.pointer,TypeName:"Amount"}});if err!=nil{t.Fatal(err)}
        for _,mode:=range []ExportMode{Ordinary,Refined}{exported,err:=p.Export(LowerOptions{Mode:mode,AllowDocumentedLoss:true});if err!=nil{t.Fatal(tc.format,mode,err)};if !strings.Contains(exported.Resources()[0].Source,"rather than rounding"){t.Fatal("numeric wire restriction not explained")};again,err:=IngestProjectResources(tc.format,exported.Resources(),ProjectOptions{Root:exported.Root(),Metadata:exported.Metadata()});if err!=nil{t.Fatal(err)};_,report,err:=again.DecodeAndValidateJSON([]byte("9007199254740993.125"),validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatal("exact native number changed",err,report)};if err:=again.ValidateJSON([]byte("0.1"));problemCode(err)!="native.payload"{t.Fatal("native multipleOf lost",err)}}
        if p.Resources()[0].Source!=tc.source{t.Fatal("immutable original changed")}
        payload,err:=p.PayloadType();if err!=nil{t.Fatal(err)};if _,err:=LowerPayload(JSONSchema,payload,LowerOptions{AllowDocumentedLoss:true});problemCode(err)!="native.unrepresentable"{t.Fatal("standalone Real lost required explicit encoding",err)}
    }
}
