package language

import (
    "sort"
    "strings"
    "unicode"
    "unicode/utf8"

    "goforge.dev/refine/pattern"
    "goforge.dev/refine/value"
)

func (e *evaluator) builtin(name string,args []evalValue,at Span) evalValue {
    if conversion,ok:=FixedIntegerConversion(name);ok{return e.fixedConversion(conversion,args[0],at)}
    if conversion,ok:=FixedFloatConversion(name);ok{return e.floatConversion(conversion,args[0],at)}
    switch name {
    case "toReal","toInteger","truncate","floor","ceiling","roundHalfEven":
        n,_:=number(args[0],at);size:=uint64(len(n.Show()));if size>0&&size>(^uint64(0)-1)/size{evalError(at,"evaluation.budget","numeric conversion cost exceeds evaluation resources")};e.step(size*size+1,at)
        switch name{
        case "toReal":return numberValue(n,"Real")
        case "toInteger":
            if !n.IsInteger(){text,_:=value.TextFromUTF8("conversion.fractional: exact integer conversion requires denominator one");return evalValue{form:EvalVariant("Err",[]evalValue{textValue(text)})}}
            return evalValue{form:EvalVariant("Ok",[]evalValue{numberValue(n,"Int")})}
        case "truncate":n=n.Truncate()
        case "floor":n=n.Floor()
        case "ceiling":n=n.Ceiling()
        case "roundHalfEven":n=n.RoundHalfEven()
        };return numberValue(n,"Int")
    case "civilSecondsUntil","siSecondsUntil":
        start,end:=timestampOf(args[0],at),timestampOf(args[1],at);size:=uint64(len(start.Raw()))+uint64(len(end.Raw()));if size>0&&size>(^uint64(0)-32)/size{evalError(at,"evaluation.budget","timestamp duration cost exceeds evaluation resources")};e.step(size*size+32,at)
        var duration value.Number;var err error;if name=="civilSecondsUntil"{duration,err=start.CivilSecondsUntil(end)}else{duration,err=start.SISecondsUntil(end)}
        if err!=nil{text,_:=value.TextFromUTF8(err.Error());return evalValue{form:EvalVariant("Err",[]evalValue{textValue(text)})}}
        return evalValue{form:EvalVariant("Ok",[]evalValue{numberValue(duration,"Real")})}
    case "not": return boolValue(!boolean(args[0],at))
    case "isInteger":n,_:=number(args[0],at);e.step(uint64(len(n.Show())),at);return boolValue(n.IsInteger())
    case "show":
        shown := e.show(args[0],at)
        e.step(uint64(len(shown)),at)
        text,err := value.TextFromUTF8(shown); if err != nil { evalError(at,"evaluation.show","value cannot be shown as text") }; return textValue(text)
    case "length":
        match args[0].form {
        case EvalText(text): return numberValue(value.Integer(int64(text.Length())),"Int")
        case EvalList(items): return numberValue(value.Integer(int64(len(items))),"Int")
        case _: evalError(at,"evaluation.type","length requires text or a list")
        }
    case "lookup","member":
        key:=textOf(args[0],at);entries:=mapEntriesOf(args[1],at);for _,entry:=range entries{e.step(uint64(key.Length()+entry.key.Length()+1),at);if entry.key.Equal(key){if name=="member"{return boolValue(true)};return evalValue{form:EvalVariant("Just",[]evalValue{entry.value})}}};if name=="member"{return boolValue(false)};return evalValue{form:EvalVariant("Nothing",nil)}
    case "keys":entries:=mapEntriesOf(args[0],at);e.step(uint64(len(entries)),at);items:=make([]evalValue,len(entries));for i,entry:=range entries{items[i]=textValue(entry.key)};return evalValue{form:EvalList(items)}
    case "values":entries:=mapEntriesOf(args[0],at);e.step(uint64(len(entries)),at);items:=make([]evalValue,len(entries));for i,entry:=range entries{items[i]=entry.value};return evalValue{form:EvalList(items)}
    case "size":return numberValue(value.Integer(int64(len(mapEntriesOf(args[0],at)))),"Int")
    case "insert":
        key:=textOf(args[0],at);source:=mapEntriesOf(args[2],at);found:=-1;for i,entry:=range source{e.step(uint64(key.Length()+entry.key.Length()+1),at);if found<0&&entry.key.Equal(key){found=i}};entries:=append([]evalMapEntry(nil),source...);if found>=0{entries[found].value=args[1]}else{entries=append(entries,evalMapEntry{key:key,value:args[1]})};return e.mapValue(entries,at)
    case "delete":
        key:=textOf(args[0],at);entries:=mapEntriesOf(args[1],at);remove:=-1;for i,entry:=range entries{e.step(uint64(key.Length()+entry.key.Length()+1),at);if remove<0&&entry.key.Equal(key){remove=i}};if remove<0{return e.mapValue(entries,at)};out:=make([]evalMapEntry,0,len(entries)-1);out=append(out,entries[:remove]...);out=append(out,entries[remove+1:]...);return e.mapValue(out,at)
    case "reverse":
        items := itemsOf(args[0],at); e.step(uint64(len(items)),at)
        result := make([]evalValue,len(items)); for i,item := range items { result[len(items)-1-i] = item }; return evalValue{form:EvalList(result)}
    case "map":
        items := itemsOf(args[1],at); e.step(uint64(len(items)),at)
        result := make([]evalValue,len(items)); for i,item := range items { result[i] = e.apply(args[0],item,at) }; return evalValue{form:EvalList(result)}
    case "filter":
        items := itemsOf(args[1],at); e.step(uint64(len(items)),at)
        result := make([]evalValue,0,len(items))
        for _,item := range items { if boolean(e.apply(args[0],item,at),at) { result = append(result,item) } }; return evalValue{form:EvalList(result)}
    case "mapValues","filterValues":
        entries:=mapEntriesOf(args[1],at);e.step(uint64(len(entries)),at);result:=make([]evalMapEntry,0,len(entries));for _,entry:=range entries{mapped:=e.apply(args[0],entry.value,at);if name=="mapValues"{result=append(result,evalMapEntry{key:entry.key,value:mapped})}else if boolean(mapped,at){result=append(result,entry)}};return e.mapValue(result,at)
    case "allValues","anyValues":
        entries:=mapEntriesOf(args[1],at);e.step(uint64(len(entries)),at);items:=make([]evalValue,len(entries));for i,entry:=range entries{items[i]=entry.value};mode:="all";if name=="anyValues"{mode="any"};return e.combine(mode,[]evalValue{args[0],evalValue{form:EvalList(items)}},at)
    case "foldl":
        result := args[1]
        for _,item := range itemsOf(args[2],at) { e.step(1,at); result = e.apply(e.apply(args[0],result,at),item,at) }; return result
    case "oneOf","elem":
        for _,item := range itemsOf(args[1],at) { if e.equal(args[0],item,at) { return boolValue(true) } }; return boolValue(false)
    case "unique":
        items := itemsOf(args[0],at)
        for i,item := range items { for j := 0; j < i; j++ { if e.equal(item,items[j],at) { return boolValue(false) } } }; return boolValue(true)
    case "all","any","satisfiesAll","satisfiesOnlyOneOf","satisfiesOneOf","satisfiesAtLeastOneOf":
        return e.combine(name,args,at)
    case "read": evalError(at,"evaluation.type","read requires an inferred target type")
    case "matches","search":
        compiled,err:=pattern.Compile(textOf(args[0],at),e.meter)
        if err!=nil {problem:=err.(*pattern.Error);evalError(at,problem.Code,problem.Message)}
        var mode pattern.Mode=pattern.Full();if name=="search"{mode=pattern.Search()}
        matched,err:=compiled.Match(textOf(args[1],at),mode,e.meter)
        if err!=nil {problem:=err.(*pattern.Error);evalError(at,problem.Code,problem.Message)}
        return boolValue(matched)
    }
    evalError(at,"evaluation.name","unsupported built-in function"); return evalValue{}
}

