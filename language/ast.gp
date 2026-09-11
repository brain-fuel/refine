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
    Types []TypeDecl
    Functions []Function
}
type Import struct { Path string; At Span }
type TypeDecl struct { Name string; Parameters []string; Body *Type; Variants []Variant; At Span }
type Variant struct { Name string; Arguments []*Type; At Span }
type Function struct { Name string; Signature *Type; Equations []Equation; At Span }
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
    Apply(Function *Expr, Argument *Expr)
    Project(Record *Expr, Field string)
    Unary(Operator string, Operand *Expr)
    Binary(Operator string, Left *Expr, Right *Expr)
    Conditional(Condition *Expr, Then *Expr, Else *Expr)
    Let(Name string, Annotation *Type, Value *Expr, Body *Expr)
    Case(Value *Expr, Arms []CaseArm)
}
type FieldValue struct { Name string; Value *Expr; At Span }
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
