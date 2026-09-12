package native

import (
	"fmt"
	"strings"
	"testing"

	avro "github.com/hamba/avro/v2"
	"goforge.dev/refine/language"
)

func TestAvroDefaultRefinementRejectsConclusiveFailure(t *testing.T) {
	schema := `{"type":"record","name":"Counter","fields":[{"name":"count","type":"int","default":0}]}`
	project := avroProject(t, schema)
	invalid := "type Positive = Int32 where fromInt32 it > 0 @code \"positive\"\ntype Counter = {count :: Positive}\ntype Datum = Counter\n"
	if _, err := project.WithEditedSource(invalid); problemCode(err) != "native.default-refinement" {
		t.Fatalf("invalid refined default compiled: %v", err)
	}
	valid := "type Positive = Int32 where fromInt32 it >= 0\ntype Counter = {count :: Positive}\ntype Datum = Counter\n"
	checked, err := project.WithEditedSource(valid)
	if err != nil {
		t.Fatal(err)
	}
	checks := checked.AvroDefaultChecks()
	if len(checks) != 1 || checks[0].State != "valid" || checks[0].Code != "native.default.valid" || !strings.HasSuffix(checks[0].Pointer, "/fields/0/default") {
		t.Fatalf("default proof absent: %+v", checks)
	}
	checks[0].State = "changed"
	if checked.AvroDefaultChecks()[0].State != "valid" {
		t.Fatal("mutable default checks escaped")
	}
}

func TestAvroDefaultRefinementUnknownIsExplicit(t *testing.T) {
	project := avroProject(t, `{"type":"record","name":"Counter","fields":[{"name":"count","type":"int","default":1}]}`)
	source := "loop :: Int32 -> Bool\nloop n = loop n\ntype Unresolved = Int32 where loop it @steps 20\ntype Counter = {count :: Unresolved}\ntype Datum = Counter\n"
	checked, err := project.WithEditedSource(source)
	if err != nil {
		t.Fatalf("unknown default must not reject compilation: %v", err)
	}
	checks := checked.AvroDefaultChecks()
	if len(checks) != 1 || checks[0].State != "indeterminate" || checks[0].Code != "native.default.unknown" {
		t.Fatalf("unknown default was claimed valid: %+v", checks)
	}
}

func TestAvroDefaultRefinementUsesFirstMatchingUnionBranch(t *testing.T) {
	schema := `{"type":"record","name":"Measure","fields":[{"name":"amount","type":["int","double"],"default":1.0}]}`
	project := avroProject(t, schema)
	source := project.EditableSource()
	edited := strings.Replace(source, "Branch2 (Real)", "Branch2 (Real where it > 2.0)", 1)
	if edited == source {
		t.Fatal("projected second union branch absent")
	}
	if _, err := project.WithEditedSource(edited); problemCode(err) != "native.default-refinement" {
		t.Fatalf("lexically floating default selected the integer branch or bypassed refinement: %v", err)
	}
}

func TestAvroDefaultChecksRecomputedAcrossBundle(t *testing.T) {
	schema := `{"type":"record","name":"Counter","fields":[{"name":"count","type":"long","default":2}]}`
	project := avroProject(t, schema)
	source := "type Count = Int64 where fromInt64 it > 1\ntype Counter = {count :: Count}\ntype Datum = Counter\n"
	project, err := project.WithEditedSource(source)
	if err != nil {
		t.Fatal(err)
	}
	bundle, err := project.Bundle()
	if err != nil {
		t.Fatal(err)
	}
	again, err := ParseBundle(bundle)
	if err != nil {
		t.Fatal(err)
	}
	if checks := again.AvroDefaultChecks(); len(checks) != 1 || checks[0].State != "valid" {
		t.Fatalf("bundle did not recheck reader defaults: %+v", checks)
	}
}

func TestAvroDefaultRefinementTraversesDependenciesAndScalarMetadata(t *testing.T) {
	resources := []Resource{{URI: "urn:avro:address", Source: `{"type":"record","name":"Address","fields":[{"name":"zip","type":"int","default":0}]}`}, {URI: "urn:avro:person", Source: `{"type":"record","name":"Person","fields":[{"name":"address","type":"Address"}]}`}}
	project, err := IngestProjectResources(Avro, resources, ProjectOptions{Root: ResourceSelector{Resource: "urn:avro:person", TypeName: "PersonDatum"}})
	if err != nil {
		t.Fatal(err)
	}
	source := strings.Replace(project.EditableSource(), "zip :: Int32", "zip :: Positive", 1) + "\ntype Positive = Int32 where fromInt32 it > 0\n"
	if _, err = project.WithEditedSource(source); problemCode(err) != "native.default-refinement" {
		t.Fatalf("dependency default refinement was not checked: %v", err)
	}
	annotated := `{"type":"record","name":"Counter","fields":[{"name":"count","type":"string","default":"0"}],"x-refine":{"source":"type Exact = Int where it > 0\ntype Counter = {count :: Exact}\n","root":"Counter"}}`
	if _, err = IngestProject(Avro, []byte(annotated), ProjectOptions{Root: ResourceSelector{TypeName: "Counter"}, Metadata: WireMetadata{Scalars: map[string]ScalarEncoding{"Exact": {Kind: DecimalString}}}}); problemCode(err) != "native.default-refinement" {
		t.Fatalf("metadata-decoded default bypassed refinements: %v", err)
	}
}

