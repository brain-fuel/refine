package native

import (
    "strings"
    "testing"
)

func TestJSONSchemaProjectEditBundleAndNativeEnforcement(t *testing.T){
    source:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["age"],"properties":{"age":{"type":"integer","minimum":0},"name":{"type":"string"}},"additionalProperties":false}`
    project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{ResourceID:"https://example.test/person.json",Root:ResourceSelector{TypeName:"Person"},Metadata:WireMetadata{ExtraFields:map[string]ExtraFieldMode{"Person":DiscardExtraFields},PublicationNamespace:"com.example.people"}});if err!=nil{t.Fatal(err)}
    origins:=project.NativeConstraints();if len(origins)!=1||origins[0].Resource!="https://example.test/person.json"{t.Fatalf("resource provenance missing: %+v",origins)};projection:=project.ResourceConstraintSource(origins[0].Resource);if recovered,err:=project.RecoverResourceNative(origins[0].Resource,origins[0].Constraint.Name,projection);err!=nil||recovered!="0"{t.Fatalf("resource recovery: %q %v",recovered,err)}
    editable:=project.EditableSource();if !strings.Contains(editable,"type Person = {age :: Int, name :: Maybe (String)}")||!strings.Contains(editable,"type Native_"){t.Fatalf("bad projection:\n%s",editable)}
    if err:=project.ValidateJSON([]byte(`{"age":3}`));err!=nil{t.Fatal(err)};if err:=project.ValidateJSON([]byte(`{"age":-1}`));problemCode(err)!="native.payload"{t.Fatalf("opaque minimum not enforced: %v",err)};if err:=project.ValidateJSON([]byte(`{"age":3,"extra":true}`));problemCode(err)!="native.payload"{t.Fatalf("opaque additionalProperties not enforced: %v",err)}
    editedSource:=strings.Replace(editable,"type Person = {age :: Int, name :: Maybe (String)}","type Person = ({age :: Int, name :: Maybe (String)} where it.age >= 21)",1);edited,err:=project.WithEditedSource(editedSource);if err!=nil{t.Fatal(err)};payload,err:=edited.PayloadType();if err!=nil||!strings.Contains(payload.Formatted(),"Person"){t.Fatalf("edited root missing: %v",err)}
    bundle,err:=edited.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if again.EditableSource()!=editedSource||again.NativeDocument().Original()!=source||again.Metadata().PublicationNamespace!="com.example.people"{t.Fatal("bundle lost project/source/sidecar")}
    bundle[0]='x';if again.NativeDocument().Original()!=source{t.Fatal("bundle bytes alias project")}
    if again.GeneratedEnforcement().Supported{t.Fatal("generated enforcement claimed opaque native coverage")}
}

func TestApplicatorConstraintIsNotHoisted(t *testing.T){source:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer","not":{"type":"integer","minimum":10},"allOf":[{"type":"integer","maximum":20}]}`;project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"Value"}});if err!=nil{t.Fatal(err)};editable:=project.EditableSource();first:=strings.Split(editable,"\n")[0];if first!="type Value = Int"{t.Fatalf("applicator became unconditional: %s",first)};if strings.Count(editable,"type Native_")!=2{t.Fatalf("provenance units missing:\n%s",editable)};if err:=project.ValidateJSON([]byte(`15`));problemCode(err)!="native.payload"{t.Fatalf("not/minimum context lost: %v",err)}}

func TestLocalReferencesBecomeNamedRecursiveDeclarations(t *testing.T){source:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"Node":{"type":"object","properties":{"children":{"type":"array","items":{"$ref":"#/$defs/Node"}}}},"Unused":{"type":"array"}},"$ref":"#/$defs/Node"}`;project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"Tree"}});if err!=nil{t.Fatal(err)};editable:=project.EditableSource();if !strings.Contains(editable,"type Node = {children :: Maybe ([Node])}")||!strings.Contains(editable,"type Tree = Node")||strings.Contains(editable,"type Unused"){t.Fatalf("reference projection wrong:\n%s",editable)}}

func TestRootAnnotationSeedsEditableSourceWithoutChangingSelector(t *testing.T){
    source:=`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer","x-refine":{"source":"type Existing = Int where it > 0\n","root":"Existing"}}`
    project,err:=IngestProject(JSONSchema,[]byte(source),ProjectOptions{Root:ResourceSelector{TypeName:"PublicValue"}});if err!=nil{t.Fatal(err)}
    if project.Root().TypeName!="PublicValue"{t.Fatalf("root selector changed: %+v",project.Root())};editable:=project.EditableSource();if !strings.Contains(editable,"type Existing = Int where it > 0")||!strings.Contains(editable,"type PublicValue = Existing"){t.Fatalf("annotation source not adopted:\n%s",editable)}
    bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if again.Root().TypeName!="PublicValue"||again.EditableSource()!=editable{t.Fatal("annotation-backed root did not round trip")}
}

