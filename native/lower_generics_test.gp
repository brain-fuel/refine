package native

import (
    "fmt"
    "strings"
    "testing"
)

func TestLowerClosedGenericAliasesAndTransformedParents(t *testing.T){
    source:="type Pair a b = {left :: a, right :: b}\ntype Swap a b = Pair b a\ntype Root = Swap String Int\n";typ:=payload(t,source,"Root");beforeSource,beforeType:=typ.Source(),typ.Formatted()
    for _,format:=range []Format{JSONSchema,OpenAPI}{export,err:=LowerPayload(format,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};text:=export.String();if !strings.Contains(text,`"type": "string"`)||!strings.Contains(text,`"type": "integer"`){t.Fatalf("%s transformed arguments missing: %s",format,text)};if typ.Source()!=beforeSource||typ.Formatted()!=beforeType{t.Fatal("lowering mutated the checked payload witness")}}
    export,err:=LowerPayload(JSONSchema,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};project,err:=IngestProject(JSONSchema,export.Bytes(),ProjectOptions{Root:ResourceSelector{TypeName:"GenericDatum"}});if err!=nil{t.Fatal(err)}
    if err:=project.ValidateJSON([]byte(`{"left":7,"right":"ok"}`));err!=nil{t.Fatalf("specialized JSON rejected: %v",err)};if err:=project.ValidateJSON([]byte(`{"left":"swapped","right":7}`));problemCode(err)!="native.payload"{t.Fatalf("transformed generic arguments rebound or swapped: %v",err)}
}

func TestLowerRecursiveGenericAvroDefinesBeforeReference(t *testing.T){
    source:="type Node a = {value :: a, children :: [Node a]}\n";typ:=payload(t,source,"Node Int32");first,err:=LowerPayload(Avro,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};second,err:=LowerPayload(Avro,typ,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};if first.String()!=second.String(){t.Fatal("generic Avro lowering is nondeterministic")}
    name:=genericDefinitionSeed("Node",typ.Formatted());text:=first.String();if strings.Count(text,`"name": "`+name+`"`)!=1||strings.Count(text,`"items": "`+name+`"`)!=1{t.Fatalf("recursive Avro specialization was duplicated or not referenced: %s",text)}
    project,err:=IngestProject(Avro,first.Bytes(),ProjectOptions{Root:ResourceSelector{TypeName:"NodeDatum"}});if err!=nil{t.Fatal(err)};if err:=project.ValidateAvroBinary([]byte{2,0},AvroPayloadLimits{});err!=nil{t.Fatalf("lowered recursive generic datum failed native validation: %v",err)}
}

func TestLowerGenericTaggedUnionUsesOneClosedDefinition(t *testing.T){
    source:="data Tree a = Leaf a | Branch (Tree a) (Tree a)\n";typ:=payload(t,source,"Tree Int32");metadata:=WireMetadata{Discriminators:map[string]Discriminator{"Tree":{Field:"kind",Values:map[string]string{"Leaf":"leaf","Branch":"branch"},Arguments:map[string][]string{"Leaf":{"value"},"Branch":{"left","right"}}}}}
    export,err:=LowerPayloadWithMetadata(JSONSchema,typ,metadata,LowerOptions{Mode:Refined});if err!=nil{t.Fatal(err)};name:=genericDefinitionSeed("Tree",typ.Formatted());if strings.Count(export.String(),`"`+name+`": {`)!=1{t.Fatalf("recursive generic union definition was duplicated: %s",export.String())}
    document,err:=ParseJSONSchema(export.Bytes(),Options{});if err!=nil{t.Fatalf("closed generic union failed native schema validation: %v",err)};if len(document.Annotations())!=1||document.Annotations()[0].Root!="Tree Int32"{t.Fatalf("closed semantic root witness missing: %s",export.String())}
}

func TestLowerGenericNamesAvoidDeclarationsAndExpansionIsBounded(t *testing.T){
    key:="(Box Int32)";collision:=genericDefinitionSeed("Box",key);source:=fmt.Sprintf("type Box a = {value :: a}\ntype %s = String\n",collision);typ:=payload(t,source,key);export,err:=LowerPayload(JSONSchema,typ,LowerOptions{});if err!=nil{t.Fatal(err)};if !strings.Contains(export.String(),`"$ref": "#/$defs/`+collision+`_1"`){t.Fatalf("generated definition overwrote an authored declaration: %s",export.String())}
    growing:=payload(t,"type Grow a = {value :: a, next :: Grow [a]}\n","Grow Int32");if _,err:=LowerPayload(JSONSchema,growing,LowerOptions{MaxGenericSpecializations:4});problemCode(err)!="native.limit"{t.Fatalf("infinite specialization family did not fail at its bound: %v",err)}
    if _,err:=LowerPayload(JSONSchema,typ,LowerOptions{MaxGenericSpecializations:MaximumLowerGenericSpecializations+1});problemCode(err)!="native.lower"{t.Fatalf("invalid specialization budget accepted: %v",err)}
}

func TestLowerRepeatedAvroScalarAliasStaysStructural(t *testing.T){typ:=payload(t,"type Small = Int32\ntype Pair = {left :: Small, right :: Small}\n","Pair");export,err:=LowerPayload(Avro,typ,LowerOptions{});if err!=nil{t.Fatal(err)};if strings.Count(export.String(),`"type": "int"`)!=2||strings.Contains(export.String(),`"type": "Small"`){t.Fatalf("scalar alias became an undefined Avro named reference: %s",export.String())}}

func TestLowerNumericKeywordExpansionIsBoundedBeforeExactParse(t *testing.T){for _,predicate:=range []string{"it < 1e1000000000","isInteger (it / 1e1000000000)"}{typ:=payload(t,"type Huge = Real where "+predicate+"\n","Huge");_,err:=LowerPayload(JSONSchema,typ,LowerOptions{});if problemCode(err)!="native.unrepresentable"||strings.Contains(err.Error(),"1000000000"){t.Fatalf("unbounded numeric literal was parsed or exposed: %v",err)}}}
