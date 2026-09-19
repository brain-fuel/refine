package analysis

import (
    "crypto/sha256"
    "encoding/hex"
    "fmt"
    "sort"

    "goforge.dev/refine/language"
)

const ContractSyntaxVersion="refine.contract-syntax/v2"

// SyntaxDifference names the changed surface, never the predicate literal,
// function body, or diagnostic-message contents. Order is deterministic.
type SyntaxDifference struct {Kind string `json:"kind"`;Name string `json:"name,omitempty"`}
type ContractSyntaxEvidence struct {
    Version string `json:"version"`
    BaselineFingerprint string `json:"baselineFingerprint"`
    CandidateFingerprint string `json:"candidateFingerprint"`
    Equal bool `json:"equal"`
    Differences []SyntaxDifference `json:"differences"`
}

// CompareContractSyntax proves only identical canonical checked language
// syntax, ignoring comments, source positions and layout. It retains roots,
// publication packages, imports, declaration/field/equation order, signatures,
// predicates, diagnostic codes/messages and budgets. A difference is not a
// proof of changed accepted values: arbitrary predicate equivalence remains
// undecidable. Callers must separately compare native resources, wire metadata,
// dependency identities and generated APIs before approving documentation-only
// release classifications.
func CompareContractSyntax(baseline *language.Program,baselineRoot string,candidate *language.Program,candidateRoot string)(ContractSyntaxEvidence,error){
    if baseline==nil||candidate==nil{return ContractSyntaxEvidence{},fmt.Errorf("analysis: two checked programs are required")}
    if _,err:=baseline.PayloadType(baselineRoot);err!=nil{return ContractSyntaxEvidence{},err};if _,err:=candidate.PayloadType(candidateRoot);err!=nil{return ContractSyntaxEvidence{},err}
    old,next:=baseline.Syntax(),candidate.Syntax();old.ReleasePolicy=nil;next.ReleasePolicy=nil;oldCanonical,nextCanonical:=language.Format(old),language.Format(next)
    result:=ContractSyntaxEvidence{Version:ContractSyntaxVersion,BaselineFingerprint:contractSyntaxDigest(baselineRoot,oldCanonical),CandidateFingerprint:contractSyntaxDigest(candidateRoot,nextCanonical),Equal:baselineRoot==candidateRoot&&oldCanonical==nextCanonical,Differences:[]SyntaxDifference{}}
    if result.Equal{return result,nil}
    if baselineRoot!=candidateRoot{result.Differences=append(result.Differences,SyntaxDifference{Kind:"root"})}
    if old.Limits.Total!=next.Limits.Total||old.Limits.Clause!=next.Limits.Clause{result.Differences=append(result.Differences,SyntaxDifference{Kind:"limits"})}
    if old.Package!=next.Package{result.Differences=append(result.Differences,SyntaxDifference{Kind:"package"})}
    if !sameSyntaxImports(old.Imports,next.Imports){result.Differences=append(result.Differences,SyntaxDifference{Kind:"imports"})}
    if language.FormatOpenAPI(old.OpenAPI)!=language.FormatOpenAPI(next.OpenAPI){result.Differences=append(result.Differences,SyntaxDifference{Kind:"openapi"})}
    oldTypes,nextTypes:=map[string]string{},map[string]string{};for _,decl:=range old.Types{oldTypes[decl.Name]=language.Format(&language.Module{Types:[]language.TypeDecl{decl}})};for _,decl:=range next.Types{nextTypes[decl.Name]=language.Format(&language.Module{Types:[]language.TypeDecl{decl}})}
    oldFunctions,nextFunctions:=map[string]string{},map[string]string{};for _,fn:=range old.Functions{oldFunctions[fn.Name]=language.Format(&language.Module{Functions:[]language.Function{fn}})};for _,fn:=range next.Functions{nextFunctions[fn.Name]=language.Format(&language.Module{Functions:[]language.Function{fn}})}
    result.Differences=append(result.Differences,namedSyntaxDifferences("type",oldTypes,nextTypes)...);result.Differences=append(result.Differences,namedSyntaxDifferences("function",oldFunctions,nextFunctions)...)
    if !sameTypeOrder(old.Types,next.Types){result.Differences=append(result.Differences,SyntaxDifference{Kind:"type-order"})};if !sameFunctionOrder(old.Functions,next.Functions){result.Differences=append(result.Differences,SyntaxDifference{Kind:"function-order"})}
    return result,nil
}

func contractSyntaxDigest(root,canonical string)string{sum:=sha256.Sum256([]byte(ContractSyntaxVersion+"\x00"+root+"\x00"+canonical));return hex.EncodeToString(sum[:])}
func sameSyntaxImports(a,b []language.Import)bool{if len(a)!=len(b){return false};for i,item:=range a{if item.Path!=b[i].Path{return false}};return true}
func sameTypeOrder(a,b []language.TypeDecl)bool{if len(a)!=len(b){return false};for i,item:=range a{if item.Name!=b[i].Name{return false}};return true}
func sameFunctionOrder(a,b []language.Function)bool{if len(a)!=len(b){return false};for i,item:=range a{if item.Name!=b[i].Name{return false}};return true}
func namedSyntaxDifferences(kind string,a,b map[string]string)[]SyntaxDifference{names:=map[string]bool{};for name:=range a{names[name]=true};for name:=range b{names[name]=true};ordered:=make([]string,0,len(names));for name:=range names{ordered=append(ordered,name)};sort.Strings(ordered);result:=[]SyntaxDifference{};for _,name:=range ordered{old,oldExists:=a[name];next,nextExists:=b[name];if oldExists&&nextExists&&old==next{continue};change:="changed";if !oldExists{change="added"}else if !nextExists{change="removed"};result=append(result,SyntaxDifference{Kind:kind+"-"+change,Name:name})};return result}
