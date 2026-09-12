// GoPlus-authored executable Java coverage for every worked contract family.
package java

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"goforge.dev/refine/analysis"
	"goforge.dev/refine/language"
	"goforge.dev/refine/validation"
	"goforge.dev/refine/value"
)

type workedPropertySample struct {
	raw      string
	expected PropertyOutcome
	code     string
}
type workedPropertyCase struct {
	file      string
	root      string
	namespace string
	seed      int64
	samples   []workedPropertySample
}

func workedExampleData(t *testing.T, program *language.Program, root, raw string) value.Data {
	t.Helper()
	text, err := value.TextFromUTF8(raw)
	if err != nil {
		t.Fatal(err)
	}
	data, report := program.ReadDataWithoutRefinements(root, text, validation.Limits{})
	if validation.StateName(report.State()) != "valid" {
		t.Fatalf("%s example is not structurally readable: %s %+v", root, raw, report.Diagnostics())
	}
	return data
}

func addWorkedPropertySuite(t *testing.T, files *[]File, test workedPropertyCase) {
	t.Helper()
	source, err := os.ReadFile(filepath.Join("..", "examples", test.file))
	if err != nil {
		t.Fatal(err)
	}
	program, err := language.Compile(string(source))
	if err != nil {
		t.Fatal(err)
	}
	models, err := GenerateModels(program, test.namespace, "Contract")
	if err != nil {
		t.Fatal(err)
	}
	examples := []PropertyExample{}
	for _, sample := range test.samples {
		codes := []string{}
		if sample.code != "" {
			codes = []string{sample.code}
		}
		examples = append(examples, PropertyExample{Target: test.root, Value: workedExampleData(t, program, test.root, sample.raw), Expected: sample.expected, DiagnosticCodes: codes})
	}
	properties, err := GeneratePropertyTests(program, test.namespace, "Contract", PropertyTestOptions{Targets: []PropertyTarget{{Name: test.root}}, CaseCount: 3, AttemptBudget: 64, Seed: test.seed, Examples: examples})
	if err != nil {
		t.Fatal(err)
	}
	for _, sample := range test.samples {
		if sample.code != "" && !strings.Contains(properties[0].Source, "invalid "+test.root+" "+sample.code) {
			t.Fatalf("%s property suite omitted %s", test.root, sample.code)
		}
	}
	if test.root == "Booking" && !strings.Contains(properties[0].Source, `new Data.Text("2026-01-01T00:00:00Z")`) {
		t.Fatal("Booking timestamp example was not emitted as canonical model Data")
	}
	*files = append(*files, models...)
	*files = append(*files, properties...)
}

func addPropertyTargetingRegressions(t *testing.T, files *[]File) {
	t.Helper()
	source := `type Dependent = Int where it > 0 @code "dependent.primary" where it > 1 @code "dependent.secondary"`
	program, err := language.Compile(source)
	if err != nil {
		t.Fatal(err)
	}
	negative := value.OfNumber(value.Integer(-1))
	for _, fixture := range []struct {
		namespace string
		source    string
		code      string
	}{
		{"example.targetsecondary", source, "dependent.primary"},
		{"example.targetmissing", source, "dependent.missing"},
		{"example.targetincomplete", `type Dependent = Int where False @code "dependent.primary" where 1 / 0 > 0.0 @code "dependent.unknown"`, "dependent.primary"},
	} {
		p := program
		if fixture.source != source {
			p, err = language.Compile(fixture.source)
			if err != nil {
				t.Fatal(err)
			}
		}
		models, modelErr := GenerateModels(p, fixture.namespace, "Contract")
		if modelErr != nil {
			t.Fatal(modelErr)
		}
		properties, propertyErr := GeneratePropertyTests(p, fixture.namespace, "Contract", PropertyTestOptions{Targets: []PropertyTarget{{Name: "Dependent"}}, CaseCount: 2, AttemptBudget: 32, Seed: 733, Examples: []PropertyExample{{Target: "Dependent", Value: negative, Expected: ExampleInvalid, DiagnosticCodes: []string{fixture.code}}}})
		if propertyErr != nil {
			t.Fatal(propertyErr)
		}
		*files = append(*files, models...)
		*files = append(*files, properties...)
	}
}

