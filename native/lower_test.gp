package native

import (
    "encoding/json"
    "strings"
    "testing"

    "goforge.dev/refine/language"
)

func payload(t *testing.T,source,root string)*language.PayloadType{t.Helper();program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};typ,err:=program.PayloadType(root);if err!=nil{t.Fatal(err)};return typ}

func decoded(t *testing.T,export *Export)map[string]any{t.Helper();var result map[string]any;if err:=json.Unmarshal(export.Bytes(),&result);err!=nil{t.Fatal(err)};return result}

func TestLowerExactJSONSchemaConstraint(t *testing.T){
    typ:=payload(t,"type Positive = Int where it >= 0 where it < 9007199254740993\n","Positive")
    export,err:=LowerPayload(JSONSchema,typ,LowerOptions{});if err!=nil{t.Fatal(err)};if len(export.Losses())!=0||export.Version()!="2020-12"{t.Fatalf("%+v",export.Losses())}
    root:=decoded(t,export);defs:=root["$defs"].(map[string]any);positive:=defs["Positive"].(map[string]any)
    if positive["minimum"].(float64)!=0||positive["exclusiveMaximum"].(float64)!=9007199254740993{t.Fatalf("%s",export.String())}
    bytes:=export.Bytes();bytes[0]='x';if !strings.HasPrefix(export.String(),"{"){t.Fatal("mutable export escaped")}
}

func TestLowerMultipleOfAndRepeatedBounds(t *testing.T){
    multiple:=payload(t,"type Even = Int where isInteger (it / 2)\n","Even");export,err:=LowerPayload(JSONSchema,multiple,LowerOptions{});if err!=nil{t.Fatal(err)};if !strings.Contains(export.String(),`"multipleOf": 2`){t.Fatal(export.String())}
    repeated:=payload(t,"type Bounded = Int where it >= 0 where it >= -1\n","Bounded");export,err=LowerPayload(JSONSchema,repeated,LowerOptions{});if err!=nil{t.Fatal(err)}
    // Repeated keyword forms remain a conjunction instead of replacing an
    // earlier clause; deterministic simplification is outside this boundary.
    if !strings.Contains(export.String(),`"minimum": 0`)||!strings.Contains(export.String(),`"minimum": -1`){t.Fatal(export.String())}
}

func TestUnsupportedRuleRequiresExplicitDocumentedLoss(t *testing.T){
    typ:=payload(t,"type Code = String where matches \"[A-Z]+\" it @code \"code.upper\"\n","Code")
    if _,err:=LowerPayload(JSONSchema,typ,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("silent loss: %v",err)}
    ordinary,err:=LowerPayload(JSONSchema,typ,LowerOptions{AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)}
    losses:=ordinary.Losses();if len(losses)!=1||losses[0].Predicate==""||ordinary.CompanionMarkdown()==""||!strings.Contains(ordinary.String(),"not machine-enforced")||!strings.Contains(ordinary.String(),"[A-Z]+"){t.Fatalf("missing embedded explanation: %+v\n%s",losses,ordinary.String())}
    losses[0].Predicate="forged";if ordinary.Losses()[0].Predicate=="forged"{t.Fatal("mutable loss escaped")}
    refined,err:=LowerPayload(JSONSchema,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};doc,err:=ParseJSONSchema(refined.Bytes(),Options{});if err!=nil{t.Fatal(err)};if len(doc.Annotations())!=1||doc.Annotations()[0].Root!="Code"{t.Fatalf("refinement source missing: %s",refined.String())}
}

func TestLowerAvroRepresentability(t *testing.T){
    typ:=payload(t,"type Person = { id :: Int64, name :: String, alias :: Nullable String }\n","Person")
    export,err:=LowerPayload(Avro,typ,LowerOptions{});if err!=nil{t.Fatal(err)};if export.Version()!="1.12.0"||!strings.Contains(export.String(),`"type": "long"`){t.Fatal(export.String())}
    refined,err:=LowerPayload(Avro,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};doc,err:=ParseAvro(refined.Bytes(),Options{});if err!=nil||len(doc.Annotations())!=1{t.Fatalf("refined Avro: %v %s",err,refined.String())}
    arbitrary:=payload(t,"type Big = Int\n","Big");if _,err:=LowerPayload(Avro,arbitrary,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("arbitrary Int silently narrowed: %v",err)}
    absent:=payload(t,"type R = { value :: Maybe String }\n","R");if _,err:=LowerPayload(Avro,absent,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("absence silently became default/null: %v",err)}
}