func (e *evaluator) attemptApply(fn,arg evalValue,at Span) (result evalValue,failure *evalFailure) {
    defer func(){ if caught := recover(); caught != nil { if explained,ok := caught.(*evalFailure); ok { failure = explained } else { panic(caught) } } }()
    result = e.apply(fn,arg,at); return
}

// Predicate errors are unknown, not false. A decisive result survives earlier
// unknowns: e.g. any [unknown, true] and all [unknown, false]. Iteration follows
// input order and stops once the result is conclusive under three-outcome logic.
func (e *evaluator) combine(name string,args []evalValue,at Span) evalValue {
    mode := "any"
    if name == "all" || name == "satisfiesAll" { mode = "all" }
    if name == "satisfiesOnlyOneOf" { mode = "one" }
    overValues := name == "all" || name == "any"
    var items []evalValue
    if overValues { items = itemsOf(args[1],at) } else { items = itemsOf(args[0],at) }
    yes := 0
    var unknown *evalFailure
    for _,item := range items {
        fn,arg := item,args[1]
        if overValues { fn,arg = args[0],item }
        result,failure := e.attemptApply(fn,arg,at)
        if failure != nil { if unknown == nil { unknown = failure }; continue }
        satisfied := boolean(result,at)
        if satisfied { yes++ }
        if mode == "all" && !satisfied { return boolValue(false) }
        if mode == "any" && satisfied { return boolValue(true) }
        if mode == "one" && yes > 1 { return boolValue(false) }
    }
    if unknown != nil { panic(unknown) }
    if mode == "all" { return boolValue(true) }
    if mode == "one" { return boolValue(yes == 1) }
    return boolValue(false)
}

