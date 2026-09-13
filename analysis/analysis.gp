// Package analysis provides conservative proofs about checked payload contracts.
// It never guesses arbitrary predicate equivalence or treats unknown as success.
package analysis

import (
    "crypto/sha256"
    "fmt"
    "math/big"
    "strconv"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

type Outcome string
const ( Yes Outcome="yes"; No Outcome="no"; Unknown Outcome="unknown" )
type Finding struct { Outcome Outcome `json:"outcome"`; Code string `json:"code"`; Explanation string `json:"explanation"` }
type Compatibility struct {
    Fingerprint string `json:"fingerprint"`
    Backward Finding `json:"backward"` // Every old accepted payload is accepted by new.
    Forward Finding `json:"forward"` // Every new accepted payload is accepted by old.
}
type bound struct { value value.Number; strict bool }
type interval struct { lower *bound; upper *bound; integer bool; numeric bool; exact bool; empty bool; resourceLimited bool }
type inspector struct { types map[string]language.TypeDecl; active map[string]bool; expansionLimit uint64 }

// Satisfiable proves contradictions in numeric bounds or validates a concrete
// candidate. Failure to find a candidate is unknown, never unsatisfiable.
func Satisfiable(program *language.Program,root string,limits validation.Limits)(Finding,error){
    target,domain,err:=inspect(program,root,limits);if err!=nil{return Finding{},err}
    if domain.empty{return Finding{No,"analysis.empty","The recognized numeric constraints have an empty intersection; additional predicates cannot restore a value."},nil}
    for _,candidate:=range candidates(domain){if validation.StateName(target.ValidateData(value.OfNumber(candidate),limits).State())=="valid"{return Finding{Yes,"analysis.witness","A concrete candidate passed the complete checked contract. The candidate is not included in this report."},nil}}
    if domain.resourceLimited{return Finding{Unknown,"analysis.resource","Numeric proof discovery declined to expand a literal beyond its deterministic resource budget. This is not a proof of impossibility."},nil}
    return Finding{Unknown,"analysis.unknown","No satisfiability proof was found within the supported numeric-bound fragment and candidate validation budget. This is not a proof of impossibility."},nil
}

// Compare considers accepted payload sets, not Java API/ABI or native wire
// compatibility. Interval inclusion proofs concern logical constraints with
// sufficient resources; equal budgets do not imply equal execution costs.
// Native format, API context and publication policy require their own analysis.
func Compare(oldProgram *language.Program,oldRoot string,newProgram *language.Program,newRoot string,limits validation.Limits)(Compatibility,error){
    oldTarget,oldDomain,err:=inspect(oldProgram,oldRoot,limits);if err!=nil{return Compatibility{},err}
    newTarget,newDomain,err:=inspect(newProgram,newRoot,limits);if err!=nil{return Compatibility{},err}
    fingerprint:=fmt.Sprintf("%x",sha256.Sum256([]byte("refine.logical-inclusion.v1\x00"+oldProgram.Source()+"\x00"+oldRoot+"\x00"+newProgram.Source()+"\x00"+newRoot)))
    same:=oldProgram.Source()==newProgram.Source()&&oldTarget.Formatted()==newTarget.Formatted()
    return Compatibility{Fingerprint:fingerprint,Backward:includes(oldTarget,oldDomain,newTarget,newDomain,same,limits),Forward:includes(newTarget,newDomain,oldTarget,oldDomain,same,limits)},nil
}

func analysisExpansionLimit(program *language.Program,limits validation.Limits)uint64{
    declared:=program.SchemaLimits();total,clause:=declared.Total,declared.Clause
    if total==0{total=uint64(validation.DefaultTotalSteps)};if clause==0{clause=uint64(validation.DefaultClauseSteps)}
    if limits.Total!=0&&limits.Total<total{total=limits.Total};if limits.Clause!=0&&limits.Clause<clause{clause=limits.Clause}
    if total<clause{return total};return clause
}

func inspect(program *language.Program,root string,limits validation.Limits)(*language.PayloadType,interval,error){
    if program==nil{return nil,interval{},fmt.Errorf("analysis: a checked program is required")}
    target,err:=program.PayloadType(root);if err!=nil{return nil,interval{},err}
    i:=inspector{types:map[string]language.TypeDecl{},active:map[string]bool{},expansionLimit:analysisExpansionLimit(program,limits)}
    for _,decl:=range program.Syntax().Types{i.types[decl.Name]=decl}
    domain:=i.typ(target.Syntax(),0);domain.normalize()
    return target,domain,nil
}

func (i *inspector) typ(t *language.Type,depth int)interval{
    if depth>512{return interval{}}
    match t.Form{
    case language.RefinedType(base,rules):
        domain:=i.typ(base,depth+1)
        for _,rule:=range rules{i.predicate(&domain,rule.Predicate)}
        domain.normalize();return domain
    case language.NamedType(name):
        if name=="Int"||name=="Real"{return interval{integer:name=="Int",numeric:true,exact:true}}
        if decl,ok:=i.types[name];ok{
            if i.active[name]||decl.Body==nil||len(decl.Parameters)>0{return interval{}}
            i.active[name]=true;result:=i.typ(decl.Body,depth+1);delete(i.active,name);return result
        }
        signed:=true;digits:=""
        if strings.HasPrefix(name,"UInt"){signed=false;digits=strings.TrimPrefix(name,"UInt")}else if strings.HasPrefix(name,"Int"){digits=strings.TrimPrefix(name,"Int")}
        width,err:=strconv.Atoi(digits);if err!=nil||width<=0||width>65536{return interval{}}
        upper:=new(big.Int).Lsh(big.NewInt(1),uint(width));lower:=new(big.Int)
        if signed{upper.Rsh(upper,1);lower.Neg(upper)}
        upper.Sub(upper,big.NewInt(1));lo,_:=value.ParseNumber(lower.String());hi,_:=value.ParseNumber(upper.String())
        return interval{lower:&bound{value:lo},upper:&bound{value:hi},numeric:true,integer:true,exact:true}
    case _:return interval{}
    }
}

func current(e *language.Expr)bool{match e.Form{case language.Variable(name):return name=="it";case _:return false}}
func literal(e *language.Expr,limit uint64)(value.Number,bool,bool){
    match e.Form{
    case language.NumberLiteral(text):
        cost:=uint64(len(text));if cost>limit{return value.Number{},false,true}
        if pos:=strings.IndexAny(text,"eE");pos>=0{
            exponent:=strings.TrimPrefix(strings.TrimPrefix(text[pos+1:],"+"),"-");expanded,err:=strconv.ParseUint(exponent,10,64)
            if err!=nil||expanded>limit-cost{return value.Number{},false,true}
        }
        n,err:=value.ParseNumber(text);return n,err==nil,false
    case language.Unary(op,arg):if op!="-"{return value.Number{},false,false};n,ok,limited:=literal(arg,limit);return n.Negate(),ok,limited
    case _:return value.Number{},false,false
    }
}

func (i *inspector) predicate(d *interval,e *language.Expr){
    match e.Form{
    case language.BoolLiteral(v):if !v{d.empty=true}
    case language.Binary(op,left,right):
        if op=="&&"{i.predicate(d,left);i.predicate(d,right);return}
        number,ok,limited:=literal(right,i.expansionLimit)
        if limited{d.resourceLimited=true}
        if !current(left)||!ok{
            var otherLimited bool;number,ok,otherLimited=literal(left,i.expansionLimit);if otherLimited{d.resourceLimited=true};if !current(right)||!ok{d.exact=false;return}
            switch op{case "<":op=">";case "<=":op=">=";case ">":op="<";case ">=":op="<="}
        }
        if !d.numeric{d.exact=false;return}
        switch op{
        case "<","<=":d.tightenUpper(bound{value:number,strict:op=="<"})
        case ">",">=":d.tightenLower(bound{value:number,strict:op==">"})
        case "==":d.tightenLower(bound{value:number});d.tightenUpper(bound{value:number})
        default:d.exact=false
        }
    case _:d.exact=false
    }
}
func (d *interval) tightenLower(b bound){if d.lower==nil{d.lower=&b;return};cmp:=b.value.Compare(d.lower.value);if cmp>0||cmp==0&&b.strict{d.lower=&b}}
func (d *interval) tightenUpper(b bound){if d.upper==nil{d.upper=&b;return};cmp:=b.value.Compare(d.upper.value);if cmp<0||cmp==0&&b.strict{d.upper=&b}}
func (d *interval) normalize(){
    if d.integer{
        if d.lower!=nil&&d.lower.value.IsInteger()&&d.lower.strict{d.lower=&bound{value:d.lower.value.Add(value.Integer(1))}}
        if d.upper!=nil&&d.upper.value.IsInteger()&&d.upper.strict{d.upper=&bound{value:d.upper.value.Subtract(value.Integer(1))}}
    }
    if d.lower!=nil&&d.upper!=nil{cmp:=d.lower.value.Compare(d.upper.value);if cmp>0||cmp==0&&(d.lower.strict||d.upper.strict){d.empty=true}}
}
func within(d interval,n value.Number)bool{
    if !d.numeric||d.empty||d.integer&&!n.IsInteger(){return false}
    if d.lower!=nil{cmp:=n.Compare(d.lower.value);if cmp<0||cmp==0&&d.lower.strict{return false}}
    if d.upper!=nil{cmp:=n.Compare(d.upper.value);if cmp>0||cmp==0&&d.upper.strict{return false}}
    return true
}
func candidates(d interval)[]value.Number{
    if !d.numeric||d.empty{return nil}
    raw:=[]value.Number{value.Integer(0),value.Integer(1),value.Integer(-1)}
    half,_:=value.ParseNumber("1/2");if !d.integer{raw=append(raw,half,half.Negate())}
    for _,b:=range []*bound{d.lower,d.upper}{if b!=nil{raw=append(raw,b.value,b.value.Add(value.Integer(1)),b.value.Subtract(value.Integer(1)));if !d.integer{raw=append(raw,b.value.Add(half),b.value.Subtract(half))}}}
    if d.lower!=nil&&d.upper!=nil{mid,_:=d.lower.value.Add(d.upper.value).Divide(value.Integer(2));raw=append(raw,mid)}
    seen:=map[string]bool{};out:=[]value.Number{}
    for _,n:=range raw{if !seen[n.Show()]&&within(d,n){seen[n.Show()]=true;out=append(out,n)}}
    return out
}

func subset(a,b interval)bool{
    if a.empty{return true}
    if !a.numeric||!b.numeric||!b.exact||b.empty{return false}
    if b.integer&&!a.integer{
        if a.lower==nil||a.upper==nil||a.lower.strict||a.upper.strict||a.lower.value.Compare(a.upper.value)!=0||!a.lower.value.IsInteger(){return false}
    }
    if b.lower!=nil{
        if a.lower==nil{return false};cmp:=a.lower.value.Compare(b.lower.value);if cmp<0||cmp==0&&b.lower.strict&&!a.lower.strict{return false}
    }
    if b.upper!=nil{
        if a.upper==nil{return false};cmp:=a.upper.value.Compare(b.upper.value);if cmp>0||cmp==0&&b.upper.strict&&!a.upper.strict{return false}
    }
    return true
}

func includes(from *language.PayloadType,a interval,to *language.PayloadType,b interval,same bool,limits validation.Limits)Finding{
    if same{return Finding{Yes,"analysis.identical","The checked source and selected target are identical."}}
    if subset(a,b){return Finding{Yes,"analysis.inclusion","The source's recognized numeric superset lies entirely in the target's fully recognized numeric interval. This is logical payload inclusion, not a native-wire or Java-ABI guarantee."}}
    // Try points on both contracts' boundaries; validate both complete original
    // contracts before reporting a counterexample. Unknown is never rejection.
    points:=append(candidates(a),candidates(b)...)
    for _,n:=range points{
        data:=value.OfNumber(n)
        if validation.StateName(from.ValidateData(data,limits).State())!="valid"{continue}
        if validation.StateName(to.ValidateData(data,limits).State())=="invalid"{return Finding{No,"analysis.counterexample","A concrete candidate is valid under the source contract and invalid under the target. The candidate is not included in this report."}}
    }
    if a.resourceLimited||b.resourceLimited{return Finding{Unknown,"analysis.resource","Numeric proof discovery declined to expand a literal beyond its deterministic resource budget. This is not a compatibility proof or a counterexample."}}
    return Finding{Unknown,"analysis.unknown","The supported proof fragment and candidate checks do not establish inclusion or a counterexample. An enforced comparison must not treat this result as compatible."}
}
