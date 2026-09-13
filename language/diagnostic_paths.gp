package language

import "strings"

const affectedPathWorkLimit=1000000
const affectedPathUnitLimit=1<<20

type affectedPathBudget struct{work,units,maxWork,maxUnits int;exhausted bool}
func (b *affectedPathBudget)takeWork(count int)bool{if count<0||count>b.maxWork-b.work{b.exhausted=true;return false};b.work+=count;return true}
func (b *affectedPathBudget)takeUnits(count int)bool{if count<0||count>b.maxUnits-b.units{b.exhausted=true;return false};b.units+=count;return true}
type affectedPathFrame struct{expression *Expr;rootVisible bool}

// AffectedPaths returns the statically visible payload paths referenced by one
// where-clause predicate. It follows only projection chains rooted directly at
// the clause's `it`; named functions and local aliases are deliberately not
// expanded. When extraction exceeds its fixed work/output bounds or finds no
// narrower dependency, the enclosing path remains the conservative answer.
func AffectedPaths(predicate *Expr,enclosing string)[]string{return affectedPathsWithLimits(predicate,enclosing,affectedPathWorkLimit,affectedPathUnitLimit)}

func affectedPathsWithLimits(predicate *Expr,enclosing string,maxWork,maxUnits int)[]string{
    budget:=&affectedPathBudget{maxWork:maxWork,maxUnits:maxUnits};relative:=affectedRelativePaths(predicate,budget)
    if budget.exhausted||len(relative)==0{return []string{enclosing}}
    return prefixAffectedPathsWithBudget(relative,enclosing,budget)
}

func prefixAffectedPaths(relative []string,enclosing string)[]string{return prefixAffectedPathsWithLimits(relative,enclosing,affectedPathWorkLimit,affectedPathUnitLimit)}
func prefixAffectedPathsWithLimits(relative []string,enclosing string,maxWork,maxUnits int)[]string{return prefixAffectedPathsWithBudget(relative,enclosing,&affectedPathBudget{maxWork:maxWork,maxUnits:maxUnits})}
func prefixAffectedPathsWithBudget(relative []string,enclosing string,budget *affectedPathBudget)[]string{
    fallback:=func()[]string{return []string{enclosing}};if len(relative)==0||budget==nil||!budget.takeWork(len(relative)){return fallback()}
    if len(enclosing)>0&&len(relative)>budget.maxUnits/len(enclosing){budget.exhausted=true;return fallback()};if !budget.takeUnits(len(enclosing)*len(relative)){return fallback()}
    for _,path:=range relative{if !budget.takeUnits(len(path)){return fallback()}}
    result:=make([]string,len(relative));for i,path:=range relative{result[i]=enclosing+path};return result
}

func affectedRelativePaths(predicate *Expr,budget *affectedPathBudget)[]string{
    work:=[]affectedPathFrame{};queued:=map[affectedPathFrame]bool{};relative:=[]string{};seen:=map[string]bool{}
    push:=func(expression *Expr,visible bool){current:=affectedPathFrame{expression,visible};if expression==nil||queued[current]||!budget.takeWork(1){return};queued[current]=true;work=append(work,current)}
    add:=func(path string){if !seen[path]{seen[path]=true;relative=append(relative,path)}}
    push(predicate,true)
    for len(work)>0&&!budget.exhausted{
        current:=work[len(work)-1];work=work[:len(work)-1]
        if current.rootVisible{if path,ok:=directAffectedPath(current.expression,budget);ok{add(path);continue}}
        match current.expression.Form{
        case NumberLiteral(_):
        case TextLiteral(_):
        case BoolLiteral(_):
        case Variable(_):
        case Project(record,_):push(record,current.rootVisible)
        case Unary(_,operand):push(operand,current.rootVisible)
        case Binary(_,left,right):push(right,current.rootVisible);push(left,current.rootVisible)
        case Apply(function,argument):push(argument,current.rootVisible);push(function,current.rootVisible)
        case Conditional(condition,yes,no):push(no,current.rootVisible);push(yes,current.rootVisible);push(condition,current.rootVisible)
        case Let(name,_,bound,body):push(body,current.rootVisible&&name!="it");push(bound,current.rootVisible)
        case ListLiteral(items):for i:=len(items)-1;i>=0;i--{push(items[i],current.rootVisible)}
        case RecordLiteral(fields):for i:=len(fields)-1;i>=0;i--{push(fields[i].Value,current.rootVisible)}
        case MapLiteral(entries):for i:=len(entries)-1;i>=0;i--{push(entries[i].Value,current.rootVisible)}
        case Case(subject,arms):
            for i:=len(arms)-1;i>=0;i--{binds:=diagnosticPatternBindsIt(arms[i].Pattern,budget);push(arms[i].Body,current.rootVisible&&!binds)}
            push(subject,current.rootVisible)
        }
    }
    return relative
}

func directAffectedPath(expression *Expr,budget *affectedPathBudget)(string,bool){
    fields:=[]string{};current:=expression;seen:=map[*Expr]bool{}
    for current!=nil{
        if seen[current]||!budget.takeWork(1){return "",false};seen[current]=true
        match current.Form{
        case Project(record,field):if !budget.takeUnits(len(field)){return "",false};fields=append(fields,field);current=record
        case Variable(name):
            if name!="it"{return "",false}
            size:=0;for i:=len(fields)-1;i>=0;i--{next:=1+len(fields[i]);for j:=0;j<len(fields[i]);j++{if fields[i][j]=='~'||fields[i][j]=='/'{next++}};if !budget.takeUnits(next){return "",false};size+=next}
            var path strings.Builder;path.Grow(size);for i:=len(fields)-1;i>=0;i--{path.WriteByte('/');for j:=0;j<len(fields[i]);j++{switch fields[i][j]{case '~':path.WriteString("~0");case '/':path.WriteString("~1");default:path.WriteByte(fields[i][j])}}};return path.String(),true
        case _:return "",false
        }
    }
    return "",false
}

func diagnosticPatternBindsIt(pattern *Pattern,budget *affectedPathBudget)bool{
    work:=[]*Pattern{};seen:=map[*Pattern]bool{};push:=func(item *Pattern){if item==nil||seen[item]||!budget.takeWork(1){return};seen[item]=true;work=append(work,item)};push(pattern)
    for len(work)>0&&!budget.exhausted{current:=work[len(work)-1];work=work[:len(work)-1];match current.Form{
    case BindPattern(name):if name=="it"{return true}
    case ConstructorPattern(_,arguments):for _,argument:=range arguments{push(argument)}
    case ListPattern(items):for _,item:=range items{push(item)}
    case ConsPattern(head,tail):push(head);push(tail)
    case WildPattern():
    case LiteralPattern(_):
    }}
    return false
}
