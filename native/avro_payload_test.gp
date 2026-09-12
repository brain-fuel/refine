package native

import (
    "math"
    "testing"
    "testing/quick"
    "unicode/utf8"

    avro "github.com/hamba/avro/v2"
)

func avroProject(t *testing.T,schema string)*Project{t.Helper();project,err:=IngestProject(Avro,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Datum"}});if err!=nil{t.Fatal(err)};return project}
func avroDatum(t *testing.T,project *Project,value any)[]byte{t.Helper();schema,err:=project.avroWriterSchema();if err!=nil{t.Fatal(err)};data,err:=avro.Marshal(schema,value);if err!=nil{t.Fatal(err)};return data}

func TestValidateAvroBinaryExactDatumAndFailures(t *testing.T){
    project:=avroProject(t,`{"type":"record","name":"Entry","fields":[{"name":"ok","type":"boolean"},{"name":"code","type":"int"},{"name":"note","type":"string"}]}`);valid:=avroDatum(t,project,map[string]any{"ok":true,"code":int(7),"note":"ready"});if err:=project.ValidateAvroBinary(valid,AvroPayloadLimits{});err!=nil{t.Fatal(err)}
    cases:=[][]byte{append(append([]byte(nil),valid...),0),{2,14,10,'r','e','a','d','y'},{1,14,2,0xff},valid[:len(valid)-1]};for _,data:=range cases{if err:=project.ValidateAvroBinary(data,AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("malformed datum accepted: %v",err)}}
    if err:=project.ValidateAvroBinary(valid,AvroPayloadLimits{Bytes:1});problemCode(err)!="native.limit"{t.Fatalf("byte limit not enforced: %v",err)}
    other,err:=IngestProject(JSONSchema,[]byte(`{"type":"string"}`),ProjectOptions{Root:ResourceSelector{TypeName:"Text"}});if err!=nil{t.Fatal(err)};if err:=other.ValidateAvroBinary(nil,AvroPayloadLimits{});problemCode(err)!="native.enforcement"{t.Fatalf("format mismatch not explicit: %v",err)}
}

func TestValidateAvroCollectionsBlocksAndBudgets(t *testing.T){
    array:=avroProject(t,`{"type":"array","items":"int"}`);for _,valid:=range [][]byte{{6,2,4,6,0},{1,2,6,0}}{if err:=array.ValidateAvroBinary(valid,AvroPayloadLimits{});err!=nil{t.Fatalf("valid array block rejected: %v",err)}}
    for _,invalid:=range [][]byte{{1,4,6,0},{1,2,6,6,0},{2,6}}{if err:=array.ValidateAvroBinary(invalid,AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("invalid array block accepted: %v",err)}}
    three:=[]byte{6,2,4,6,0};if err:=array.ValidateAvroBinary(three,AvroPayloadLimits{Values:3});problemCode(err)!="native.limit"{t.Fatalf("value limit not enforced: %v",err)}
    recursive:=avroProject(t,`{"type":"record","name":"Node","fields":[{"name":"next","type":["null","Node"]}]}`);if err:=recursive.ValidateAvroBinary([]byte{2,0},AvroPayloadLimits{});err!=nil{t.Fatal(err)};if err:=recursive.ValidateAvroBinary([]byte{2,0},AvroPayloadLimits{Depth:2});problemCode(err)!="native.limit"{t.Fatalf("recursive depth limit not enforced: %v",err)}
}

func TestValidateAvroLogicalTypesExactly(t *testing.T){
    decimal:=avroProject(t,`{"type":"bytes","logicalType":"decimal","precision":2,"scale":0}`);if err:=decimal.ValidateAvroBinary([]byte{2,99},AvroPayloadLimits{});err!=nil{t.Fatal(err)};for _,overflow:=range [][]byte{{2,123},{2,0x85}}{if err:=decimal.ValidateAvroBinary(overflow,AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("decimal precision not enforced: %v",err)}}
    fixedDecimal:=avroProject(t,`{"type":"fixed","name":"Money","size":2,"logicalType":"decimal","precision":2,"scale":0}`);if err:=fixedDecimal.ValidateAvroBinary([]byte{0,123},AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("fixed decimal precision not enforced: %v",err)}
    uuid:=avroProject(t,`{"type":"string","logicalType":"uuid"}`);for text,valid:=range map[string]bool{"123e4567-e89b-12d3-a456-426614174000":true,"not-a-uuid":false}{err:=uuid.ValidateAvroBinary(avroDatum(t,uuid,text),AvroPayloadLimits{});if (err==nil)!=valid{t.Fatalf("uuid %q: %v",text,err)}}
    fixedUUID:=avroProject(t,`{"type":"fixed","name":"Identifier","size":16,"logicalType":"uuid"}`);if err:=fixedUUID.ValidateAvroBinary(make([]byte,16),AvroPayloadLimits{});err!=nil{t.Fatal(err)}
    daytime:=avroProject(t,`{"type":"int","logicalType":"time-millis"}`);if err:=daytime.ValidateAvroBinary(avroDatum(t,daytime,int(86399999)),AvroPayloadLimits{});err!=nil{t.Fatal(err)};if err:=daytime.ValidateAvroBinary(avroDatum(t,daytime,int(86400000)),AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("time-of-day range not enforced: %v",err)}
    nanos:=avroProject(t,`{"type":"long","logicalType":"timestamp-nanos"}`);if err:=nanos.ValidateAvroBinary(avroDatum(t,nanos,int64(math.MaxInt64)),AvroPayloadLimits{});err!=nil{t.Fatal(err)}
    unknown:=avroProject(t,`{"type":"string","logicalType":"example-vendor-type"}`);if err:=unknown.ValidateAvroBinary(avroDatum(t,unknown,"underlying"),AvroPayloadLimits{});err!=nil{t.Fatalf("unknown logical type was not read as underlying string: %v",err)}
    if err:=unknown.ValidateAvroBinary(avroDatum(t,unknown,"long"),AvroPayloadLimits{StringBytes:3});problemCode(err)!="native.limit"{t.Fatalf("string limit not enforced: %v",err)}
    bigDecimal:=avroProject(t,`{"type":"bytes","logicalType":"big-decimal"}`);for _,datum:=range [][]byte{{6,2,0,0},{8,4,4,0xd2,4},{6,2,0xff,3},{8,4,0,1,0}}{if err:=bigDecimal.ValidateAvroBinary(datum,AvroPayloadLimits{});err!=nil{t.Fatalf("valid big-decimal rejected: %x %v",datum,err)}};for _,datum:=range [][]byte{{0},{4,0,0},{4,2,1},{8,2,1,0,0},{14,2,1,0x80,0x80,0x80,0x80,0x10}}{if err:=bigDecimal.ValidateAvroBinary(datum,AvroPayloadLimits{});problemCode(err)!="native.payload"{t.Fatalf("malformed big-decimal accepted: %x %v",datum,err)}}
}

func TestValidateAvroBinaryUsesOrderedResourceCache(t *testing.T){
    resources:=[]Resource{{URI:"urn:avro:address",Source:`{"type":"record","name":"Address","aliases":["OldAddress"],"fields":[{"name":"line","type":"string"}]}`},{URI:"urn:avro:person",Source:`{"type":"record","name":"Person","fields":[{"name":"address","type":"Address"}]}`}};project,err:=IngestProjectResources(Avro,resources,ProjectOptions{Root:ResourceSelector{Resource:"urn:avro:person",TypeName:"PersonDatum"}});if err!=nil{t.Fatal(err)};data:=avroDatum(t,project,map[string]any{"address":map[string]any{"line":"Main"}});if err:=project.ValidateAvroBinary(data,AvroPayloadLimits{});err!=nil{t.Fatal(err)}
}

func TestValidateAvroBinaryOracleProperty(t *testing.T){
    project:=avroProject(t,`{"type":"record","name":"Numbers","fields":[{"name":"small","type":"int"},{"name":"wide","type":"long"},{"name":"text","type":"string"}]}`)
    property:=func(small int32,wide int64,text string)bool{if len(text)>4096||!utf8.ValidString(text){return true};data,err:=func()([]byte,error){schema,e:=project.avroWriterSchema();if e!=nil{return nil,e};return avro.Marshal(schema,map[string]any{"small":int(small),"wide":wide,"text":text})}();if err!=nil{return false};return project.ValidateAvroBinary(data,AvroPayloadLimits{})==nil}
    if err:=quick.Check(property,&quick.Config{MaxCount:2000});err!=nil{t.Fatal(err)}
}

func FuzzValidateAvroBinary(f *testing.F){project,err:=IngestProject(Avro,[]byte(`["null",{"type":"record","name":"Item","fields":[{"name":"name","type":"string"},{"name":"values","type":{"type":"array","items":"long"}}]}]`),ProjectOptions{Root:ResourceSelector{TypeName:"Datum"}});if err!=nil{f.Fatal(err)};for _,seed:=range [][]byte{{0},{2,2,'x',0},{4},{2,2,0xff,0}}{f.Add(seed)};f.Fuzz(func(t *testing.T,input []byte){if len(input)>65536{t.Skip()};_ = project.ValidateAvroBinary(input,AvroPayloadLimits{Bytes:65536,Depth:32,Values:10000,StringBytes:8192})})}
