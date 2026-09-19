// Package language implements the Haskell/ML-style refinement front end.
// Syntax trees are compiler-owned intermediate data, not runtime payload values.
package language

import "fmt"

type Position struct { Offset int; Line int; Column int }
type Span struct { Start Position; End Position }
type Error struct { Code string; At Span; Message string }
func (e *Error) Error() string { return fmt.Sprintf("%s at %d:%d: %s", e.Code, e.At.Start.Line, e.At.Start.Column, e.Message) }

type Module struct {
    Source string
    Package string
    Imports []Import
    Limits SchemaLimits
    ReleasePolicy *ReleasePolicy
    OpenAPI *OpenAPIDeclaration
    Types []TypeDecl
    Functions []Function
    // Immutable after Compile; deliberately absent from fresh Syntax() copies.
    inferred map[*Expr]*Type
    functionScopes map[string]map[string]string
    declarationScopes map[string]map[string]string
    functionCapabilities map[string][]CapabilityConstraint
}
// SchemaLimits are the contract-authored total validation budget and the
// default budget for a where clause. Zero is the immutable unspecified value;
// runtimes substitute the documented defaults.
type SchemaLimits struct { Total uint64; Clause uint64; At Span }
type Import struct { Path string; At Span }
type TypeDecl struct { Name string; Parameters []string; Body *Type; Variants []Variant; At Span }
type Variant struct { Name string; Arguments []*Type; At Span }
// CapabilityConstraint is an authored type-class requirement on one of a
// function signature's type variables. The checked snapshot separately exposes
// the complete explicit plus inferred capability set.
type CapabilityConstraint struct { Capability string; Variable string; At Span }
type Function struct { Name string; Constraints []CapabilityConstraint; Signature *Type; Equations []Equation; At Span }
type Equation struct { Patterns []*Pattern; Body *Expr; At Span }

type Type struct { Form TypeForm; At Span }
//goplus:derive off
type TypeForm enum {
    NamedType(Name string)
    ListType(Element *Type)
    AppliedType(Constructor *Type, Argument *Type)
    ArrowType(Argument *Type, Result *Type)
    RecordType(Fields []Field)
    RefinedType(Base *Type, Rules []Where)
}
type Field struct { Name string; Type *Type; At Span }
type Where struct { Predicate *Expr; Code string; Message *Expr; Steps uint64; At Span }

type Expr struct { Form ExprForm; At Span }
//goplus:derive off
type ExprForm enum {
    NumberLiteral(Text string)
    TextLiteral(Quoted string)
    BoolLiteral(Value bool)
    Variable(Name string)
    ListLiteral(Elements []*Expr)
    RecordLiteral(Fields []FieldValue)
    MapLiteral(Entries []MapValue)
    Apply(Function *Expr, Argument *Expr)
    Project(Record *Expr, Field string)
    Unary(Operator string, Operand *Expr)
    Binary(Operator string, Left *Expr, Right *Expr)
    Conditional(Condition *Expr, Then *Expr, Else *Expr)
    Let(Name string, Annotation *Type, Value *Expr, Body *Expr)
    Case(Value *Expr, Arms []CaseArm)
}
type FieldValue struct { Name string; Value *Expr; At Span }
// MapValue retains the original quoted token. Map identity uses the decoded
// UTF-16 key, so alternate escape spellings cannot create distinct entries.
type MapValue struct { Key string; Value *Expr; At Span }
type CaseArm struct { Pattern *Pattern; Body *Expr; At Span }

type Pattern struct { Form PatternForm; At Span }
//goplus:derive off
type PatternForm enum {
    BindPattern(Name string)
    WildPattern
    ConstructorPattern(Name string, Arguments []*Pattern)
    ListPattern(Elements []*Pattern)
    ConsPattern(Head *Pattern, Tail *Pattern)
    LiteralPattern(Value *Expr)
}
