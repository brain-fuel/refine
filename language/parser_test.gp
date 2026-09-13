package language

import (
    "errors"
    "os"
    "strconv"
    "strings"
    "testing"
    "testing/quick"
)

func signed(n int32) string { return strconv.FormatInt(int64(n),10) }

func TestTokenCategoryNamesRemainIdentifiers(t *testing.T) {
    for _,name:=range []string{"text","number","name","newline","eof"}{
        source:=name+" :: Int -> Int\n"+name+" "+name+" = "+name+"\nentry :: Int\nentry = "+name+" 42"
        program,err:=Compile(source);if err!=nil{t.Fatalf("%s: %v",name,err)}
        if len(program.module.Functions)!=2{t.Fatalf("%s truncated the module",name)}
        expr,err:=ParseExpression(name);if err!=nil{t.Fatal(err)}
        match expr.Form{case Variable(actual):if actual!=name{t.Fatal(actual)};case _:t.Fatalf("%s became a literal/token",name)}
    }
    for _,source:=range []string{"import text","eof type Ignored = Int","type T = Int eof"}{if _,err:=Compile(source);err==nil{t.Fatalf("token impersonation accepted: %s",source)}}
}

func parsedExpression(t *testing.T, source string) *Expr {
    t.Helper(); e, err := ParseExpression(source); if err != nil { t.Fatal(err) }; return e
}
func TestExpressionPrecedence(t *testing.T) {
    cases := []struct { source string; formatted string }{
        {"it.age >= 0 && it.age < 18", "(((it).age >= 0) && ((it).age < 18))"},
        {"1 + 2 * 3", "(1 + (2 * 3))"},
        {"f x + g y", "((f x) + (g y))"},
        {"show it.age", "(show (it).age)"},
        {"f x y", "((f x) y)"},
        {"x : y : []", "(x : (y : []))"},
        {"1 - 2 - 3", "((1 - 2) - 3)"},
        {"-f x * 2", "((-(f x)) * 2)"},
        {"True || False && False", "(True || (False && False))"},
        {`"é"`, `"\u00e9"`},
    }
    for _, tc := range cases {
        t.Run(tc.source,func(t *testing.T) {
            e := parsedExpression(t,tc.source)
            if actual := FormatExpression(e); actual != tc.formatted { t.Errorf("got %s, want %s",actual,tc.formatted) }
            again := parsedExpression(t,FormatExpression(e))
            if FormatExpression(again) != tc.formatted { t.Fatal("formatter is not stable") }
        })
    }
}

func TestAgreedContractSyntax(t *testing.T) {
    data, err := os.ReadFile("testdata/contracts.refine"); if err != nil { t.Fatal(err) }
    module, err := Parse(string(data)); if err != nil { t.Fatal(err) }
    if module.Package != "com.example.contracts" || len(module.Types) != 8 || len(module.Functions) != 7 { t.Fatalf("declaration counts: package=%s, types=%d, functions=%d",module.Package,len(module.Types),len(module.Functions)) }
    formatted := Format(module)
    again, err := Parse(formatted); if err != nil { t.Fatalf("formatted module does not parse: %v\n%s",err,formatted) }
    if Format(again) != formatted { t.Fatal("module format/parse/format is not idempotent") }
    child := module.Types[2]
    match child.Body.Form {
    case RefinedType(_, rules):
        if len(rules) != 1 || rules[0].Code != "person.child_age_range" || rules[0].Message == nil { t.Fatal("where clause metadata lost") }
    case NamedType(_): t.Fatal("missing child refinement")
    case ListType(_): t.Fatal("unexpected child type")
    case AppliedType(_, _): t.Fatal("unexpected child type")
    case ArrowType(_, _): t.Fatal("unexpected child type")
    case RecordType(_): t.Fatal("unexpected child type")
    }
    percent := module.Types[3]
    match percent.Body.Form {
    case RefinedType(_, rules): if len(rules) != 2 { t.Fatal("repeated where clauses merged") }
    case NamedType(_): t.Fatal("missing percentage refinement")
    case ListType(_): t.Fatal("unexpected percentage type")
    case AppliedType(_, _): t.Fatal("unexpected percentage type")
    case ArrowType(_, _): t.Fatal("unexpected percentage type")
    case RecordType(_): t.Fatal("unexpected percentage type")
    }
}

