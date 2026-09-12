package analysis

import (
    "fmt"
    "sort"
    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
)

// SchemaFinding keeps unknown separate from a proof of an inhabited type.
// Findings follow declaration order, never map iteration order.
type SchemaFinding struct {Type string `json:"type"`;Finding Finding `json:"finding"`}
type SchemaReport struct {Roots []string `json:"roots"`;Findings []SchemaFinding `json:"findings"`}
type SchemaError struct {Type string;Finding Finding}
func (e *SchemaError)Error()string{return "schema.unsatisfiable: "+e.Type+": "+e.Finding.Explanation}

// CheckSchema rejects proven-empty declarations, while returning explicit
// unknown findings for unsupported proofs and uninstantiated generic types.
// It is separate from language.Compile: type checking alone is not a proof.
// The current proof fragment is deliberately the same as Satisfiable.
func CheckSchema(program *language.Program,limits validation.Limits)(SchemaReport,error){
    if program==nil{return SchemaReport{Roots:[]string{},Findings:[]SchemaFinding{}},fmt.Errorf("schema.program: a checked program is required")};roots:=[]string{};for _,decl:=range program.Syntax().Types{if len(decl.Parameters)==0{roots=append(roots,decl.Name)}};return checkSchemaRoots(program,roots,limits,false)
}

// CheckSchemaRoots classifies every declaration but rejects a proven-empty
// schema only when that declaration is an explicit closed entrypoint. An
// impossible unused definition or optional child cannot make an inhabitable
// selected root empty. Root order and duplicates do not affect the report.
func CheckSchemaRoots(program *language.Program,roots []string,limits validation.Limits)(SchemaReport,error){return checkSchemaRoots(program,roots,limits,true)}

func checkSchemaRoots(program *language.Program,roots []string,limits validation.Limits,requireRoots bool)(SchemaReport,error){
    report:=SchemaReport{Roots:[]string{},Findings:[]SchemaFinding{}}
    if program==nil{return report,fmt.Errorf("schema.program: a checked program is required")}
    declarations:=map[string]language.TypeDecl{};for _,decl:=range program.Syntax().Types{declarations[decl.Name]=decl};selected:=map[string]bool{};for _,root:=range roots{selected[root]=true};for root:=range selected{report.Roots=append(report.Roots,root)};sort.Strings(report.Roots);if requireRoots&&len(report.Roots)==0{return report,fmt.Errorf("schema.root: at least one closed entrypoint is required")};for _,root:=range report.Roots{decl,ok:=declarations[root];if !ok{return report,fmt.Errorf("schema.root: %s is not a declared type",root)};if len(decl.Parameters)>0{return report,fmt.Errorf("schema.root: %s is not a closed declaration",root)}}
    var rejected error
    for _,decl:=range program.Syntax().Types{
        finding:=Finding{Unknown,"analysis.generic","A generic declaration has no selected closed type arguments; satisfiability remains unknown."}
        if len(decl.Parameters)==0{var err error;finding,err=Satisfiable(program,decl.Name,limits);if err!=nil{return report,err}}
        report.Findings=append(report.Findings,SchemaFinding{Type:decl.Name,Finding:finding})
        if selected[decl.Name]&&finding.Outcome==No&&rejected==nil{rejected=&SchemaError{Type:decl.Name,Finding:finding}}
    }
    return report,rejected
}