func TestLowerOpenAPIAndRecursiveReferences(t *testing.T){
    typ:=payload(t,"type Node = { value :: Int32, children :: [Node] }\n","Node")
    export,err:=LowerPayload(OpenAPI,typ,LowerOptions{OpenAPIVersion:"3.2.0"});if err!=nil{t.Fatal(err)};if !strings.Contains(export.String(),`"$ref": "#/components/schemas/Node"`){t.Fatal(export.String())}
    if _,err:=ParseOpenAPI(export.Bytes(),Options{});err!=nil{t.Fatal(err)}
    patch,err:=LowerPayload(OpenAPI,typ,LowerOptions{OpenAPIVersion:"3.2.1"});if err!=nil||patch.Version()!="3.2.1"||!strings.Contains(patch.String(),`"openapi": "3.2.1"`){t.Fatalf("published 3.2.1 lowering failed: %v %s",err,patch.String())}
    defaulted,err:=LowerPayload(OpenAPI,typ,LowerOptions{});if err!=nil||defaulted.Version()!="3.2.0"{t.Fatalf("compatibility default changed: %v %s",err,defaulted.Version())}
    if _,err:=LowerPayload(OpenAPI,typ,LowerOptions{OpenAPIVersion:"3.0.4"});problemCode(err)!="native.unrepresentable"{t.Fatalf("unsupported 3.0 lowering not explicit: %v",err)}
    if _,err:=LowerPayload(OpenAPI,typ,LowerOptions{OpenAPIVersion:"3.2.99"});problemCode(err)!="native.unrepresentable"{t.Fatalf("invented patch lowering accepted: %v",err)}
}

func TestOpenAPIRootNameCollisionIsSafe(t *testing.T){typ:=payload(t,"type RefineRoot = Int\n","RefineRoot");export,err:=LowerPayload(OpenAPI,typ,LowerOptions{});if err!=nil{t.Fatal(err)};text:=export.String();if !strings.Contains(text,`"RefineRoot":`)||!strings.Contains(text,`"RefineRoot_":`){t.Fatalf("root silently overwritten: %s",text)}}

func TestAvroRepeatedNamedRecordUsesReference(t *testing.T){
    source:="type Address = { line :: String }\ntype Person = { home :: Address, billing :: Address }\n";typ:=payload(t,source,"Person");export,err:=LowerPayload(Avro,typ,LowerOptions{});if err!=nil{t.Fatal(err)}
    if strings.Count(export.String(),`"name": "Address"`)!=1||!strings.Contains(export.String(),`"type": "Address"`){t.Fatalf("named record redefined: %s",export.String())}
}