func rationalCarrierSchema(numerator, denominator string) string {
	return `{"type":"record","name":"AmountWire","fields":[{"name":"numerator","type":"bytes","default":"` + numerator + `"},{"name":"denominator","type":"bytes","default":"` + denominator + `"}],"x-refine":{"source":"type Amount = Real where it > 0.0\n","root":"Amount"}}`
}

func TestAvroRationalCarrierDefaultsAreNeverSilentlySkipped(t *testing.T) {
	options := ProjectOptions{Root: ResourceSelector{TypeName: "Amount"}, Metadata: WireMetadata{Scalars: map[string]ScalarEncoding{"Amount": {Kind: RationalRecord}}}}
	for _, source := range []string{
		rationalCarrierSchema(`\u0001`, `\u0000`),
		rationalCarrierSchema(`\u0000\u0001`, `\u0002`),
		rationalCarrierSchema(`\u00ff`, `\u0001`),
	} {
		if _, err := IngestProject(Avro, []byte(source), options); problemCode(err) != "native.default-refinement" {
			t.Fatalf("invalid rational carrier default was accepted: %v", err)
		}
	}
	project, err := IngestProject(Avro, []byte(rationalCarrierSchema(`\u0001`, `\u0002`)), options)
	if err != nil {
		t.Fatal(err)
	}
	checks := project.AvroDefaultChecks()
	if len(checks) != 2 {
		t.Fatalf("carrier defaults disappeared from the explicit audit: %+v", checks)
	}
	for _, check := range checks {
		if check.State != "indeterminate" || check.Code != "native.default.unknown" {
			t.Fatalf("contextual carrier default was mislabeled: %+v", checks)
		}
	}
}

func TestAvroDefaultTraversalFailuresAreExplicit(t *testing.T) {
	project := avroProject(t, `{"type":"record","name":"AliasTarget","fields":[{"name":"value","type":"int","default":0}]}`)
	var source strings.Builder
	source.WriteString("type Positive = Int32 where fromInt32 it > 0\n")
	for i := 0; i < 514; i++ {
		source.WriteString("type Alias" + fmt.Sprint(i) + " = Alias" + fmt.Sprint(i+1) + "\n")
	}
	source.WriteString("type Alias514 = {value :: Positive}\ntype Datum = Alias0\n")
	deep, err := project.WithEditedSource(source.String())
	if err != nil {
		t.Fatalf("checked alias chain failed before bounded default traversal: %v", err)
	}
	found := false
	for _, check := range deep.AvroDefaultChecks() {
		if check.State == "indeterminate" && check.Code == "native.limit" {
			found = true
		}
	}
	if !found {
		t.Fatalf("deep reachable default traversal returned empty success: %+v", deep.AvroDefaultChecks())
	}

	typ := &language.Type{Form: language.NamedType{Name: "x"}}
	for i := 0; i < 514; i++ {
		typ = &language.Type{Form: language.ListType{Element: typ}}
	}
	schema, err := parseAvroStructure([]byte(`["int","string"]`), &avro.SchemaCache{})
	if err != nil {
		t.Fatal(err)
	}
	walker := avroDefaultWalker{project: &Project{root: ResourceSelector{Resource: "urn:test"}}, unknown: map[string]bool{}}
	variants := []language.Variant{{Name: "Deep", Arguments: []*language.Type{typ}}, {Name: "Text", Arguments: []*language.Type{{Form: language.NamedType{Name: "String"}}}}}
	if err := walker.union(variants, schema, map[string]*language.Type{"x": {Form: language.NamedType{Name: "Int32"}}}, 0); err != nil {
		t.Fatal(err)
	}
	if len(walker.checks) != 1 || walker.checks[0].Code != "native.limit" {
		t.Fatalf("substitution limit was silently skipped: %+v", walker.checks)
	}
	malformed := avroDefaultWalker{project: &Project{root: ResourceSelector{Resource: "urn:test"}}, unknown: map[string]bool{}}
	bad := []language.Variant{{Name: "Bad", Arguments: []*language.Type{nil}}, {Name: "Text", Arguments: []*language.Type{{Form: language.NamedType{Name: "String"}}}}}
	if err := malformed.union(bad, schema, map[string]*language.Type{"x": {Form: language.NamedType{Name: "Int32"}}}, 0); problemCode(err) != "native.default-refinement" {
		t.Fatalf("malformed substitution was not propagated: %v", err)
	}
	if err := malformed.walk(&language.Type{Form: language.NamedType{Name: "Unbound"}}, schema.(*avro.UnionSchema).Types()[0], nil, "", 0); problemCode(err) != "native.default-refinement" {
		t.Fatalf("unbound checked type was silently skipped: %v", err)
	}
}