// Canonical display is separate from native serde. Records sort identifiers;
// sequences and constructor arguments keep their order. Text escapes every
// non-ASCII UTF-16 code unit. Numbers use reduced exact fractions.
func (e *evaluator) show(v evalValue,at Span) string {
    e.enter(at); defer func(){e.depth--}()
    match v.form {
    case EvalNumber(n,_): e.step(uint64(len(n.Show())),at); return n.Show()
    case EvalText(text): e.step(uint64(text.Length()),at); return text.Show()
    case EvalTimestamp(timestamp):e.step(uint64(len(timestamp.Raw())),at);return timestamp.Show()
    case EvalBool(b): if b { return "True" }; return "False"
    case EvalList(items):
        e.step(uint64(len(items)),at)
        parts := make([]string,len(items)); for i,item := range items { parts[i] = e.show(item,at) }
        return "[" + strings.Join(parts,", ") + "]"
    case EvalRecord(fields):
        levels := uint64(1); for n := len(fields); n > 1; n >>= 1 { levels++ }
        e.step(uint64(len(fields))*levels,at)
        ordered := append([]evalField(nil),fields...); sort.Slice(ordered,func(i,j int) bool { return ordered[i].name < ordered[j].name })
        parts := make([]string,len(ordered)); for i,field := range ordered {
            e.step(uint64(len(field.name)),at)
            if !codecIdentifier(field.name,false){evalError(at,"evaluation.show","record field is not representable in the canonical value grammar")}
            parts[i] = field.name + " = " + e.show(field.value,at)
        }
        return "{" + strings.Join(parts,", ") + "}"
    case EvalMap(entries):
        e.step(uint64(len(entries)),at);parts:=make([]string,len(entries));for i,entry:=range entries{e.step(uint64(entry.key.Length()),at);parts[i]=entry.key.Show()+" = "+e.show(entry.value,at)};return "map {"+strings.Join(parts,", ")+"}"
    case EvalVariant(name,args):
        e.step(uint64(len(name)+len(args)),at)
        if !codecIdentifier(name,true){evalError(at,"evaluation.show","constructor is not representable in the canonical value grammar")}
        if len(args) == 0 { return name }
        parts := []string{name}; for _,arg := range args {
            shown:=e.show(arg,at)
            match arg.form{case EvalNumber(n,_):if strings.HasPrefix(n.Show(),"-") || strings.Contains(n.Show(),"/"){shown="("+shown+")"};case _:}
            parts = append(parts,shown)
        }; return "(" + strings.Join(parts," ") + ")"
    case EvalFunction(_,_,_): evalError(at,"evaluation.show","functions do not support canonical display")
    case EvalGuardedFunction(_,_,_,_):evalError(at,"evaluation.show","functions do not support canonical display")
    }
    return ""
}

