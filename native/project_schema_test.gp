package native

import (
    "errors"
    "reflect"
    "testing"

    refineanalysis "goforge.dev/refine/analysis"
)

func TestProjectSchemaChecksRejectOnlySelectedEntrypoints(t *testing.T){
    annotated:=`{"type":"object","properties":{"value":{"type":"integer"}},"x-refine":{"source":"type Empty = Int where it > 0 && it < 1\ntype Root = { value :: Maybe Empty }\n","root":"Root"}}`;project,err:=IngestProject(JSONSchema,[]byte(annotated),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatalf("optional impossible field rejected inhabitable root: %v",err)};report:=project.SchemaChecks();if !reflect.DeepEqual(report.Roots,[]string{"Root"})||report.Findings[0].Finding.Outcome!=refineanalysis.No||report.Findings[1].Finding.Outcome!=refineanalysis.Unknown{t.Fatalf("scoped report lost optional-root evidence: %+v",report)}
    project,err=IngestProject(JSONSchema,[]byte(`{"type":"integer"}`),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};edited:="type Empty = Int where it >= 2 && it < 2\ntype Root = Int\n";if _,err=project.WithEditedSource(edited);err!=nil{t.Fatalf("unused impossible source edit was rejected: %v",err)};selected:="type Empty = Int where it >= 2 && it < 2\ntype Root = Int where it >= 2 && it < 2\n";_,err=project.WithEditedSource(selected);var proof *refineanalysis.SchemaError;if problemCode(err)!="native.schema"||!errors.As(err,&proof)||proof.Type!="Root"{t.Fatalf("proven-empty selected source edit was accepted: %v",err)}
    sources:=map[string]string{"types/empty.refine":"type ImportedEmpty = Int where it > 10 && it <= 10\n","types/main.refine":"import \"empty.refine\"\ntype Root = Int where it > 10 && it <= 10\n"};_,err=project.WithEditedSources("types/main.refine",sources);proof=nil;if problemCode(err)!="native.schema"||!errors.As(err,&proof)||proof.Type!="Root"{t.Fatalf("proven-empty imported selected source edit was accepted: %v",err)}
}

func TestProjectSchemaChecksIncludeOpenAPIEntrypoints(t *testing.T){
    project,err:=IngestProject(JSONSchema,[]byte(`{"type":"integer"}`),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};source:="type Root = Int\ntype Params = { id :: Int }\ntype Headers = {}\ntype Body = {}\ntype Request = { parameters :: Params, headers :: Headers, body :: Body } where False\ntype Response = { headers :: Headers, body :: Body }\ntype Context = { request :: Request, response :: Response }\n";project,err=project.WithEditedSource(source);if err!=nil{t.Fatal(err)};_,err=project.WithMetadata(operationWire());var proof *refineanalysis.SchemaError;if problemCode(err)!="native.schema"||!errors.As(err,&proof)||proof.Type!="Request"{t.Fatalf("proven-empty OpenAPI request entrypoint was accepted: %v",err)}
    if got:=SchemaEntrypoints("Root",operationWire());!reflect.DeepEqual(got,[]string{"Context","Request","Response","Root"}){t.Fatalf("operation proof roots not canonical: %+v",got)}
}

func TestProjectSchemaChecksRetainUnknownAndRecomputeOnBundle(t *testing.T){project,err:=IngestProject(JSONSchema,[]byte(`{"type":"integer"}`),ProjectOptions{Root:ResourceSelector{TypeName:"Root"}});if err!=nil{t.Fatal(err)};source:="loop :: Int -> Bool\nloop n = loop n\ntype Recursive = Int where loop it @steps 10\ntype Box a = {item :: a}\ntype Positive = Int where it > 0\ntype Root = Positive\n";project,err=project.WithEditedSource(source);if err!=nil{t.Fatalf("unknown satisfiability must not reject: %v",err)};report:=project.SchemaChecks();if !reflect.DeepEqual(report.Roots,[]string{"Root"})||len(report.Findings)!=4{t.Fatalf("missing proof scope or declaration findings: %+v",report)};want:=map[string]refineanalysis.Outcome{"Recursive":refineanalysis.Unknown,"Box":refineanalysis.Unknown,"Positive":refineanalysis.Yes,"Root":refineanalysis.Yes};for _,item:=range report.Findings{if item.Finding.Outcome!=want[item.Type]{t.Fatalf("phantom validity or changed classification for %s: %+v",item.Type,item.Finding)};if item.Type=="Box"&&item.Finding.Code!="analysis.generic"{t.Fatalf("generic declaration was not explicitly unknown: %+v",item.Finding)}}
    report.Roots[0]="changed";report.Findings[0].Type="changed";report.Findings[0].Finding.Outcome=refineanalysis.Yes;if got:=project.SchemaChecks();got.Roots[0]=="changed"||got.Findings[0].Type=="changed"{t.Fatal("SchemaChecks returned mutable project backing")}
    original:=project.SchemaChecks();bundle,err:=project.Bundle();if err!=nil{t.Fatal(err)};again,err:=ParseBundle(bundle);if err!=nil{t.Fatal(err)};if !reflect.DeepEqual(original,again.SchemaChecks()){t.Fatalf("bundle reload did not deterministically recompute schema checks: before=%+v after=%+v",original,again.SchemaChecks())}
}

func TestProjectSchemaProofPrecedesAvroDefaultRefinement(t *testing.T){project:=avroProject(t,`{"type":"record","name":"Counter","fields":[{"name":"count","type":"int","default":0}]}`);source:="type Empty = Int where it > 0 && it < 1\ntype Positive = Int32 where fromInt32 it > 0\ntype Counter = {count :: Positive}\ntype Datum = Int where it > 0 && it < 1\n";if _,err:=project.WithEditedSource(source);problemCode(err)!="native.schema"{t.Fatalf("Avro default checking obscured selected-root schema contradiction: %v",err)}}