func TestWhereAnnotationsAndComments(t *testing.T) {
    source := "{- outer {- nested -} comment -}\ntype Positive = Int where it > 0 @steps 123 @code \"positive\" @message \"positive required\"\n"
    module, err := Parse(source); if err != nil { t.Fatal(err) }
    if !strings.Contains(Format(module),"@steps 123") { t.Fatal("budget annotation lost") }
    imported, err := Parse("import \"../common.refine\"\n" + source)
    if err != nil || len(imported.Imports) != 1 || imported.Imports[0].Path != "../common.refine" { t.Fatal("import not parsed",err) }
}

func TestMalformedSyntax(t *testing.T) {
    cases := []string{
        "type X = {x :: Int, x :: String}", "type X = Int\ntype X = String",
        "type X = Int where", "type X = Int where it > 0 @steps 0",
        "type X = Int where it > 0 @unknown 2", "type X = Int where it > 0 @code \"\"",
        "type X = Int where it > 0 @steps 1 @steps 2", "{- unfinished",
        "type X = String where it == \"unterminated", "f x = \\y -> y",
        "f x = 01", "f x = 1e", "f x = case x of {}", "f x = {a = 1, a = 2}",
        "f :: Int\nf :: String", "package foo\npackage bar", "type lower = Int",
        "f x = \"\xff\"", "type X = (Int", "f x = x garbage :: Int",
    }
    for _, source := range cases {
        _, err := Parse(source)
        var problem *Error
        if !errors.As(err,&problem) || problem.Code != "language.syntax" { t.Errorf("expected syntax error for %q, got %v",source,err) }
    }
    _, err := Parse("type X = Int\n\ntype Y = @\n")
    var problem *Error
    if !errors.As(err,&problem) || problem.At.Start.Line != 3 || problem.At.Start.Column != 10 { t.Errorf("source position = %v",err) }
}

func TestExpressionFormattingProperty(t *testing.T) {
    property := func(a, b, c int32) bool {
        source := "(it.age >= " + signed(a) + " && it.age < " + signed(b) + ") || isAdult (people [" + signed(c) + "])"
        e, err := ParseExpression(source); if err != nil { return false }
        formatted := FormatExpression(e)
        next, err := ParseExpression(formatted)
        return err == nil && FormatExpression(next) == formatted
    }
    if err := quick.Check(property,&quick.Config{MaxCount:2000}); err != nil { t.Fatal(err) }
}

func FuzzParseFormat(f *testing.F) {
    data, err := os.ReadFile("testdata/contracts.refine"); if err != nil { f.Fatal(err) }
    for _, source := range []string{string(data),"type X = Int where it > 0", "f :: Int -> Int\nf n = n + 1", "", "{- nested {- -} -}", "type X = Int\n\n@releasePolicy \"{\\\"version\\\":1}\"\n", "type X = Int\n{-\n@releasePolicy \"ignored\"\n-}\n"} { f.Add(source) }
    f.Fuzz(func(t *testing.T,source string) {
        if len(source) > 65536 { return }
        module, err := Parse(source); if err != nil { return }
        formatted := Format(module)
        next, err := Parse(formatted)
        if err != nil { t.Fatalf("formatter produced invalid source: %v\n%s",err,formatted) }
        if Format(next) != formatted { t.Fatal("format/parse is not stable") }
    })
}

func TestSyntaxResourceLimits(t *testing.T) {
    for _, source := range []string{
        "f = " + strings.Repeat("1 + ",600) + "1",
        "f = " + strings.Repeat("(",600) + "1" + strings.Repeat(")",600),
        "type X = " + strings.Repeat("Maybe ",600) + "Int",
    } {
        _, err := Parse(source)
        var problem *Error
        if !errors.As(err,&problem) || problem.Code != "language.limit" { t.Errorf("missing resource diagnostic: %v",err) }
    }
}
