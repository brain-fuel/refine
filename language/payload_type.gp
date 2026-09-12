package language

import (
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

// PayloadType is an immutable, closed type checked in one Program's environment.
// It can instantiate generic declarations, compose records/collections and add
// arbitrary statically checked refinements. Creating a handle executes no rules.
// Its zero value is invalid; use Program.PayloadType to obtain a checked handle.
type PayloadType struct { program *Program; typ *Type; source string }

// CheckedPayloadType is a caller-owned generation snapshot. Type and all module
// expression pointers belong to Module's inferred-type map. Mutating a snapshot
// cannot change the handle, its Program, or a later snapshot.
type CheckedPayloadType struct { Module CheckedModule; Type *Type }

func (p *Program) PayloadType(source string)(target *PayloadType,failure error){
    defer recoverSyntax(&failure)
    if p==nil||p.module==nil{return nil,&Error{Code:"language.type",Message:"a compiled program is required"}}
    typ,err:=ParseTypeExpression(source);if err!=nil{return nil,err}
    // Recheck a private tree so additional inference neither mutates the source
    // Program nor introduces a synthetic declaration/extra validation layer.
    module,err:=Parse(p.module.Source);if err!=nil{panic("checked source stopped parsing")}
    checked:=checkModule(module,typ)
    return &PayloadType{program:checked,typ:typ,source:source},nil
}

func (t *PayloadType) Source()string{if t==nil{return ""};return t.source}
func (t *PayloadType) Formatted()string{if t==nil||t.typ==nil{return ""};return FormatType(t.typ)}
func (t *PayloadType) Syntax()*Type{
    if t==nil||t.typ==nil{return nil}
    typ,err:=ParseTypeExpression(t.source);if err!=nil{panic("checked payload type stopped parsing")};return typ
}
func (t *PayloadType) CheckedSyntax()CheckedPayloadType{
    if t==nil||t.typ==nil{return CheckedPayloadType{}}
    copy,err:=t.program.PayloadType(t.source);if err!=nil{panic("checked payload type stopped compiling")}
    module:=copy.program.module
    return CheckedPayloadType{Module:checkedModuleSnapshot(module),Type:copy.typ}
}
func invalidPayloadType()validation.Report{
    return validation.Collect([]validation.Check{validation.Violated(validation.Diagnostic{Code:"validation.root",Paths:[]string{""},Message:"Choose a checked payload type."})})
}
func (t *PayloadType) ValidateData(data value.Data,caller validation.Limits)validation.Report{return t.validateData(data,caller,false)}
func (t *PayloadType) ValidateDataWithoutRefinements(data value.Data,caller validation.Limits)validation.Report{return t.validateData(data,caller,true)}
func (t *PayloadType) validateData(data value.Data,caller validation.Limits,withoutRefinements bool)validation.Report{
    if t==nil||t.typ==nil||t.program==nil{return invalidPayloadType()}
    v:=&payloadValidator{program:t.program,declarations:make(map[string]TypeDecl),budget:validation.NewBudget(validation.Limits{},caller),withoutRefinements:withoutRefinements}
    for _,decl:=range t.program.module.Types{v.declarations[decl.Name]=decl}
    v.structure=newEvaluator(t.program.module,v.budget.BeginStructure());v.run(t.typ,data)
    return validation.Collect(v.checks)
}
func (t *PayloadType) ReadData(text value.Text,caller validation.Limits)(value.Data,validation.Report){
    if t==nil||t.typ==nil||t.program==nil{return value.Data{},invalidPayloadType()}
    return t.program.readDataType(t.typ,text,caller)
}

// ReadDataWithoutRefinements is the explicit structural-only text boundary for
// this closed type, including generic and inline-refined targets. It never runs
// a where clause and never bypasses shape, representation or resource checks.
func (t *PayloadType) ReadDataWithoutRefinements(text value.Text,caller validation.Limits)(value.Data,validation.Report){
    if t==nil||t.typ==nil||t.program==nil{return value.Data{},invalidPayloadType()}
    return t.program.readDataTypeMode(t.typ,text,caller,true)
}