func addEvolutionSuites(t *testing.T, files *[]File) {
	t.Helper()
	oldSource, err := os.ReadFile(filepath.Join("..", "examples", "evolution", "v1.0.0.refine"))
	if err != nil {
		t.Fatal(err)
	}
	newSource, err := os.ReadFile(filepath.Join("..", "examples", "evolution", "SNAPSHOT.refine"))
	if err != nil {
		t.Fatal(err)
	}
	oldProgram, err := language.Compile(string(oldSource))
	if err != nil {
		t.Fatal(err)
	}
	newProgram, err := language.Compile(string(newSource))
	if err != nil {
		t.Fatal(err)
	}
	result, err := analysis.Compare(oldProgram, "Age", newProgram, "Age", validation.Limits{})
	if err != nil || result.Backward.Outcome != analysis.Yes || result.Forward.Outcome != analysis.No {
		t.Fatalf("evolution direction: %+v %v", result, err)
	}
	for _, item := range []struct {
		program   *language.Program
		namespace string
		seed      int64
		valid     string
		invalid   string
	}{{oldProgram, "example.evolution.v1_0_0", 809, "0", "-1"}, {newProgram, "example.evolution.snapshot", 811, "-1", "-2"}} {
		models, modelErr := GenerateModels(item.program, item.namespace, "Contract")
		if modelErr != nil {
			t.Fatal(modelErr)
		}
		examples := []PropertyExample{{Target: "Age", Value: workedExampleData(t, item.program, "Age", item.valid), Expected: ExampleValid}, {Target: "Age", Value: workedExampleData(t, item.program, "Age", item.invalid), Expected: ExampleInvalid, DiagnosticCodes: []string{"age.minimum"}}}
		properties, propertyErr := GeneratePropertyTests(item.program, item.namespace, "Contract", PropertyTestOptions{Targets: []PropertyTarget{{Name: "Age"}}, CaseCount: 3, AttemptBudget: 64, Seed: item.seed, Examples: examples})
		if propertyErr != nil {
			t.Fatal(propertyErr)
		}
		*files = append(*files, models...)
		*files = append(*files, properties...)
	}
}

