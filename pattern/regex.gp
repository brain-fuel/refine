// Package pattern executes refinement regular expressions with deterministic
// work accounting. Native schema regex dialects remain a separate concern.
package pattern

import (
    "regexp/syntax"
    "unicode/utf16"

    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

type Error struct { Code string; Message string }
func (e *Error) Error()string{return e.Code+": "+e.Message}
type Regex struct { program *syntax.Prog }
type Mode enum { Full; Search }
func charge(meter *validation.Meter,cost uint64)error{if err:=meter.Step(cost);err!=nil{return &Error{Code:"regex.budget",Message:"regular expression step budget exhausted"}};return nil}

// Compile reuses the Go/RE2 syntax parser and program compiler, not its matcher.
// Invalid/unsupported dialect constructs fail explicitly. Parser diagnostics are
// sanitized because the pattern itself can originate in a private payload.
func Compile(source value.Text,meter *validation.Meter)(Regex,error) {
    size:=uint64(source.Length())
    if size>0 && size>(^uint64(0)-1)/size{return Regex{},&Error{Code:"regex.limit",Message:"pattern compilation cost is too large"}}
    if err:=charge(meter,size*size+1);err!=nil{return Regex{},err}
    raw,err:=source.UTF8();if err!=nil{return Regex{},&Error{Code:"regex.syntax",Message:"pattern requires Unicode scalar text; use a hexadecimal escape for a surrogate"}}
    parsed,err:=syntax.Parse(raw,syntax.Perl)
    if err!=nil{
        code:="regex.syntax";message:="invalid or unsupported regular expression"
        if problem,ok:=err.(*syntax.Error);ok{message=string(problem.Code);if problem.Code==syntax.ErrLarge||problem.Code==syntax.ErrNestingDepth{code="regex.limit"}}
        return Regex{},&Error{Code:code,Message:message}
    }
    bound,err:=expansion(parsed,meter,0);if err!=nil{return Regex{},err}
    if err:=charge(meter,bound);err!=nil{return Regex{},err}
    program,err:=syntax.Compile(parsed.Simplify())
    if err!=nil{return Regex{},&Error{Code:"regex.compile",Message:"regular expression could not be compiled"}}
    return Regex{program:program},nil
}

// Charge a conservative expanded-program bound before counted repetitions are
// expanded by the ecosystem compiler. Overflow/limits are unknown, not false.
func expansion(expr *syntax.Regexp,meter *validation.Meter,depth int)(uint64,error) {
    if depth>=512{return 0,&Error{Code:"regex.limit",Message:"regular expression nesting limit exceeded"}}
    if err:=charge(meter,1);err!=nil{return 0,err}
    total:=uint64(4+len(expr.Rune)+len(expr.Sub))
    for _,child:=range expr.Sub{
        weight,err:=expansion(child,meter,depth+1);if err!=nil{return 0,err}
        if total>^uint64(0)-weight{return 0,&Error{Code:"regex.limit",Message:"regular expression expansion is too large"}}
        total+=weight
    }
    if expr.Op==syntax.OpRepeat{
        count:=expr.Max;if count<0{count=expr.Min+1};count=max(count,1)
        if total>^uint64(0)/uint64(count){return 0,&Error{Code:"regex.limit",Message:"regular expression expansion is too large"}}
        total*=uint64(count)
    }
    return total,nil
}

// Match uses an iterative Thompson-style state set, not backtracking. Valid
// UTF-16 surrogate pairs form one code point; lone units retain their identity
// rather than being silently replaced. length in the DSL still counts units.
func (r Regex) Match(subject value.Text,mode Mode,meter *validation.Meter)(bool,error) {
    if r.program==nil{return false,&Error{Code:"regex.uncompiled",Message:"regular expression has not been compiled"}}
    if err:=charge(meter,uint64(subject.Length()+len(r.program.Inst)));err!=nil{return false,err}
    units:=subject.Units();points:=make([]rune,0,len(units))
    for i:=0;i<len(units);i++{
        unit:=units[i]
        if unit>=0xd800 && unit<=0xdbff && i+1<len(units) && units[i+1]>=0xdc00 && units[i+1]<=0xdfff{points=append(points,utf16.DecodeRune(rune(unit),rune(units[i+1])));i++}else{points=append(points,rune(unit))}
    }
    search:=false;match mode{case Full():case Search():search=true}
    visited:=make([]int,len(r.program.Inst));for i:=range visited{visited[i]=-1}
    seeds:=[]uint32{}
    for position:=0;position<=len(points);position++{
        if err:=charge(meter,1);err!=nil{return false,err}
        before,after:=rune(-1),rune(-1);if position>0{before=points[position-1]};if position<len(points){after=points[position]}
        if position==0||search{seeds=append(seeds,uint32(r.program.Start))}
        work:=seeds;next:=[]uint32{}
        for len(work)>0{
            if err:=charge(meter,1);err!=nil{return false,err}
            pc:=work[len(work)-1];work=work[:len(work)-1]
            if visited[pc]==position{continue};visited[pc]=position
            instruction:=&r.program.Inst[pc]
            switch instruction.Op{
            case syntax.InstAlt,syntax.InstAltMatch:work=append(work,instruction.Arg,instruction.Out)
            case syntax.InstCapture,syntax.InstNop:work=append(work,instruction.Out)
            case syntax.InstEmptyWidth:if instruction.MatchEmptyWidth(before,after){work=append(work,instruction.Out)}
            case syntax.InstMatch:if search||position==len(points){return true,nil}
            case syntax.InstFail:
            case syntax.InstRune,syntax.InstRune1,syntax.InstRuneAny,syntax.InstRuneAnyNotNL:
                if position==len(points){continue}
                cost:=uint64(1);for n:=len(instruction.Rune);n>1;n>>=1{cost++};if syntax.Flags(instruction.Arg)&syntax.FoldCase!=0{cost+=4}
                if err:=charge(meter,cost);err!=nil{return false,err}
                if instruction.MatchRune(after){next=append(next,instruction.Out)}
            default:return false,&Error{Code:"regex.program",Message:"unsupported regular expression instruction"}
            }
        }
        seeds=next
        if !search && len(seeds)==0{return false,nil}
    }
    return false,nil
}
