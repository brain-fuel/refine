package language

import (
    "sort"
    "strconv"
    "strings"

    "goforge.dev/refine/value"
)

func compareMapText(left,right value.Text)int{return left.Compare(right)}

func quote(text string) string {
    v, err := value.TextFromUTF8(text)
    if err != nil { panic("compiler-owned text is not UTF-8") }
    return v.Show()
}

// FormatExpression produces deterministic, explicitly grouped source. It does
// not claim equivalence of arbitrarily rewritten predicates or change && into
// separate where clauses. Source provenance is tracked separately from layout.
func FormatExpression(e *Expr) string {
    match e.Form {
    case NumberLiteral(text): return text
    case TextLiteral(raw): text, _ := value.ReadText(raw); return text.Show()
    case BoolLiteral(b): if b { return "True" }; return "False"
    case Variable(name): return name
    case ListLiteral(items):
        parts := make([]string,len(items)); for i, item := range items { parts[i] = FormatExpression(item) }
        return "[" + strings.Join(parts,", ") + "]"
    case RecordLiteral(fields):
        parts := make([]string,len(fields)); for i, field := range fields { parts[i] = field.Name + " = " + FormatExpression(field.Value) }
        return "{" + strings.Join(parts,", ") + "}"
    case MapLiteral(entries):
        ordered:=append([]MapValue(nil),entries...);sort.Slice(ordered,func(i,j int)bool{left,_:=value.ReadText(ordered[i].Key);right,_:=value.ReadText(ordered[j].Key);return compareMapText(left,right)<0})
        parts:=make([]string,len(ordered));for i,entry:=range ordered{key,_:=value.ReadText(entry.Key);parts[i]=key.Show()+" = "+FormatExpression(entry.Value)}
        return "map {"+strings.Join(parts,", ")+"}"
    case Apply(fn, arg): return "(" + FormatExpression(fn) + " " + FormatExpression(arg) + ")"
    case Project(record, field): return "(" + FormatExpression(record) + ")." + field
    case Unary(op, operand): return "(" + op + FormatExpression(operand) + ")"
    case Binary(op, left, right): return "(" + FormatExpression(left) + " " + op + " " + FormatExpression(right) + ")"
    case Conditional(condition, yes, no): return "(if " + FormatExpression(condition) + " then " + FormatExpression(yes) + " else " + FormatExpression(no) + ")"
    case Let(name, annotation, bound, body):
        decl := name
        if annotation != nil { decl += " :: " + FormatType(annotation) }
        return "(let " + decl + " = " + FormatExpression(bound) + " in " + FormatExpression(body) + ")"
    case Case(subject, arms):
        parts := make([]string,len(arms)); for i, arm := range arms { parts[i] = FormatPattern(arm.Pattern) + " -> " + FormatExpression(arm.Body) }
        return "(case " + FormatExpression(subject) + " of { " + strings.Join(parts,"; ") + " })"
    }
}

func FormatPattern(p *Pattern) string {
    match p.Form {
    case BindPattern(name): return name
    case WildPattern(): return "_"
    case ConstructorPattern(name, args):
        if len(args) == 0 { return name }
        parts := []string{name}; for _, arg := range args { parts = append(parts,FormatPattern(arg)) }
        return "(" + strings.Join(parts," ") + ")"
    case ListPattern(items):
        parts := make([]string,len(items)); for i, item := range items { parts[i] = FormatPattern(item) }
        return "[" + strings.Join(parts,", ") + "]"
    case ConsPattern(head, tail): return "(" + FormatPattern(head) + " : " + FormatPattern(tail) + ")"
    case LiteralPattern(e): return FormatExpression(e)
    }
}

func FormatType(t *Type) string {
    match t.Form {
    case NamedType(name): return name
    case ListType(element): return "[" + FormatType(element) + "]"
    case AppliedType(constructor, arg): return "(" + FormatType(constructor) + " " + FormatType(arg) + ")"
    case ArrowType(arg, result): return "(" + FormatType(arg) + " -> " + FormatType(result) + ")"
    case RecordType(fields):
        parts := make([]string,len(fields)); for i, field := range fields { parts[i] = field.Name + " :: " + FormatType(field.Type) }
        return "{" + strings.Join(parts,", ") + "}"
    case RefinedType(base, rules):
        text := "(" + FormatType(base)
        for _, rule := range rules {
            text += " where " + FormatExpression(rule.Predicate)
            if rule.Code != "" { text += " @code " + quote(rule.Code) }
            if rule.Message != nil { text += " @message " + FormatExpression(rule.Message) }
            if rule.Steps != 0 { text += " @steps " + strconv.FormatUint(rule.Steps,10) }
        }
        return text + ")"
    }
}

// Format preserves declaration/equation order and emits a stable source form.
// Comments/formatting are not retained here; lossless native provenance lives
// in the native document layer, not this Haskell-like pretty-printer.
func Format(module *Module) string {
    var b strings.Builder
    if module.Package != "" { b.WriteString("package " + module.Package + "\n\n") }
    for _, entry := range module.Imports { b.WriteString("import " + quote(entry.Path) + "\n") }
    if len(module.Imports) > 0 { b.WriteByte('\n') }
    if module.Limits.Total!=0||module.Limits.Clause!=0{b.WriteString("@limits");if module.Limits.Total!=0{b.WriteString(" total "+strconv.FormatUint(module.Limits.Total,10))};if module.Limits.Clause!=0{b.WriteString(" clause "+strconv.FormatUint(module.Limits.Clause,10))};b.WriteString("\n\n")}
    if module.OpenAPI!=nil{b.WriteString(FormatOpenAPI(module.OpenAPI));b.WriteByte('\n')}
    for _, declaration := range module.Types {
        name := declaration.Name
        if len(declaration.Parameters) > 0 { name += " " + strings.Join(declaration.Parameters," ") }
        if declaration.Body != nil { b.WriteString("type " + name + " = " + FormatType(declaration.Body) + "\n\n"); continue }
        parts := make([]string,len(declaration.Variants))
        for i, variant := range declaration.Variants {
            parts[i] = variant.Name
            for _, arg := range variant.Arguments { parts[i] += " (" + FormatType(arg) + ")" }
        }
        b.WriteString("data " + name + " = " + strings.Join(parts," | ") + "\n\n")
    }
    for _, fn := range module.Functions {
        if fn.Signature != nil { b.WriteString(fn.Name + " :: " + FormatQualifiedType(fn.Constraints,fn.Signature) + "\n") }
        for _, equation := range fn.Equations {
            b.WriteString(fn.Name)
            for _, pattern := range equation.Patterns { b.WriteString(" " + FormatPattern(pattern)) }
            b.WriteString(" = " + FormatExpression(equation.Body) + "\n")
        }
        b.WriteByte('\n')
    }
    if module.ReleasePolicy != nil {
        policy, err := FormatReleasePolicyJSON(module.ReleasePolicy)
        if err != nil { panic(err) }
        b.WriteString("\n@releasePolicy " + quote(string(policy)) + "\n")
    }
    return b.String()
}

// FormatQualifiedType renders a signature context without changing the type.
// One constraint uses the compact form; multiple constraints are parenthesized.
func FormatQualifiedType(constraints []CapabilityConstraint,signature *Type)string {
    if len(constraints)==0{return FormatType(signature)}
    parts:=make([]string,len(constraints));for i,item:=range constraints{parts[i]=item.Capability+" "+item.Variable}
    prefix:=strings.Join(parts,", ");if len(parts)>1{prefix="("+prefix+")"}
    return prefix+" => "+FormatType(signature)
}
