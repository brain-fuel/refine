package cli

import (
    "bytes"
    "encoding/json"
    "os"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/native"
)

func TestNativeAvroJSONInputEncodingIsExplicitAndValidated(t *testing.T){
    p,err:=native.IngestProject(native.Avro,[]byte(`"int"`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Count"}});if err!=nil{t.Fatal(err)};p,err=p.WithEditedSource(strings.Replace(p.EditableSource(),"Int32","Int32 where fromInt32 it > 0 @code \"positive\"",1));if err!=nil{t.Fatal(err)};bundle,err:=p.Bundle();if err!=nil{t.Fatal(err)};artifact:=filepath.Join(t.TempDir(),"count.refined.json");if err=os.WriteFile(artifact,bundle,0600);err!=nil{t.Fatal(err)}
    cases:=[]struct{name,input,state,code string;extra []string}{
        {"valid",`3`,"valid","",nil},{"predicate",`-3`,"invalid","positive",nil},{"native",`12345678987654321`,"invalid","native.payload",nil},{"duplicate",`{"private":1,"private":1}`,"invalid","native.payload",nil},{"budget",`3`,"indeterminate","",[]string{"--total-steps","1"}},{"native only",`-3`,"valid","",[]string{"--native-only"}},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){args:=append([]string{"native","validate-payload","--json","--avro-json"},tc.extra...);args=append(args,artifact,"-");var out,errout bytes.Buffer;status:=Run(args,strings.NewReader(tc.input),&out,&errout);want:=1;if tc.state=="valid"{want=0};if status!=want{t.Fatalf("status %d: %s %s",status,out.String(),errout.String())};var got report;if err=json.Unmarshal(out.Bytes(),&got);err!=nil||got.State!=tc.state{t.Fatalf("report: %s %v",out.String(),err)};if tc.code!=""&&!strings.Contains(out.String(),tc.code){t.Fatal("missing expected diagnostic",out.String())};if strings.Contains(out.String(),"12345678987654321")||strings.Contains(out.String(),"private"){t.Fatal("native input leaked")}})}
    var out,errout bytes.Buffer;if status:=Run([]string{"native","validate-payload","--json",artifact,"-"},strings.NewReader("-3"),&out,&errout);status!=1||!strings.Contains(out.String(),"native.payload"){t.Fatal("Avro input encoding was guessed",out.String())}
    other,err:=native.IngestProject(native.JSONSchema,[]byte(`{"type":"integer"}`),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Count"}});if err!=nil{t.Fatal(err)};otherBundle,err:=other.Bundle();if err!=nil{t.Fatal(err)};if err=os.WriteFile(artifact,otherBundle,0600);err!=nil{t.Fatal(err)};out.Reset();errout.Reset();if status:=Run([]string{"native","validate-payload","--avro-json",artifact,"-"},strings.NewReader("3"),&out,&errout);status!=2||out.Len()!=0||!strings.Contains(errout.String(),"requires an Avro bundle"){t.Fatal("foreign encoding accepted",out.String(),errout.String())}
}