func TestLossIdentityUsesOwnerAndOffset(t *testing.T){
    source:="type A = String where matches \"x\" it\ntype B = String where matches \"x\" it\ntype Pair = { a :: A, b :: B }\n";typ:=payload(t,source,"Pair");export,err:=LowerPayload(JSONSchema,typ,LowerOptions{AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};losses:=export.Losses();if len(losses)!=2||losses[0].Owner!="A"||losses[1].Owner!="B"{t.Fatalf("ambiguous predicate identity: %+v",losses)}
    inline:=payload(t,"","String where matches \"x\" it");export,err=LowerPayload(JSONSchema,inline,LowerOptions{AllowDocumentedLoss:true});if err!=nil{t.Fatal(err)};if len(export.Losses())!=1||export.Losses()[0].Owner!="$payload"||!strings.Contains(export.CompanionMarkdown(),"$payload"){t.Fatalf("inline root omitted: %+v\n%s",export.Losses(),export.CompanionMarkdown())}
}

func TestWireUnrepresentableTypesAlwaysError(t *testing.T){
    for _,root:=range []string{"Real","Timestamp"}{typ:=payload(t,"",root);for _,mode:=range []ExportMode{Ordinary,Refined}{if _,err:=LowerPayload(JSONSchema,typ,LowerOptions{Mode:mode,AllowDocumentedLoss:true});problemCode(err)!="native.unrepresentable"{t.Errorf("%s/%s: %v",root,mode,err)}}}
}

func TestFixedIntegerGenerationLimit(t *testing.T){typ:=payload(t,"","Int65537");if _,err:=LowerPayload(JSONSchema,typ,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("unbounded fixed-width generation: %v",err)}}

func TestExplicitScalarWireEncodings(t *testing.T){
    exact:=payload(t,"type Exact = Real\n","Exact");metadata:=WireMetadata{Scalars:map[string]ScalarEncoding{"Exact":{Kind:RationalRecord}}};jsonExport,err:=LowerPayloadWithMetadata(JSONSchema,exact,metadata,LowerOptions{});if err!=nil{t.Fatal(err)};if !strings.Contains(jsonExport.String(),`"denominator"`)||!strings.Contains(jsonExport.String(),`"exclusiveMinimum": 0`){t.Fatal(jsonExport.String())};avroExport,err:=LowerPayloadWithMetadata(Avro,exact,metadata,LowerOptions{});if err!=nil{t.Fatal(err)};if !strings.Contains(avroExport.String(),"two's-complement")||!strings.Contains(avroExport.String(),`"type": "bytes"`){t.Fatal(avroExport.String())}
    timestamp:=payload(t,"type EventTime = Timestamp\n","EventTime");export,err:=LowerPayloadWithMetadata(JSONSchema,timestamp,WireMetadata{Scalars:map[string]ScalarEncoding{"EventTime":{Kind:TimestampString}}},LowerOptions{});if err!=nil||!strings.Contains(export.String(),"exact source spelling"){t.Fatalf("timestamp policy: %v %s",err,export.String())}
    integer:=payload(t,"type BigId = Int\n","BigId");integerMetadata:=WireMetadata{Scalars:map[string]ScalarEncoding{"BigId":{Kind:DecimalString}}};export,err=LowerPayloadWithMetadata(Avro,integer,integerMetadata,LowerOptions{});if err!=nil||!strings.Contains(export.String(),"decimal-integer-string"){t.Fatalf("integer string policy: %v %s",err,export.String())};jsonInteger,err:=LowerPayloadWithMetadata(JSONSchema,integer,integerMetadata,LowerOptions{});if err!=nil{t.Fatal(err)};project,err:=IngestProject(JSONSchema,jsonInteger.Bytes(),ProjectOptions{Root:ResourceSelector{TypeName:"WireId"}});if err!=nil{t.Fatal(err)};for _,valid:=range []string{`"0"`,`"-1"`,`"123"`}{if err:=project.ValidateJSON([]byte(valid));err!=nil{t.Fatalf("canonical integer %s rejected: %v",valid,err)}};if err:=project.ValidateJSON([]byte(`"-0"`));problemCode(err)!="native.payload"{t.Fatalf("negative zero accepted: %v",err)}
}

func TestAvroRepeatedRationalEncodingUsesNamedReference(t *testing.T){
    typ:=payload(t,"type Exact = Real\ntype Pair = {left :: Exact, right :: Exact}\n","Pair");metadata:=WireMetadata{Scalars:map[string]ScalarEncoding{"Exact":{Kind:RationalRecord}}};export,err:=LowerPayloadWithMetadata(Avro,typ,metadata,LowerOptions{});if err!=nil{t.Fatal(err)};text:=export.String();if strings.Count(text,`"name": "ExactWire"`)!=1||!strings.Contains(text,`"type": "ExactWire"`){t.Fatalf("rational record was redefined instead of referenced: %s",text)}
}

func TestJSONWireMetadataLowersRecordsAndTaggedUnions(t *testing.T){
    typ:=payload(t,"type Envelope = {left :: Int, right :: Int}\ndata Payment = Card String | Bank Int64\ntype Request = {envelope :: Envelope, payment :: Payment}\n","Request")
    metadata:=WireMetadata{ExtraFields:map[string]ExtraFieldMode{"Envelope":DiscardExtraFields},Discriminators:map[string]Discriminator{"Payment":{Field:"kind",Values:map[string]string{"Card":"card","Bank":"bank"},Arguments:map[string][]string{"Card":{"number"},"Bank":{"account"}}}}}
    for _,format:=range []Format{JSONSchema,OpenAPI}{export,err:=LowerPayloadWithMetadata(format,typ,metadata,LowerOptions{});if err!=nil{t.Fatal(err)};text:=export.String();for _,want:=range []string{`"const": "card"`,`"const": "bank"`,`"number"`,`"account"`,`"additionalProperties": false`}{if !strings.Contains(text,want){t.Fatalf("%s missing %s: %s",format,want,text)}}}
    if _,err:=LowerPayloadWithMetadata(Avro,typ,metadata,LowerOptions{});problemCode(err)!="native.unrepresentable"{t.Fatalf("Avro silently ignored JSON wire policy: %v",err)}
}
