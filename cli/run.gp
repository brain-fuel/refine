// Package cli provides the testable command-line boundary. Filesystem access
// belongs here, never in the refinement predicate evaluator.
package cli

import (
    "encoding/json"
    "errors"
    "fmt"
    "io"
    "os"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
)

const usage = `refine — refinement schema tooling (development)

Usage:
  refine typecheck [--json] <source.refine|->
  refine check-schema [--json] [--total-steps N] [--clause-steps N] <source.refine|->
  refine fmt <source.refine|->
  refine inspect-json [--json] <document.json|->
  refine explain [--json] <source.refine|->
  refine validate [--json] [--total-steps N] [--clause-steps N] <source.refine|-> <type> <payload.txt|->
  refine validate-native [--json] <json-schema|avro|openapi> <schema|->
  refine satisfiable [--json] <source.refine|-> <type>
  refine compare-payload [--json] <old.refine|-> <old-type> <new.refine|-> <new-type>
  refine project generate [--root DIR] [--config FILE] [--package NAME] [--output DIR] [--flat] [--check] [--json]
  refine project maven [--root DIR] [--config FILE] [--executable PATH] [--native-regex]
  refine release plan [--root DIR] [--config FILE] [--json] [family...]
  refine release promote [--root DIR] [--config FILE] [--json] [family...]
  refine release recover [--root DIR]
  refine native ingest [--resource URI] [--pointer PTR] [--type NAME] [--resources FILE] <json-schema|avro|openapi> <schema|->
  refine native source <bundle|->
  refine native update <bundle|-> <source.refine|->
  refine native original <bundle|->
  refine native validate-payload [--native-only] [--avro-json] [--json] [--total-steps N] [--clause-steps N] <bundle|-> <payload|->

typecheck checks the language's static rules; it is not yet native schema,
satisfiability, compatibility, or payload validation.
check-schema also rejects proven-empty declarations and reports unknown proofs;
unknown satisfiability allows compilation and is never described as proven valid.
fmt writes formatted source to stdout and never overwrites the input file.
inspect-json checks JSON syntax and duplicate keys, not schema validity.
validate reads canonical Refine value text, not JSON or Avro wire data.
validate-native validates native document structure offline, not payloads.
explain emits complete demand-driven English instructions without running predicates.
satisfiable and compare-payload use conservative logical numeric proofs; unsupported
cases are unknown. compare-payload enforces backward inclusion only and is not a
native-wire, Java-ABI, or full release-compatibility check.
Use - to read stdin. Maven deployment is not performed by these commands.
`

type diagnostic struct {
    Code string `json:"code"`
    Message string `json:"message"`
    Line int `json:"line,omitempty"`
    Column int `json:"column,omitempty"`
    Offset int `json:"offset,omitempty"`
    Path string `json:"path,omitempty"`
}
type report struct {
    Phase string `json:"phase"`
    State string `json:"state"`
    Summary string `json:"summary,omitempty"`
    Diagnostics []diagnostic `json:"diagnostics"`
    Result any `json:"result,omitempty"`
}

func load(path string, input io.Reader) ([]byte,error) {
    reader := input
    if path != "-" {
        file, err := os.Open(path); if err != nil { return nil, err }
        defer file.Close(); reader = file
    }
    return io.ReadAll(io.LimitReader(reader,16*1024*1024+1))
}

// Run returns 0 for a successful requested phase, 1 for a failed phase, and 2
// for usage/I/O failure. JSON mode writes one report on stdout; human failures
// go to stderr. Neither mode echoes payload values by default.
func Run(args []string, input io.Reader, output, errorOutput io.Writer) int {
    if len(args) == 0 || args[0] == "help" || args[0] == "--help" {
        if _, err := io.WriteString(output,usage); err != nil { return 2 }; return 0
    }
    command := args[0]
    if command=="project"{return projectCommand(args[1:],output,errorOutput)}
    if command=="release"{return releaseCommand(args[1:],output,errorOutput)}
    if command=="native"{return nativeCommand(args[1:],input,output,errorOutput)}
    switch command{case "explain","validate","validate-native","satisfiable","compare-payload","check-schema":return workflow(args,input,output,errorOutput)}
    if command != "typecheck" && command != "fmt" && command != "inspect-json" { fmt.Fprintln(errorOutput,"unknown command; use refine help"); return 2 }
    jsonMode, path := false, ""
    for _, arg := range args[1:] {
        if arg == "--json" {
            if jsonMode || command == "fmt" { fmt.Fprintln(errorOutput,"--json is not valid here"); return 2 }; jsonMode = true
        } else if path == "" { path = arg
        } else { fmt.Fprintln(errorOutput,"expected exactly one input path or -"); return 2 }
    }
    if path == "" { fmt.Fprintln(errorOutput,"expected an input path or -"); return 2 }
    source, err := load(path,input)
    if err != nil { fmt.Fprintln(errorOutput,"cannot read input:",err); return 2 }
    result := report{Phase:command,State:"valid",Diagnostics:[]diagnostic{}}
    switch command {
    case "typecheck":
        var program *language.Program
        program, err = language.Compile(string(source))
        if err == nil { result.Summary = program.Summary() }
    case "fmt":
        var module *language.Module
        module, err = language.Parse(string(source))
        if err == nil { if _, failure := io.WriteString(output,language.Format(module)); failure != nil { return 2 }; return 0 }
    case "inspect-json":
        var document schemajson.Document
        document, err = schemajson.Parse(source,schemajson.Limits{})
        if err == nil { result.Summary = "JSON " + schemajson.KindName(document.Root().Kind()) + "; syntax and duplicate-key checks passed" }
    }
    code := 0
    if err != nil {
        code = 1; result.State = "invalid"
        detail := diagnostic{Code:"refine.error",Message:err.Error()}
        var languageError *language.Error
        var jsonError *schemajson.Error
        if errors.As(err,&languageError) {
            detail = diagnostic{Code:languageError.Code,Message:languageError.Message,Line:languageError.At.Start.Line,Column:languageError.At.Start.Column,Offset:languageError.At.Start.Offset}
            if languageError.Code == "language.limit" { result.State = "indeterminate" }
        } else if errors.As(err,&jsonError) {
            detail = diagnostic{Code:jsonError.Code,Message:jsonError.Message,Path:jsonError.Path,Offset:jsonError.Offset}
            if jsonError.Code == "json.limit" { result.State = "indeterminate" }
        }
        result.Diagnostics = append(result.Diagnostics,detail)
    }
    if jsonMode {
        if err := json.NewEncoder(output).Encode(result); err != nil { return 2 }
    } else if code == 0 { if _, err := fmt.Fprintln(output,result.Summary); err != nil { return 2 }
    } else { if _, failure := fmt.Fprintln(errorOutput,err); failure != nil { return 2 } }
    return code
}
