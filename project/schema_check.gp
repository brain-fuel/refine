package project

import (
    "encoding/json"
    "goforge.dev/refine/analysis"
    "goforge.dev/refine/native"
    "goforge.dev/refine/validation"
)

func checkContractSchema(contract Contract)([]byte,error){
    var report analysis.SchemaReport;var err error
    if contract.NativeProject!=nil{report=contract.NativeProject.SchemaChecks()}else{report,err=analysis.CheckSchemaRoots(contract.Program,native.SchemaEntrypoints(contract.RootType,contract.Wire),validation.Limits{});if err!=nil{return nil,err}}
    data,err:=json.MarshalIndent(struct{Scope string `json:"scope"`;Report analysis.SchemaReport `json:"report"`}{"Only the explicit payload and OpenAPI operation entrypoints are rejection gates; every Refine declaration is still reported. Native schema validity and native satisfiability are separate checks.",report},"","  ");if err!=nil{return nil,err};return append(data,'\n'),nil
}
