// Package explain derives English contract instructions from checked syntax.
// It does not execute predicates, simplify arbitrary functions, or claim that
// native schema keywords can enforce the additional rules.
package explain

import (
    "encoding/json"
    "fmt"
    "strings"

    "goforge.dev/refine/language"
)

type Instruction struct { ID string; English string }
type Rule struct {
    Owner string
    Location string // Syntax location, not a concrete runtime payload path.
    Code string // Empty means the runtime derives a code for each payload path.
    Offset int
    Predicate string
    Entry string
    Message string
    MessageEntry string
    Steps uint64
}
type Definition struct { Name string; Signature string; English string }
type Equation struct { Function string; Patterns []string; English string; Entry string }
type Document struct {
    definitions []Definition
    rules []Rule
    equations []Equation
    instructions []Instruction
}
func (d Document) Definitions()[]Definition{return append([]Definition(nil),d.definitions...)}
func (d Document) Rules()[]Rule{return append([]Rule(nil),d.rules...)}
func (d Document) Instructions()[]Instruction{return append([]Instruction(nil),d.instructions...)}
func (d Document) Equations()[]Equation{out:=append([]Equation(nil),d.equations...);for i:=range out{out[i].Patterns=append([]string(nil),out[i].Patterns...)};return out}
func (d Document) MarshalJSON()([]byte,error){return json.Marshal(struct{
    Definitions []Definition `json:"definitions"`
    Rules []Rule `json:"rules"`
    Equations []Equation `json:"equations"`
    Instructions []Instruction `json:"instructions"`
}{d.Definitions(),d.Rules(),d.Equations(),d.Instructions()})}

type builder struct { doc Document; functions map[string]bool; locals map[string]bool; next int; bytes int }
type limitError struct{}
func (limitError) Error()string{return "explain: explanation exceeds the 100,000-instruction or 16 MiB generation limit"}
func (b *builder) charge(n int){if n>16<<20-b.bytes{panic(limitError{})};b.bytes+=n}

// Generate describes every declaration, clause and function body, including
// recursive algorithms. References are not expanded, so recursive contracts
// produce finite documents. Only compiler-checked source is accepted.
func Generate(program *language.Program)(Document,error){return generate(program,nil)}

// GeneratePayload also includes anonymous constraints authored on a selected
// closed target outside the module, such as Box (Int where it > 0).
func GeneratePayload(target *language.PayloadType)(Document,error){
    if target==nil{return Document{},fmt.Errorf("explain: a checked payload type is required")}
    checked:=target.CheckedSyntax();if checked.Type==nil||checked.Module.Syntax==nil{return Document{},fmt.Errorf("explain: a checked payload type is required")}
    program,err:=language.Compile(checked.Module.Syntax.Source);if err!=nil{return Document{},err}
    return generate(program,checked.Type)
}