func codecIdentifier(name string,constructor bool)bool {
    if name=="" || !utf8.ValidString(name) || reserved(name){return false}
    if constructor && (!uppercase(name) || name=="True" || name=="False"){return false}
    for i,r:=range name{if i==0{if !unicode.IsLetter(r) && r!='_'{return false}}else if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r!='_' && r!='\''{return false}}
    return true
}

// fromData is a structural transfer, not schema validation. The caller must
// apply the declared numeric types/refinements before executing predicates.
func (e *evaluator) fromData(data value.Data,at Span) evalValue {
    e.enter(at); defer func(){e.depth--}()
    match data.Kind() {
    case value.NumberData(): n,_ := data.Number();e.step(uint64(len(n.Show())),at);if n.IsInteger() { return numberValue(n,"Int") }; return numberValue(n,"Real")
    case value.TextData(): t,_ := data.Text(); return textValue(t)
    case value.BoolData(): b,_ := data.Boolean(); return boolValue(b)
    case value.ListData():
        e.step(uint64(data.Size()),at);items := data.Elements()
        result := make([]evalValue,len(items)); for i,item := range items { result[i] = e.fromData(item,at) }; return evalValue{form:EvalList(result)}
    case value.RecordData():
        e.step(uint64(data.Size()),at);fields := data.Fields()
        result := make([]evalField,len(fields)); for i,field := range fields {e.step(uint64(len(field.Name)),at);result[i] = evalField{name:field.Name,value:e.fromData(field.Value,at)} }; return evalValue{form:EvalRecord(result)}
    case value.MapData():
        e.step(uint64(data.Size()),at);entries:=data.Entries();result:=make([]evalMapEntry,len(entries));for i,entry:=range entries{e.step(uint64(entry.Key.Length()),at);result[i]=evalMapEntry{key:entry.Key,value:e.fromData(entry.Value,at)}};return e.mapValue(result,at)
    case value.VariantData():
        name,_ := data.Constructor();e.step(uint64(data.Size()+len(name)),at);args := data.Elements()
        result := make([]evalValue,len(args)); for i,arg := range args { result[i] = e.fromData(arg,at) }; return evalValue{form:EvalVariant(name,result)}
    }
}

func (e *evaluator) toData(v evalValue,at Span) value.Data {
    e.enter(at); defer func(){e.depth--}()
    match v.form {
    case EvalNumber(n,_): return value.OfNumber(n)
    case EvalText(t): return value.OfText(t)
    case EvalTimestamp(t):e.step(uint64(len(t.Raw())),at);text,_:=value.TextFromUTF8(t.Raw());return value.OfText(text)
    case EvalBool(b): return value.OfBool(b)
    case EvalList(items):
        e.step(uint64(len(items)),at)
        result := make([]value.Data,len(items)); for i,item := range items { result[i] = e.toData(item,at) }; return value.List(result)
    case EvalRecord(fields):
        e.step(uint64(len(fields)),at)
        result := make([]value.DataField,len(fields)); for i,field := range fields { result[i] = value.DataField{Name:field.name,Value:e.toData(field.value,at)} }
        data,err := value.Record(result); if err != nil { evalError(at,"evaluation.record","invalid runtime record") }; return data
    case EvalMap(entries):
        e.step(uint64(len(entries)),at);result:=make([]value.MapEntry,len(entries));for i,entry:=range entries{e.step(uint64(entry.key.Length()),at);result[i]=value.MapEntry{Key:entry.key,Value:e.toData(entry.value,at)}};data,err:=value.Map(result);if err!=nil{evalError(at,"evaluation.map","invalid runtime map")};return data
    case EvalVariant(name,args):
        e.step(uint64(len(args)),at)
        result := make([]value.Data,len(args)); for i,arg := range args { result[i] = e.toData(arg,at) }
        data,err := value.Variant(name,result); if err != nil { evalError(at,"evaluation.constructor","invalid runtime constructor") }; return data
    case EvalFunction(_,_,_): evalError(at,"evaluation.type","a function is not a serializable payload value")
    case EvalGuardedFunction(_,_,_,_):evalError(at,"evaluation.type","a function is not a serializable payload value")
    }
    return value.Data{}
}
