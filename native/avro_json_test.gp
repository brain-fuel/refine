package native

import (
    "bytes"
    "encoding/json"
    "math/rand"
    "strconv"
    "strings"
    "testing"

    "goforge.dev/refine/validation"
)

func TestAvroJSONNativeEncodingAndExactTranscode(t *testing.T){
    cases:=[]struct{name,schema,input string;want []byte}{
        {"null",`"null"`,`null`,[]byte{}},
        {"boolean",`"boolean"`,`true`,[]byte{1}},
        {"int",`"int"`,`-3`,[]byte{5}},
        {"long",`"long"`,`9223372036854775807`,[]byte{254,255,255,255,255,255,255,255,255,1}},
        {"float",`"float"`,`0.5`,[]byte{0,0,0,63}},
        {"double",`"double"`,`0.5`,[]byte{0,0,0,0,0,0,224,63}},
        {"unicode",`"string"`,`"\ud83d\ude80"`,[]byte{8,240,159,154,128}},
        {"bytes",`"bytes"`,`"\u0000\u00ff"`,[]byte{4,0,255}},
        {"big decimal",`{"type":"bytes","logicalType":"big-decimal"}`,`"\u0004\u0004\u00d2\u0004"`,[]byte{8,4,4,210,4}},
        {"fixed",`{"type":"fixed","name":"Pair","size":2}`,`"\u0000\u00ff"`,[]byte{0,255}},
        {"enum",`{"type":"enum","name":"Color","symbols":["red","green"]}`,`"green"`,[]byte{2}},
        {"array",`{"type":"array","items":"int"}`,`[1,-1]`,[]byte{4,2,1,0}},
        {"empty array",`{"type":"array","items":"int"}`,`[]`,[]byte{0}},
        {"map",`{"type":"map","values":"int"}`,`{"a":1}`,[]byte{2,2,97,2,0}},
        {"record order",`{"type":"record","name":"R","fields":[{"name":"a","type":"int"},{"name":"b","type":"boolean"}]}`,`{"b":false,"a":2}`,[]byte{4,0}},
        {"null union",`["string","null"]`,`null`,[]byte{2}},
        {"string union",`["null","string"]`,`{"string":"x"}`,[]byte{2,2,120}},
        {"named union",`["null",{"type":"record","name":"n.R","fields":[{"name":"x","type":"int"}]}]`,`{"n.R":{"x":1}}`,[]byte{2,2}},
        {"recursive",`{"type":"record","name":"n.Node","fields":[{"name":"next","type":["null","n.Node"]}]}`,`{"next":{"n.Node":{"next":null}}}`,[]byte{2,0}},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){doc,err:=ParseAvro([]byte(tc.schema),Options{});if err!=nil{t.Fatal(err)};p:=&Project{document:doc,root:ResourceSelector{Resource:"urn:test:avro"},resources:[]Resource{{URI:"urn:test:avro",Source:tc.schema}}};got,_,err:=p.avroJSONBinary([]byte(tc.input),AvroPayloadLimits{});if err!=nil||!bytes.Equal(got,tc.want){t.Fatalf("transcode %x want %x: %v",got,tc.want,err)};if err=p.ValidateAvroJSON([]byte(tc.input),AvroPayloadLimits{});err!=nil{t.Fatal(err)}})}
}

func TestAvroJSONRejectsMalformedLossyAndDefaultedWriterInputs(t *testing.T){
    cases:=[]struct{schema string;inputs []string}{
        {`"int"`,[]string{`1.0`,`1e0`,`2147483648`,`"1"`,`true`,`1 2`}},
        {`"long"`,[]string{`9223372036854775808`,`1.5`,`null`}},
        {`"float"`,[]string{`1e1000`,`"NaN"`,`"Infinity"`}},
        {`"string"`,[]string{`"\ud800"`,`false`}},
        {`"bytes"`,[]string{`"\u0100"`,`"\ud83d\ude80"`,`[1,2]`}},
        {`{"type":"fixed","name":"Pair","size":2}`,[]string{`"x"`,`"xxx"`}},
        {`{"type":"enum","name":"Color","symbols":["red"]}`,[]string{`"blue"`,`0`}},
        {`["null","string"]`,[]string{`"x"`,`{"null":null}`,`{}`,`{"string":"x","int":2}`,`{"string":"x","string":"x"}`}},
        {`{"type":"record","name":"R","fields":[{"name":"a","type":"int","default":0}]}`,[]string{`{}`,`{"a":0,"extra":1}`,`{"a":1,"a":1}`}},
        {`{"type":"bytes","logicalType":"decimal","precision":2,"scale":0}`,[]string{`"\u007b"`}},
        {`{"type":"bytes","logicalType":"big-decimal"}`,[]string{`"\u0004\u0004\u00d2"`,`"\u0000\u0000"`}},
    }
    for i,tc:=range cases{p:=avroProject(t,tc.schema);for j,input:=range tc.inputs{t.Run(strconv.Itoa(i)+"/"+strconv.Itoa(j),func(t *testing.T){if err:=p.ValidateAvroJSON([]byte(input),AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("malformed input not rejected: %v",err)}})}}
}