func generate(program *language.Program,payload *language.Type)(document Document,err error){
    defer func(){if caught:=recover();caught!=nil{if failure,ok:=caught.(limitError);ok{document=Document{};err=failure}else{panic(caught)}}}()
    if program==nil{return Document{},fmt.Errorf("explain: a checked program is required")}
    checked:=program.CheckedSyntax();module:=checked.Syntax
    b:=builder{functions:map[string]bool{},locals:map[string]bool{}}
    for _,fn:=range module.Functions{b.functions[fn.Name]=true}
    for _,decl:=range module.Types{
        name:=decl.Name;if len(decl.Parameters)>0{name+=" "+strings.Join(decl.Parameters," ")}
        if decl.Body!=nil{
            b.doc.definitions=append(b.doc.definitions,Definition{Name:name,Signature:language.FormatType(decl.Body),English:"A value of "+name+" has "+describeType(decl.Body)+". All constraints of referenced types still apply; naming a parent does not copy or weaken them."})
            b.typ(decl.Name,"value",decl.Body)
        }else{
            parts:=[]string{}
            for _,variant:=range decl.Variants{
                args:=[]string{};for i,arg:=range variant.Arguments{args=append(args,describeType(arg));b.typ(decl.Name,fmt.Sprintf("alternative %s argument %d",variant.Name,i+1),arg)}
                part:=variant.Name;if len(args)>0{part+=" carrying, in order, "+strings.Join(args,"; ")};parts=append(parts,part)
            }
            b.doc.definitions=append(b.doc.definitions,Definition{Name:name,English:"Exactly one tagged alternative: "+strings.Join(parts,"; or ")+". These are language alternatives; no wire discriminator is implied."})
        }
    }
    if payload!=nil{
        b.doc.definitions=append(b.doc.definitions,Definition{Name:"$payload",Signature:language.FormatType(payload),English:"The selected payload has "+describeType(payload)+"."})
        b.typ("$payload","value",payload)
    }
    for _,fn:=range module.Functions{
        b.locals=map[string]bool{}
        capabilities:=checked.FunctionCapabilities[fn.Name]
        capabilityEnglish:=""
        if len(capabilities)>0{parts:=[]string{};for _,item:=range capabilities{parts=append(parts,item.Capability+" for "+item.Variable)};capabilityEnglish=" Its effective statically required capabilities are "+strings.Join(parts,", ")+"."}
        b.doc.definitions=append(b.doc.definitions,Definition{Name:fn.Name,Signature:language.FormatQualifiedType(capabilities,fn.Signature),English:"A named function. Match its arguments against the following equations in source order and evaluate the first matching body in the pattern bindings. Recursive calls use the same rules and shared evaluation budget; termination is not promised."+capabilityEnglish})
        b.typ(fn.Name,"signature",fn.Signature)
        for _,eq:=range fn.Equations{
            patterns,words:=[]string{},[]string{}
            for _,pattern:=range eq.Patterns{patterns=append(patterns,language.FormatPattern(pattern));words=append(words,describePattern(pattern))}
            b.locals=map[string]bool{};for _,pattern:=range eq.Patterns{bindPattern(pattern,b.locals)}
            entry:=b.expr(fn.Name,eq.Body)
            b.doc.equations=append(b.doc.equations,Equation{Function:fn.Name,Patterns:patterns,English:strings.Join(words,"; then "),Entry:entry})
        }
    }
    for _,def:=range b.doc.definitions{b.charge(len(def.Name)+len(def.Signature)+len(def.English))}
    for _,rule:=range b.doc.rules{b.charge(len(rule.Owner)+len(rule.Location)+len(rule.Code)+len(rule.Predicate)+len(rule.Message))}
    for _,eq:=range b.doc.equations{b.charge(len(eq.Function)+len(eq.English))}
    return b.doc,nil
}

func describeType(t *language.Type)string{
    match t.Form{
    case language.NamedType(name):
        switch name{case "Int":return "an arbitrary-precision integer";case "Real":return "an exact rational number (rounding is never implicit)";case "Float32":return "a finite IEEE-754 binary32 value represented exactly (with no distinct signed-zero identity and no implicit rounding)";case "Float64":return "a finite IEEE-754 binary64 value represented exactly (with no distinct signed-zero identity and no implicit rounding)";case "String":return "text compared by exact Unicode sequence, with length measured in UTF-16 code units";case "Bool":return "a Boolean";case "Timestamp":return "an RFC 3339 timestamp retaining its original text";case "JSON":return "an immutable JSON value represented by one of JSONNull, JSONBoolean, JSONNumber, JSONString, JSONArray, or JSONObject; JSON numbers remain exact and JSON object keys are never normalized"}
        return "the declared type "+name
    case language.ListType(element):return "an ordered list whose elements each have "+describeType(element)
    case language.RecordType(fields):
        parts:=[]string{};for _,field:=range fields{parts=append(parts,field.Name+": "+describeType(field.Type))}
        return "a record with fields {"+strings.Join(parts,"; ")+"}; undeclared fields are permitted by the standalone language"
    case language.RefinedType(base,_):return describeType(base)+", subject to the separately listed where clauses"
    case language.ArrowType(arg,result):return "a function taking "+describeType(arg)+" and returning "+describeType(result)
    case language.AppliedType(constructor,arg):
        if name,args,ok:=appliedType(constructor,arg);ok&&name=="Map"&&len(args)==2{return "an immutable exact-string-keyed map whose values each have "+describeType(args[1])+"; entry order is not semantic and keys are never normalized"}
        match constructor.Form{
        case language.NamedType(name):
            if name=="Maybe"{return "an absent value (Nothing) or a present value (Just) with "+describeType(arg)+"; absence is not null"}
            if name=="Nullable"{return "explicit null (Null) or a non-null value (NonNull) with "+describeType(arg)+"; null is not absence"}
        case _:}
        return "the applied type "+language.FormatType(t)+" (substitute its arguments in the referenced definition)"
    }
}

