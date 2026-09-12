package java

import (
    "bytes"
    "encoding/base64"
    "encoding/json"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"

    "goforge.dev/refine/native"
    "goforge.dev/refine/validation"
)

func TestNativeAvroJSONAgreesWithApacheEncoding(t *testing.T){
    compiler,vm:=javaTools(t);classpath:=avroClasspath(t)
    cases:=[]struct{Schema string `json:"schema"`;Input string `json:"input"`}{
        {`"long"`,`9223372036854775807`},
        {`"float"`,`0.1`},
        {`"double"`,`-0.125`},
        {`"bytes"`,`"\u0000\u00ff"`},
        {`{"type":"fixed","name":"Pair","size":2}`,`"\u0000\u00ff"`},
        {`{"type":"array","items":"int"}`,`[1,-2,3]`},
        {`{"type":"enum","name":"Color","symbols":["red","green"]}`,`"green"`},
        {`["int","string"]`,`{"string":"hello"}`},
        {`{"type":"record","name":"n.Node","fields":[{"name":"value","type":"int"},{"name":"next","type":["null","n.Node"]}]}`,`{"next":{"n.Node":{"next":null,"value":2}},"value":1}`},
    }
    input,err:=json.Marshal(cases);if err!=nil{t.Fatal(err)};dir:=t.TempDir();source:=filepath.Join(dir,"AvroJSONOracle.java");if err=os.WriteFile(source,[]byte(avroJSONOracleHarness),0600);err!=nil{t.Fatal(err)};classes:=filepath.Join(dir,"classes");if output,err:=exec.Command(compiler,"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-cp",classpath,"-d",classes,source).CombinedOutput();err!=nil{t.Fatalf("Avro JSON oracle javac: %v\n%s",err,output)}
    command:=exec.Command(vm,"-Xss256k","-Xmx64m","-cp",classes+string(os.PathListSeparator)+classpath,"AvroJSONOracle");command.Stdin=bytes.NewReader(input);var stderr bytes.Buffer;command.Stderr=&stderr;output,err:=command.Output();if err!=nil{t.Fatalf("Avro JSON oracle: %v\n%s",err,stderr.String())};lines:=strings.Split(strings.TrimSpace(string(output)),"\n");if len(lines)!=len(cases){t.Fatalf("oracle produced %d lines for %d cases",len(lines),len(cases))}
    for i,tc:=range cases{project,err:=native.IngestProject(native.Avro,[]byte(tc.Schema),native.ProjectOptions{Root:native.ResourceSelector{TypeName:"Datum"}});if err!=nil{t.Fatal(err)};binary,err:=base64.StdEncoding.DecodeString(lines[i]);if err!=nil{t.Fatal(err)};want,wantReport,err:=project.DecodeAndValidateAvro(binary,native.AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(wantReport.State())!="valid"{t.Fatalf("case %d Apache binary: %v %+v",i,err,wantReport)};got,report,err:=project.DecodeAndValidateAvroJSON([]byte(tc.Input),native.AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("case %d Go JSON: %v %+v",i,err,report)};equal,err:=got.EqualWith(want,func(uint64)error{return nil});if err!=nil||!equal{t.Fatalf("case %d Go/Apache exact data mismatch: %v",i,err)}}
}

const avroJSONOracleHarness=`
public final class AvroJSONOracle {
    public static void main(String[] args)throws Exception{
        var cases=new com.fasterxml.jackson.databind.ObjectMapper().readTree(System.in);
        for(var entry:cases){
            var schema=new org.apache.avro.Schema.Parser().parse(entry.get("schema").asText());
            var datum=new org.apache.avro.generic.GenericDatumReader<Object>(schema).read(null,org.apache.avro.io.DecoderFactory.get().jsonDecoder(schema,entry.get("input").asText()));
            var buffer=new java.io.ByteArrayOutputStream();var encoder=org.apache.avro.io.EncoderFactory.get().binaryEncoder(buffer,null);
            new org.apache.avro.generic.GenericDatumWriter<Object>(schema).write(datum,encoder);encoder.flush();
            System.out.println(java.util.Base64.getEncoder().encodeToString(buffer.toByteArray()));
        }
    }
}
`