func TestAvroJSONBudgetsAndRefinementBoundary(t *testing.T){
    p:=avroProject(t,`{"type":"array","items":"int"}`);cases:=[]struct{input string;limits AvroPayloadLimits}{{`[1]`,AvroPayloadLimits{Bytes:2}},{`[1,2]`,AvroPayloadLimits{Values:2}},{`[1]`,AvroPayloadLimits{Depth:-1}}};for _,tc:=range cases{if err:=p.ValidateAvroJSON([]byte(tc.input),tc.limits);problemCode(err)!="native.limit"{t.Fatalf("array budget not enforced: %v",err)}}
    text:=avroProject(t,`"string"`);if err:=text.ValidateAvroJSON([]byte(`"abc"`),AvroPayloadLimits{StringBytes:2});problemCode(err)!="native.limit"{t.Fatalf("string budget: %v",err)}
    recursive:=avroProject(t,`{"type":"record","name":"Node","fields":[{"name":"next","type":["null","Node"]}]}`);if err:=recursive.ValidateAvroJSON([]byte(`{"next":{"Node":{"next":null}}}`),AvroPayloadLimits{Depth:1});problemCode(err)!="native.limit"{t.Fatalf("depth budget: %v",err)}
    p=avroProject(t,`"int"`);source:=strings.Replace(p.EditableSource(),"Int32","Int32 where fromInt32 it > 0 @code \"positive\"",1);var err error;p,err=p.WithEditedSource(source);if err!=nil{t.Fatal(err)}
    for _,tc:=range []struct{input,state string}{{`3`,"valid"},{`-3`,"invalid"}}{data,report,err:=p.DecodeAndValidateAvroJSON([]byte(tc.input),AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!=tc.state{t.Fatalf("refined JSON boundary: %v %+v",err,report)};number,ok:=data.Number();if !ok||number.Show()!=tc.input{t.Fatal("exact native payload was changed")}}
    if _,report,err:=p.DecodeAndValidateAvroJSON([]byte(`3`),AvroPayloadLimits{},validation.Limits{Total:1,Clause:1});err!=nil||validation.StateName(report.State())!="indeterminate"{t.Fatalf("refinement budget: %v %+v",err,report)}
    if _,_,err:=p.DecodeAndValidateAvroJSON([]byte(`1.5`),AvroPayloadLimits{},validation.Limits{});problemCode(err)!="native.payload"{t.Fatalf("native gate did not precede refinement: %v",err)}
    var absent *Project;if err:=absent.ValidateAvroJSON(nil,AvroPayloadLimits{});problemCode(err)!="native.project"{t.Fatal(err)}
}

func TestAvroJSONSeededLongAgreementWithBinary(t *testing.T){p:=avroProject(t,`"long"`);random:=rand.New(rand.NewSource(1729));for i:=0;i<1000;i++{number:=int64(random.Uint64());input:=strconv.FormatInt(number,10);encoded,_,err:=p.avroJSONBinary([]byte(input),AvroPayloadLimits{});if err!=nil{t.Fatal(err)};expected:=avroDatum(t,p,number);if !bytes.Equal(encoded,expected){t.Fatalf("seed 1729 iteration %d: binary mismatch",i)};data,report,err:=p.DecodeAndValidateAvroJSON([]byte(input),AvroPayloadLimits{},validation.Limits{});if err!=nil||validation.StateName(report.State())!="valid"{t.Fatalf("seed 1729 iteration %d: %v",i,err)};got,_:=data.Number();if got.Show()!=input{t.Fatalf("seed 1729 iteration %d: exact value changed",i)}}}

func FuzzAvroJSONBoundary(f *testing.F){p,err:=IngestProject(Avro,[]byte(`{"type":"record","name":"Node","fields":[{"name":"next","type":["null","Node"]}]}`),ProjectOptions{Root:ResourceSelector{TypeName:"Node"}});if err!=nil{f.Fatal(err)};for _,seed:=range []string{`{"next":null}`,`{"next":{"Node":{"next":null}}}`,`{"next":0}`,`{"next":null,"next":null}`}{f.Add(seed)};f.Fuzz(func(t *testing.T,input string){if len(input)>8192{t.Skip()};if !json.Valid([]byte(input)){return};_,_,_=p.DecodeAndValidateAvroJSON([]byte(input),AvroPayloadLimits{Bytes:8192,Depth:16,Values:256,StringBytes:1024},validation.Limits{Total:10000,Clause:1000})})}