func appliedType(constructor,arg *language.Type)(string,[]*language.Type,bool){root:=&language.Type{Form:language.AppliedType(constructor,arg)};args:=[]*language.Type{};for{match root.Form{case language.AppliedType(fn,item):args=append([]*language.Type{item},args...);root=fn;case language.NamedType(name):return name,args,true;case _:return "",nil,false}}}

func (b *builder) typ(owner,location string,t *language.Type){
    match t.Form{
    case language.NamedType(_):
    case language.ListType(element):b.typ(owner,location+" / each list element",element)
    case language.AppliedType(constructor,arg):b.typ(owner,location+" / type constructor",constructor);b.typ(owner,location+" / type argument",arg)
    case language.ArrowType(arg,result):b.typ(owner,location+" / function argument",arg);b.typ(owner,location+" / function result",result)
    case language.RecordType(fields):for _,field:=range fields{b.typ(owner,location+" / field "+field.Name,field.Type)}
    case language.RefinedType(base,rules):
        b.typ(owner,location,base)
        for _,rule:=range rules{
            old:=b.locals;b.locals=copyBindings(old);delete(b.locals,"it")
            item:=Rule{Owner:owner,Location:location,Code:rule.Code,Offset:rule.At.Start.Offset,Predicate:language.FormatExpression(rule.Predicate),Steps:rule.Steps}
            item.Entry=b.expr(owner,rule.Predicate)
            if rule.Message!=nil{item.Message=language.FormatExpression(rule.Message);item.MessageEntry=b.expr(owner,rule.Message)}
            b.doc.rules=append(b.doc.rules,item)
            b.locals=old
        }
    }
}

// Instructions form a demand-driven expression graph, NOT an eager sequential
// program. Conditional branches and &&/|| operands are only entered as specified.
func (b *builder) expr(owner string,e *language.Expr)string{
    b.next++;if b.next>100000{panic(limitError{})};id:=fmt.Sprintf("E%d",b.next);slot:=len(b.doc.instructions)
    b.doc.instructions=append(b.doc.instructions,Instruction{ID:id})
    child:=func(value *language.Expr)string{return b.expr(owner,value)}
    english:=""
    match e.Form{
    case language.NumberLiteral(text):english="Return the exact numeric literal "+text+"."
    case language.TextLiteral(raw):english="Return the text literal "+raw+" after decoding its language escapes, without normalization."
    case language.BoolLiteral(v):english=fmt.Sprintf("Return %t.",v)
    case language.Variable(name):
        if b.locals[name]{english="Use the lexically bound value "+name+"."}else if name=="it"{english="Return the current value at this refinement's location."}else if b.functions[name]{english="Refer to named function "+name+" and its equations below; do not evaluate a body until its arguments are supplied."}else if meaning,ok:=builtinMeaning(name);ok{english=meaning}else{english="Use the lexically bound value or declared constructor "+name+"."}
    case language.ListLiteral(items):
        parts:=[]string{};for _,item:=range items{parts=append(parts,child(item))};english="Evaluate ["+strings.Join(parts,", ")+"] from left to right and return the resulting ordered list."
    case language.RecordLiteral(fields):
        parts:=[]string{};for _,field:=range fields{parts=append(parts,field.Name+" from "+child(field.Value))};english="Evaluate and construct a new record with "+strings.Join(parts,"; ")+"."
    case language.MapLiteral(entries):
        parts:=[]string{};for _,entry:=range entries{parts=append(parts,entry.Key+" from "+child(entry.Value))};english="Evaluate and construct an immutable string-keyed map with "+strings.Join(parts,"; ")+". Entry order is not semantic; decoded UTF-16 keys are exact and are not normalized."
    case language.Project(record,field):english="Evaluate "+child(record)+", then select its field "+field+"."
    case language.Apply(fn,arg):english="Evaluate function "+child(fn)+", then argument "+child(arg)+", and apply the former to the latter. Arguments are eager even when unused; partial applications retain supplied arguments. Apply any declared argument/result refinements at their corresponding boundary."
    case language.Unary(op,operand):
        operation:="negate numerically";if op=="!"{operation="negate logically"};english="Evaluate "+child(operand)+", then "+operation+"; fixed-width overflow is an evaluation error."
    case language.Binary(op,left,right):
        a,c:=child(left),child(right)
        switch op{
        case "&&":english="Evaluate "+a+". If false, return false without evaluating "+c+"; if true, evaluate and return "+c+". An unhandled error in the left operand is indeterminate, not false."
        case "||":english="Evaluate "+a+". If true, return true without evaluating "+c+"; if false, evaluate and return "+c+". An unhandled error in the left operand is indeterminate, not false."
        default:english="Evaluate "+a+" and then "+c+"; "+binaryMeaning(op)+"."
        }
    case language.Conditional(condition,yes,no):english="Evaluate "+child(condition)+". If true, evaluate and return only "+child(yes)+"; otherwise evaluate and return only "+child(no)+"."
    case language.Let(name,annotation,bound,body):
        value:=child(bound);check:="";if annotation!=nil{check=" Check the value against "+language.FormatType(annotation)+", including its refinements.";b.typ(owner,"local binding "+name,annotation)}
        old:=b.locals;b.locals=copyBindings(old);b.locals[name]=true;next:=child(body);b.locals=old
        english="Evaluate "+value+"."+check+" Bind that value to "+name+" in the body, then evaluate and return "+next+"; the binding does not mutate an existing value."
    case language.Case(subject,arms):
        entry:=child(subject);parts:=[]string{}
        for i,arm:=range arms{old:=b.locals;b.locals=copyBindings(old);bindPattern(arm.Pattern,b.locals);entry:=child(arm.Body);b.locals=old;parts=append(parts,fmt.Sprintf("arm %d: %s, then evaluate %s",i+1,describePattern(arm.Pattern),entry))}
        english="Evaluate "+entry+" once. Try the following patterns in order, choosing only the first match and evaluating its body in the pattern bindings: "+strings.Join(parts,"; ")+"."
    }
    b.charge(len(id)+len(english));b.doc.instructions[slot].English=english
    return id
}