func TestOpenAPIAndAvroEditableProjection(t *testing.T){
    api:="openapi: 3.2.0\ninfo: {title: People, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Person:\n      type: object\n      required: [id]\n      properties:\n        id: {type: integer}\n        label: {type: string}\n"
    open,err:=IngestProject(OpenAPI,[]byte(api),ProjectOptions{ResourceID:"https://example.test/openapi.yaml",Root:ResourceSelector{Pointer:"/components/schemas/Person",TypeName:"PersonPayload"}});if err!=nil{t.Fatal(err)};if !strings.Contains(open.EditableSource(),"type PersonPayload = {id :: Int, label :: Maybe (String)}"){t.Fatal(open.EditableSource())};if err:=open.ValidateJSON([]byte(`{}`));problemCode(err)!="native.enforcement"{t.Fatalf("unsupported OpenAPI native validator not gated: %v",err)}
    avro:=`{"type":"record","name":"Person","fields":[{"name":"id","type":"long"},{"name":"label","type":["null","string"],"default":null}]}`;avroProject,err:=IngestProject(Avro,[]byte(avro),ProjectOptions{Root:ResourceSelector{TypeName:"PersonPayload"}});if err!=nil{t.Fatal(err)};text:=avroProject.EditableSource();if !strings.Contains(text,"type Person = {id :: Int64, label :: Nullable (String)}")||!strings.Contains(text,"type PersonPayload = Person"){t.Fatal(text)}
}

func TestWireMetadataCheckedAndImmutable(t *testing.T){
    schema:=`{"type":"object","properties":{}}`;project,err:=IngestProject(JSONSchema,[]byte(schema),ProjectOptions{Root:ResourceSelector{TypeName:"Envelope"}});if err!=nil{t.Fatal(err)}
    edited,err:=project.WithEditedSource(project.EditableSource()+"\ndata Payment = Card String | Bank Int64\ntype Exact = Real\n");if err!=nil{t.Fatal(err)}
    metadata:=WireMetadata{ExtraFields:map[string]ExtraFieldMode{"Envelope":PreserveExtraFields},Scalars:map[string]ScalarEncoding{"Exact":{Kind:RationalRecord}},Discriminators:map[string]Discriminator{"Payment":{Field:"kind",Values:map[string]string{"Card":"card","Bank":"bank"},Arguments:map[string][]string{"Card":{"number"},"Bank":{"account"}}}},PublicationNamespace:"com.example.payments"}
    configured,err:=edited.WithMetadata(metadata);if err!=nil{t.Fatal(err)};metadata.Discriminators["Payment"].Values["Card"]="forged";got:=configured.Metadata();if got.Discriminators["Payment"].Values["Card"]!="card"{t.Fatal("metadata input alias escaped")};got.Discriminators["Payment"].Arguments["Card"][0]="forged";if configured.Metadata().Discriminators["Payment"].Arguments["Card"][0]!="number"{t.Fatal("metadata output alias escaped")}
    bad:=configured.Metadata();bad.Discriminators["Payment"]=Discriminator{Field:"kind",Values:map[string]string{"Card":"same","Bank":"same"},Arguments:map[string][]string{"Card":{"number"},"Bank":{"account"}}};if _,err:=configured.WithMetadata(bad);problemCode(err)!="native.metadata"{t.Fatalf("duplicate wire tags accepted: %v",err)}
}

