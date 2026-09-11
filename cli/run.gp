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
  refine fmt <source.refine|->
  refine inspect-json [--json] <document.json|->

typecheck checks the language's static rules; it is not yet native schema,
satisfiability, compatibility, or payload validation.
fmt writes formatted source to stdout and never overwrites the input file.
inspect-json checks JSON syntax and duplicate keys, not schema validity.
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