func copyBindings(input map[string]bool)map[string]bool{out:=make(map[string]bool,len(input));for key,v:=range input{out[key]=v};return out}
func bindPattern(p *language.Pattern,bindings map[string]bool){match p.Form{
case language.BindPattern(name):bindings[name]=true
case language.ConstructorPattern(_,args):for _,arg:=range args{bindPattern(arg,bindings)}
case language.ListPattern(items):for _,item:=range items{bindPattern(item,bindings)}
case language.ConsPattern(head,tail):bindPattern(head,bindings);bindPattern(tail,bindings)
case language.WildPattern():
case language.LiteralPattern(_):
}}

func binaryMeaning(op string)string{
    switch op{
    case "==":return "return whether the values are structurally equal (text has exact Unicode-sequence equality without normalization)"
    case "/=":return "return whether the values are not structurally equal"
    case "<":return "return whether the first is strictly less than the second"
    case "<=":return "return whether the first is less than or equal to the second"
    case ">":return "return whether the first is strictly greater than the second"
    case ">=":return "return whether the first is greater than or equal to the second"
    case "+":return "add the numbers exactly, rejecting fixed-width overflow"
    case "-":return "subtract the second number from the first exactly, rejecting fixed-width overflow"
    case "*":return "multiply the numbers exactly, rejecting fixed-width overflow"
    case "/":return "divide the first number by the second as an exact rational; division by zero is an evaluation error"
    case "%":return "return the integer remainder, using division truncated toward zero; a zero divisor is an evaluation error"
    case "++":return "concatenate the two texts or lists in order, without modifying either"
    case ":":return "prepend the first value to the second list, without modifying the list"
    }
    panic("checked expression contains an unknown binary operator")
}