func TestExplicitJSONSchemaResourceResolutionAndBundle(t *testing.T){
    resources:=[]Resource{{URI:"https://example.test/main.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"dep.json"}`},{URI:"https://example.test/dep.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"string","minLength":2}`}}
    project,err:=IngestProjectResources(JSONSchema,resources,ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/main.json",TypeName:"Code"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"type Code = String"){t.Fatal(project.EditableSource())};if err:=project.ValidateJSON([]byte(`"x"`));problemCode(err)!="native.payload"{t.Fatalf("external native constraint not enforced: %v",err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if len(again.Resources())!=2{t.Fatal("resource bundle lost dependency")}
    resources=resources[:1];if _,err:=IngestProjectResources(JSONSchema,resources,ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/main.json",TypeName:"Code"}});problemCode(err)!="native.structure"{t.Fatalf("missing external resource did not fail closed: %v",err)}
}

func TestExternalJSONSchemaProvenanceRemainsResourceScoped(t *testing.T){
    resources:=[]Resource{{URI:"https://example.test/main.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"dep.json"}`},{URI:"https://example.test/dep.json",Source:`{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"integer","minimum":7}`}}
    project,err:=IngestProjectResources(JSONSchema,resources,ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/main.json",TypeName:"Count"}});if err!=nil{t.Fatal(err)}
    constraints:=project.NativeConstraints();if len(constraints)!=1||constraints[0].Resource!="https://example.test/dep.json"{t.Fatalf("external provenance scope lost: %+v",constraints)};projection:=project.ResourceConstraintSource(constraints[0].Resource);recovered,err:=project.RecoverResourceNative(constraints[0].Resource,constraints[0].Constraint.Name,projection);if err!=nil||recovered!="7"{t.Fatalf("external constraint recovery: %q %v",recovered,err)}
    if err:=project.ValidateJSON([]byte(`6`));problemCode(err)!="native.payload"{t.Fatalf("external constraint not enforced: %v",err)}
}

func TestExplicitOpenAPIAndAvroResources(t *testing.T){
    api:=[]Resource{{URI:"https://example.test/api.yaml",Source:"openapi: 3.1.2\ninfo: {title: T, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Person: {$ref: './person.yaml'}\n"},{URI:"https://example.test/person.yaml",Source:"type: object\nrequired: [name]\nproperties:\n  name: {type: string}\n"}}
    project,err:=IngestProjectResources(OpenAPI,api,ProjectOptions{Root:ResourceSelector{Resource:"https://example.test/api.yaml",Pointer:"/components/schemas/Person",TypeName:"Person"}});if err!=nil{t.Fatal(err)};if !strings.Contains(project.EditableSource(),"name :: String"){t.Fatal(project.EditableSource())}
    avro:=[]Resource{{URI:"urn:avro:address",Source:`{"type":"record","name":"Address","fields":[{"name":"line","type":"string"}]}`},{URI:"urn:avro:person",Source:`{"type":"record","name":"Person","fields":[{"name":"address","type":"Address"}]}`}}
    avroProject,err:=IngestProjectResources(Avro,avro,ProjectOptions{Root:ResourceSelector{Resource:"urn:avro:person",TypeName:"PersonPayload"}});if err!=nil{t.Fatal(err)};if !strings.Contains(avroProject.EditableSource(),"address :: Address"){t.Fatal(avroProject.EditableSource())}
}

func TestOfflineLanguageImportsComposeWithNativeSidecar(t *testing.T){
    project,err:=IngestProject(JSONSchema,[]byte(`{"type":"object","required":["age"],"properties":{"age":{"type":"integer","maximum":130}}}`),ProjectOptions{Root:ResourceSelector{TypeName:"Person"}});if err!=nil{t.Fatal(err)}
    sources:=map[string]string{"models/common.refine":"type AdultAge = Int where it >= 18\n","models/main.refine":"import \"common.refine\"\ntype Person = { age :: AdultAge }\n"};edited,err:=project.WithEditedSources("models/main.refine",sources);if err!=nil{t.Fatal(err)};if edited.LanguageEntry()!="models/main.refine"||len(edited.LanguageFiles())!=2||!strings.Contains(edited.EditableSource(),"type AdultAge"){t.Fatalf("imports not flattened/retained: %s",edited.EditableSource())}
    bundle,err:=edited.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if again.LanguageEntry()!=edited.LanguageEntry()||again.EditableSource()!=edited.EditableSource(){t.Fatal("language import graph did not round trip")}
    if _,err:=project.WithEditedSources("models/main.refine",map[string]string{"models/main.refine":sources["models/main.refine"]});problemCode(err)!="native.refinement"{t.Fatalf("missing import did not fail closed: %v",err)}
}

func TestResourceAndBundleFailuresAreExplicit(t *testing.T){
    duplicate:=[]Resource{{URI:"urn:test:x",Source:`{"type":"string"}`},{URI:"urn:test:x",Source:`{"type":"string"}`}};if _,err:=IngestProjectResources(JSONSchema,duplicate,ProjectOptions{Root:ResourceSelector{Resource:"urn:test:x",TypeName:"X"}});problemCode(err)!="native.resource"{t.Fatalf("duplicate URI accepted: %v",err)}
    drafts:=[]Resource{{URI:"urn:test:main",Source:`{"$ref":"urn:test:old"}`},{URI:"urn:test:old",Source:`{"$schema":"http://json-schema.org/draft-07/schema#","type":"string"}`}};if _,err:=IngestProjectResources(JSONSchema,drafts,ProjectOptions{Root:ResourceSelector{Resource:"urn:test:main",TypeName:"X"}});problemCode(err)!="native.version"{t.Fatalf("mixed draft accepted: %v",err)}
    project,err:=IngestProject(JSONSchema,[]byte(`{"type":"string"}`),ProjectOptions{Root:ResourceSelector{TypeName:"X"}});if err!=nil{t.Fatal(err)};bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};tampered:=strings.Replace(string(bundle),`"format": "json-schema"`,`"format": "json-schema", "format": "avro"`,1);if _,err:=ParseBundle([]byte(tampered));problemCode(err)!="native.bundle"{t.Fatalf("duplicate bundle key accepted: %v",err)};unknown:=strings.Replace(string(bundle),`"version": 1`,`"version": 1, "future": true`,1);if _,err:=ParseBundle([]byte(unknown));problemCode(err)!="native.bundle"{t.Fatalf("unknown bundle member accepted: %v",err)}
}
