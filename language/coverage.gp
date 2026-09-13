package language

// Coverage specializes a pattern matrix by each constructor in a finite family.
// For open domains (integers, strings, polymorphic values), only a wildcard or
// binder closes coverage. Nested constructor fields are checked, not just tags.
type coveragePattern struct { tag string; arguments []*coveragePattern }
type coverageConstructor struct { tag string; arguments []*term }
func wild() *coveragePattern { return &coveragePattern{} }

func (c *checker) pattern(pattern *Pattern, expected *term, env map[string]*term, seen map[string]bool) *coveragePattern {
    match pattern.Form {
    case WildPattern(): return wild()
    case BindPattern(name):
        if seen[name] { typeError(pattern.At,"variable is bound twice in the same pattern row") }
        seen[name] = true; env[name] = expected; return wild()
    case LiteralPattern(expression):
        actual := c.expression(expression,env); c.unify(expected,actual,expression.At)
        match expression.Form {
        case BoolLiteral(b): if b { return &coveragePattern{tag:"True"} }; return &coveragePattern{tag:"False"}
        case _: return &coveragePattern{tag:"literal:"+FormatExpression(expression)}
        }
    case ListPattern(elements):
        item := c.fresh(false); c.unify(expected,base("[]",item),pattern.At)
        patterns := make([]*coveragePattern,len(elements))
        for i, element := range elements { patterns[i] = c.pattern(element,item,env,seen) }
        tail := &coveragePattern{tag:"[]"}
        for i := len(patterns)-1; i >= 0; i-- { tail = &coveragePattern{tag:":",arguments:[]*coveragePattern{patterns[i],tail}} }
        return tail
    case ConsPattern(head, tail):
        item := c.fresh(false); c.unify(expected,base("[]",item),pattern.At)
        return &coveragePattern{tag:":",arguments:[]*coveragePattern{c.pattern(head,item,env,seen),c.pattern(tail,expected,env,seen)}}
    case ConstructorPattern(name, arguments):
        if _, ok := c.constructors[name]; !ok { typeError(pattern.At,"unknown pattern constructor " + name) }
        signature := c.function(name,pattern.At)
        childTypes := []*term{}
        for signature.name == "->" { childTypes = append(childTypes,signature.args[0]); signature = signature.args[1] }
        c.unify(expected,signature,pattern.At)
        if len(childTypes) != len(arguments) { typeError(pattern.At,"wrong number of constructor pattern arguments") }
        result := &coveragePattern{tag:name}
        for i, argument := range arguments { result.arguments = append(result.arguments,c.pattern(argument,childTypes[i],env,seen)) }
        return result
    }
}

func (c *checker) family(typ *term) []coverageConstructor {
    typ = c.prune(typ)
    switch typ.name {
    case "Bool": return []coverageConstructor{{tag:"True"},{tag:"False"}}
    case "[]": return []coverageConstructor{{tag:"[]"},{tag:":",arguments:[]*term{typ.args[0],typ}}}
    }
    names := []string{}
    switch typ.name {
    case "Maybe": names = []string{"Nothing","Just"}
    case "Nullable": names = []string{"Null","NonNull"}
    case "Result": names = []string{"Err","Ok"}
    case "JSON":for _,item:=range jsonConstructorSpecs(){names=append(names,item.name)}
    default:
        if declaration, ok := c.declarations[typ.name]; ok {
            for _, variant := range declaration.Variants { names = append(names,variant.Name) }
        }
    }
    result := []coverageConstructor{}
    for _, name := range names {
        constructor := c.constructors[name]
        variables := make(map[string]*term)
        for i, parameter := range constructor.parameters { variables[parameter] = typ.args[i] }
        arguments := []*term{}
        for _, arg := range constructor.arguments { arguments = append(arguments,c.typ(arg,variables,false,false)) }
        result = append(result,coverageConstructor{tag:name,arguments:arguments})
    }
    return result
}

func (c *checker) covered(rows [][]*coveragePattern, types []*term, depth int) bool {
    c.coverageWork++
    if c.coverageWork > 1000000 { panic(&Error{Code:"language.limit",Message:"pattern coverage analysis exhausted its deterministic work budget"}) }
    if len(rows) == 0 { return false }
    if len(types) == 0 { return true }
    for _, row := range rows {
        allWild := true
        for _, pattern := range row { if pattern.tag != "" { allWild = false; break } }
        if allWild { return true }
    }
    if depth > 256 { panic(&Error{Code:"language.limit",Message:"pattern coverage analysis exceeded its nesting budget"}) }
    family := c.family(types[0])
    if len(family) == 0 {
        defaults := [][]*coveragePattern{}
        for _, row := range rows { if row[0].tag == "" { defaults = append(defaults,row[1:]) } }
        return c.covered(defaults,types[1:],depth+1)
    }
    for _, constructor := range family {
        specialized := [][]*coveragePattern{}
        for _, row := range rows {
            arguments := []*coveragePattern{}
            if row[0].tag == "" { for range constructor.arguments { arguments = append(arguments,wild()) }
            } else if row[0].tag == constructor.tag { arguments = append(arguments,row[0].arguments...)
            } else { continue }
            specialized = append(specialized,append(arguments,row[1:]...))
        }
        constructorTypes := append(append([]*term(nil),constructor.arguments...),types[1:]...)
        if !c.covered(specialized,constructorTypes,depth+1) { return false }
    }
    return true
}