func describePattern(p *language.Pattern)string{
    match p.Form{
    case language.BindPattern(name):return "accept any value and bind it as "+name
    case language.WildPattern():return "accept any value without binding it"
    case language.LiteralPattern(e):return "require equality with literal "+language.FormatExpression(e)
    case language.ConstructorPattern(name,args):parts:=[]string{};for _,arg:=range args{parts=append(parts,describePattern(arg))};return "require constructor "+name+" and match its arguments in order ["+strings.Join(parts,"; ")+"]"
    case language.ListPattern(items):parts:=[]string{};for _,item:=range items{parts=append(parts,describePattern(item))};return "require exactly "+fmt.Sprint(len(items))+" list elements and match them in order ["+strings.Join(parts,"; ")+"]"
    case language.ConsPattern(head,tail):return "require a nonempty list; for its first element, "+describePattern(head)+"; for its remaining list, "+describePattern(tail)
    }
}

// Markdown is deterministic and self-contained; code fences grow to contain
// arbitrary author text safely. It includes all algorithms, not just summaries.
func (d Document) Markdown()string{
    var out strings.Builder
    out.WriteString("# Additional contract requirements\n\nThese requirements supplement the ordinary schema; this document does not claim that the schema enforces them. Apply referenced definitions recursively. Each where clause is one diagnostic unit, even when it contains several Boolean operands.\n\n")
    out.WriteString("## Evaluation policy\n\nValues are immutable. Calculations do not change the payload. Integers are arbitrary precision by default; fractional arithmetic is exact. Text length counts UTF-16 code units, and equality performs no Unicode normalization. Timestamp ordering compares RFC 3339 instants. Ordinary calls evaluate arguments eagerly; conditional branches and Boolean short-circuit operators evaluate only the selected operands. Predicates cannot perform network or filesystem I/O.\n\nA false clause is invalid. An unhandled evaluation error or exhausted deterministic budget is indeterminate. A known violation keeps the aggregate invalid even when other checks are indeterminate, with diagnostics marked incomplete. Both invalid and indeterminate prevent normal construction, updates and serde. Caller limits may tighten but never relax schema limits. Custom-message failure preserves the original violation and uses the generated fallback. Instructions below are demand-driven: enter an instruction only when its caller requests it; do not execute the numbered list eagerly.\n\n")
    out.WriteString("## Definitions\n\n")
    for _,definition:=range d.definitions{out.WriteString(prose(definition.Name+": "+definition.English)+"\n\n");if definition.Signature!=""{out.WriteString(fence(definition.Signature))}}
    out.WriteString("## Separate where clauses\n\n")
    if len(d.rules)==0{out.WriteString("No where clauses are declared.\n\n")}
    for i,rule:=range d.rules{
        fmt.Fprintf(&out,"Clause %d — %s, %s. Evaluate %s with it bound to this value; require true.\n\n",i+1,prose(rule.Owner),prose(rule.Location),rule.Entry)
        out.WriteString(fence(rule.Predicate))
        if rule.Code!=""{out.WriteString("Author error code:\n\n"+fence(rule.Code))}else{out.WriteString("The runtime derives the error code from the clause and concrete payload path.\n\n")}
        if rule.Steps>0{fmt.Fprintf(&out,"Declared clause limit: %d logical steps (also constrained by enclosing and caller limits).\n\n",rule.Steps)}else{out.WriteString("Use the runtime's default clause limit, also constrained by enclosing and caller limits.\n\n")}
        if rule.Message!=""{out.WriteString("Author-defined failure message: evaluate "+rule.MessageEntry+" only when this clause fails. This wording supplements, and does not replace, the predicate algorithm.\n\n"+fence(rule.Message))}
    }
    out.WriteString("## Function equations\n\n")
    for _,eq:=range d.equations{out.WriteString(prose(eq.Function+": "+eq.English)+"; return "+eq.Entry+".\n\n")}
    out.WriteString("## Demand-driven algorithm instructions\n\n")
    for _,instruction:=range d.instructions{out.WriteString(instruction.ID+": "+prose(instruction.English)+"\n\n")}
    return out.String()
}

func fence(text string)string{delimiter:="```";for strings.Contains(text,delimiter){delimiter+="`"};return delimiter+"text\n"+text+"\n"+delimiter+"\n\n"}
func prose(text string)string{return strings.NewReplacer("&","&amp;","<","&lt;",">","&gt;","\\","\\\\","`","\\`","*","\\*","_","\\_","[","\\[","]","\\]","#","\\#","\n"," ","\r"," ").Replace(text)}
