package language

func syntaxResource(at Span, message string) { panic(&Error{Code:"language.limit",At:at,Message:message}) }
func guardDepth(at Span, depth int) { if depth > 512 { syntaxResource(at,"syntax tree exceeds the nesting resource limit") } }

// Parsing can build a deep left-associated tree without deep parser recursion.
// Bound the resulting tree as well, before checking or formatting traverses it.
func guardExpression(e *Expr, depth int) {
    guardDepth(e.At,depth)
    match e.Form {
    case NumberLiteral(_):
    case TextLiteral(_):
    case BoolLiteral(_):
    case Variable(_):
    case ListLiteral(items): for _, item := range items { guardExpression(item,depth+1) }
    case RecordLiteral(fields): for _, field := range fields { guardExpression(field.Value,depth+1) }
    case Apply(fn, arg): guardExpression(fn,depth+1); guardExpression(arg,depth+1)
    case Project(record, _): guardExpression(record,depth+1)
    case Unary(_, operand): guardExpression(operand,depth+1)
    case Binary(_, left, right): guardExpression(left,depth+1); guardExpression(right,depth+1)
    case Conditional(condition, yes, no): guardExpression(condition,depth+1); guardExpression(yes,depth+1); guardExpression(no,depth+1)
    case Let(_, annotation, bound, body): if annotation != nil { guardType(annotation,depth+1) }; guardExpression(bound,depth+1); guardExpression(body,depth+1)
    case Case(subject, arms):
        guardExpression(subject,depth+1)
        for _, arm := range arms { guardPattern(arm.Pattern,depth+1); guardExpression(arm.Body,depth+1) }
    }
}
func guardType(t *Type, depth int) {
    guardDepth(t.At,depth)
    match t.Form {
    case NamedType(_):
    case ListType(element): guardType(element,depth+1)
    case AppliedType(constructor, arg): guardType(constructor,depth+1); guardType(arg,depth+1)
    case ArrowType(arg, result): guardType(arg,depth+1); guardType(result,depth+1)
    case RecordType(fields): for _, field := range fields { guardType(field.Type,depth+1) }
    case RefinedType(parent, rules):
        guardType(parent,depth+1)
        for _, rule := range rules { guardExpression(rule.Predicate,depth+1); if rule.Message != nil { guardExpression(rule.Message,depth+1) } }
    }
}
func guardPattern(pattern *Pattern, depth int) {
    guardDepth(pattern.At,depth)
    match pattern.Form {
    case BindPattern(_):
    case WildPattern():
    case ConstructorPattern(_, args): for _, arg := range args { guardPattern(arg,depth+1) }
    case ListPattern(items): for _, item := range items { guardPattern(item,depth+1) }
    case ConsPattern(head, tail): guardPattern(head,depth+1); guardPattern(tail,depth+1)
    case LiteralPattern(e): guardExpression(e,depth+1)
    }
}
func guardModule(module *Module) {
    for _, declaration := range module.Types {
        if declaration.Body != nil { guardType(declaration.Body,0) }
        for _, variant := range declaration.Variants { for _, arg := range variant.Arguments { guardType(arg,0) } }
    }
    for _, fn := range module.Functions {
        if fn.Signature != nil { guardType(fn.Signature,0) }
        for _, equation := range fn.Equations {
            for _, pattern := range equation.Patterns { guardPattern(pattern,0) }
            guardExpression(equation.Body,0)
        }
    }
}
