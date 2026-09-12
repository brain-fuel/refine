package cli

import (
    "bytes"
    "encoding/json"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

func TestEnglishCLI(t *testing.T){
    source:=`type Child = Int where it >= 0 && it < 18 @message "Expected 0 <= age < 18"`
    for _,jsonMode:=range []bool{false,true}{var out,stderr bytes.Buffer;args:=[]string{"explain"};if jsonMode{args=append(args,"--json")};args=append(args,"-");if Run(args,strings.NewReader(source),&out,&stderr)!=0||stderr.Len()!=0{t.Fatal(stderr.String())};if jsonMode{var decoded map[string]any;if err:=json.Unmarshal(out.Bytes(),&decoded);err!=nil{t.Fatal(err)};detail:=decoded["result"].(map[string]any);if len(detail["rules"].([]any))!=1{t.Fatal("clause lost")}}else if !strings.Contains(out.String(),"Expected 0 <= age < 18")||!strings.Contains(out.String(),"without evaluating"){t.Fatal("incomplete explanation")}}
}

func TestCanonicalValidationCLI(t *testing.T){
    dir:=t.TempDir();schema:=filepath.Join(dir,"schema.refine");if err:=os.WriteFile(schema,[]byte("type T = String where length it > 10\n"),0600);err!=nil{t.Fatal(err)}
    for _,test:=range []struct{args []string;payload string;state string;status int}{
        {[]string{"validate","--json",schema,"T","-"},`"a secret"`,"invalid",1},
        {[]string{"validate","--json",schema,"T","-"},`"a sufficiently long value"`,"valid",0},
        {[]string{"validate","--json","--total-steps","1",schema,"T","-"},`"a secret"`,"indeterminate",1},
        {[]string{"validate","--json",schema,"T","-"},`show "a secret"`,"invalid",1},
    }{var out,stderr bytes.Buffer;status:=Run(test.args,strings.NewReader(test.payload),&out,&stderr);if status!=test.status{t.Fatalf("status %d: %s %s",status,&out,&stderr)};var decoded report;if err:=json.Unmarshal(out.Bytes(),&decoded);err!=nil{t.Fatal(err)};if decoded.State!=test.state||strings.Contains(out.String(),"a secret")||stderr.Len()!=0{t.Fatalf("bad/private report: %s %s",&out,&stderr)}}
}

func TestNativeStructureCLI(t *testing.T){
    cases:=[]struct{format string;source string;code int}{
        {"json-schema",`{"type":"integer","minimum":0}`,0},
        {"avro",`{"type":"record","name":"T","fields":[{"name":"value","type":"long"}]}`,0},
        {"openapi",`{"openapi":"3.2.0","info":{"title":"Example","version":"1.0.0"},"paths":{}}`,0},
        {"json-schema",`{"type":"private-secret"}`,1},
        {"json-schema",`{"type":"integer","type":"private-secret"}`,1},
        {"avro",`{"type":"private-secret"}`,1},
    }
    for _,test:=range cases{var out,stderr bytes.Buffer;status:=Run([]string{"validate-native","--json",test.format,"-"},strings.NewReader(test.source),&out,&stderr);if status!=test.code||stderr.Len()!=0{t.Fatalf("bad result %d: %s %s",status,&out,&stderr)};if strings.Contains(out.String(),"private-secret"){t.Fatal("oracle diagnostic leaked source value")}}
}

func TestAnalysisCLI(t *testing.T){
    var out,stderr bytes.Buffer
    if Run([]string{"satisfiable","--json","-","T"},strings.NewReader("type T = [Int]"),&out,&stderr)!=0{t.Fatal("unknown satisfiability must allow compilation")}
    var decoded report;if err:=json.Unmarshal(out.Bytes(),&decoded);err!=nil||decoded.State!="unknown"{t.Fatal(out.String(),err)}
    out.Reset();if Run([]string{"satisfiable","--json","-","T"},strings.NewReader("type T = Int where it > 0 where it < 1"),&out,&stderr)!=1{t.Fatal("unsatisfiable not rejected")}
    dir:=t.TempDir();old:=filepath.Join(dir,"old.refine");if err:=os.WriteFile(old,[]byte("type T = Int where it >= 0"),0600);err!=nil{t.Fatal(err)}
    out.Reset();stderr.Reset();if Run([]string{"compare-payload","--json",old,"T","-","T"},strings.NewReader("type T = Int where it >= -1"),&out,&stderr)!=0{t.Fatal(out.String(),stderr.String())}
    var result struct{Result struct{Backward struct{Outcome string};Forward struct{Outcome string}}};if err:=json.Unmarshal(out.Bytes(),&result);err!=nil||result.Result.Backward.Outcome!="yes"||result.Result.Forward.Outcome!="no"{t.Fatal(out.String(),err)}
    out.Reset();if Run([]string{"compare-payload","--json",old,"T","-","T"},strings.NewReader("type T = Int where it >= 1"),&out,&stderr)!=1{t.Fatal("backward break not rejected")}
}

func TestWorkflowErrors(t *testing.T){
    for _,args:=range [][]string{{"validate","-","T","-"},{"compare-payload","-","T","-","T"},{"explain"},{"validate","--total-steps","-1","-","T","x"},{"explain","--not-a-flag","-"}}{var out,stderr bytes.Buffer;if Run(args,strings.NewReader(""),&out,&stderr)!=2{t.Fatalf("accepted invalid usage %v",args)}}
    var stderr bytes.Buffer
    if Run([]string{"explain","-"},strings.NewReader("type T = Int"),brokenWriter{},&stderr)!=2{t.Fatal("output failure ignored")}
    if Run([]string{"explain","--json","-"},strings.NewReader("type T = Int"),brokenWriter{},&stderr)!=2{t.Fatal("JSON output failure ignored")}
}