func TestWorkedExamplesGenerateExecutableJava(t *testing.T) {
	cases := []workedPropertyCase{
		{"booking.refine", "Booking", "example.booking", 701, []workedPropertySample{
			{`{checkIn = "2026-01-01T00:00:00Z", checkOut = "2026-01-02T00:00:00Z"}`, ExampleValid, ""},
			{`{checkIn = "2026-01-02T00:00:00Z", checkOut = "2026-01-01T00:00:00Z"}`, ExampleInvalid, "booking.order"},
			{`{checkIn = "2026-01-01T00:00:00Z", checkOut = "2026-03-02T00:00:00Z"}`, ExampleInvalid, "booking.maximum_stay"},
		}},
		{"invoice.refine", "Invoice", "example.invoice", 703, []workedPropertySample{
			{`{lines = [{price = 1.005, quantity = 1}, {price = 1.015, quantity = 1}], totalCents = 202}`, ExampleValid, ""},
			{`{lines = [{price = -1, quantity = 1}], totalCents = -100}`, ExampleInvalid, "invoice.price.nonnegative"},
			{`{lines = [{price = 1, quantity = 0}], totalCents = 0}`, ExampleInvalid, "invoice.quantity.positive"},
			{`{lines = [], totalCents = 0}`, ExampleInvalid, "invoice.nonempty"},
			{`{lines = [{price = 1.005, quantity = 1}], totalCents = 101}`, ExampleInvalid, "invoice.total"},
		}},
		{"batch.refine", "Batch", "example.batch", 709, []workedPropertySample{
			{`[{id = "root", parent = Nothing}, {id = "child", parent = Just "root"}]`, ExampleValid, ""},
			{`[{id = "same", parent = Nothing}, {id = "same", parent = Nothing}]`, ExampleInvalid, "batch.unique_id"},
			{`[{id = "child", parent = Just "missing"}]`, ExampleInvalid, "batch.parent_reference"},
		}},
		{"deployment.refine", "Deployment", "example.deployment", 719, []workedPropertySample{
			{`[{id = "db", dependencies = []}, {id = "api", dependencies = ["db"]}]`, ExampleValid, ""},
			{`[{id = "same", dependencies = []}, {id = "same", dependencies = []}]`, ExampleInvalid, "deployment.unique_id"},
			{`[{id = "db", dependencies = ["api"]}, {id = "api", dependencies = ["db"]}]`, ExampleInvalid, "deployment.acyclic_references"},
		}},
		{"payment.refine", "Payment", "example.payment", 727, []workedPropertySample{
			{`Card "token" 1.25`, ExampleValid, ""},
			{`BankTransfer "x" 0`, ExampleInvalid, "payment.details"},
		}},
		{"expression.refine", "Expression", "example.expression", 733, []workedPropertySample{
			{`IfThenElse (EqualExpr (IntegerLiteral 1) (IntegerLiteral 2)) (Plus (IntegerLiteral 3) (IntegerLiteral 4)) (IntegerLiteral 0)`, ExampleValid, ""},
			{`Plus (IntegerLiteral 1) (BooleanLiteral True)`, ExampleInvalid, "expression.type_consistency"},
		}},
		{"polygon.refine", "Polygon", "example.polygon", 739, []workedPropertySample{
			{`[{x = 0, y = 0}, {x = 2, y = 0}, {x = 2, y = 2}, {x = 0, y = 2}, {x = 0, y = 0}]`, ExampleValid, ""},
			{`[{x = 0, y = 0}, {x = 2, y = 0}, {x = 2, y = 2}]`, ExampleInvalid, "polygon.minimum_vertices"},
			{`[{x = 0, y = 0}, {x = 2, y = 0}, {x = 2, y = 2}, {x = 0, y = 2}]`, ExampleInvalid, "polygon.closed"},
			{`[{x = 0, y = 0}, {x = 2, y = 0}, {x = 2, y = 0}, {x = 2, y = 2}, {x = 0, y = 2}, {x = 0, y = 0}]`, ExampleInvalid, "polygon.distinct_vertices"},
			{`[{x = 0, y = 0}, {x = 1, y = 0}, {x = 2, y = 0}, {x = 0, y = 0}]`, ExampleInvalid, "polygon.nonzero_area"},
			{`[{x = 0, y = 0}, {x = 3, y = 3}, {x = 0, y = 3}, {x = 2, y = 0}, {x = 0, y = 0}]`, ExampleInvalid, "polygon.nonintersection"},
		}},
	}
	compiler, vm := javaTools(t)
	classpath := jetCheckClasspath(t)
	files := []File{}
	for _, test := range cases {
		addWorkedPropertySuite(t, &files, test)
	}
	addEvolutionSuites(t, &files)
	addPropertyTargetingRegressions(t, &files)
	files = append(files, File{Path: "WorkedExamplesHarness.java", Source: workedExamplesHarnessJava})
	dir := t.TempDir()
	sources := []string{}
	for _, file := range files {
		target := filepath.Join(dir, filepath.FromSlash(file.Path))
		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(target, []byte(file.Source), 0644); err != nil {
			t.Fatal(err)
		}
		sources = append(sources, target)
	}
	classes := filepath.Join(dir, "classes")
	args := append([]string{"--release", "25", "-encoding", "UTF-8", "-Xlint:all", "-Werror", "-cp", classpath, "-d", classes}, sources...)
	compileContext, stopCompile := context.WithTimeout(context.Background(), 45*time.Second)
	defer stopCompile()
	if output, err := exec.CommandContext(compileContext, compiler, args...).CombinedOutput(); err != nil {
		t.Fatalf("worked examples javac: %v\n%s", err, output)
	}
	runContext, stopRun := context.WithTimeout(context.Background(), 45*time.Second)
	defer stopRun()
	if output, err := exec.CommandContext(runContext, vm, "-Xss256k", "-Xmx64m", "-cp", classes+string(os.PathListSeparator)+classpath, "WorkedExamplesHarness").CombinedOutput(); err != nil {
		t.Fatalf("worked examples runtime: %v\n%s", err, output)
	}
}

const workedExamplesHarnessJava = `
public final class WorkedExamplesHarness {
 private static void expectFailure(Runnable action,String fragment){try{action.run();}catch(AssertionError expected){if(expected.getMessage()!=null&&expected.getMessage().contains(fragment))return;throw expected;}throw new AssertionError("expected generated suite failure: "+fragment);}
 public static void main(String[] args){
  example.booking.ContractGeneratedProperties.main(args);
  example.invoice.ContractGeneratedProperties.main(args);
  example.batch.ContractGeneratedProperties.main(args);
  example.deployment.ContractGeneratedProperties.main(args);
  example.payment.ContractGeneratedProperties.main(args);
  example.expression.ContractGeneratedProperties.main(args);
  example.polygon.ContractGeneratedProperties.main(args);
  example.evolution.v1_0_0.ContractGeneratedProperties.main(args);
  example.evolution.snapshot.ContractGeneratedProperties.main(args);
  example.targetsecondary.ContractGeneratedProperties.main(args);
  expectFailure(()->example.targetmissing.ContractGeneratedProperties.main(args),"embedded example 0 diagnostic");
  expectFailure(()->example.targetincomplete.ContractGeneratedProperties.main(args),"embedded example 0 outcome");
  try{example.evolution.v1_0_0.Age.read("-1");throw new AssertionError("old Age accepted -1");}catch(example.evolution.v1_0_0.ValidationException expected){}
  example.evolution.v1_0_0.Age.read("0");example.evolution.snapshot.Age.read("0");example.evolution.snapshot.Age.read("-1");
 }
}
`
