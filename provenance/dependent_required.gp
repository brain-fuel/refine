package provenance

import (
    "encoding/json"
    "sort"
    "unicode/utf8"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/value"
)

type dependentRequiredEntry struct{trigger value.Text;required []value.Text}

const dependentRequiredOrderingWorkLimit uint64=64<<20

// dependentRequiredConstraint is the JSON Schema discovery seam. Callers
// must invoke it only at an actual Schema Object position. The
// complete keyword is one atomic unit because its object members jointly form
// one native assertion.
func (s *JSONSchema)dependentRequiredConstraint(node schemajson.Node,path,key string,raw schemajson.Node)(bool,error){
    if key!="dependentRequired"{return false,nil};where:=pointer(path,key)
    predicate,projectable,err:=dependentRequiredProjection(raw,schemajson.DefaultNodes,maxJSONValueSourceBytes);if err!=nil{if problem,ok:=err.(*Error);ok&&problem.Pointer==""{problem.Pointer=where};return true,err};if !projectable||!jsonSchemaExplicitObject(node){return true,nil}
    err=s.addConstraint(path,where,key,"((Map String) JSON)",predicate,raw.Raw(),[]string{"member"});if valueLimit(err){return true,nil};return true,err
}

func jsonSchemaExplicitObject(node schemajson.Node)bool{
    typ,ok:=node.Lookup("type");if !ok{return false};if schemajson.KindName(typ.Kind())=="array"{if typ.ElementCount()!=1{return false};typ=typ.Elements()[0]};name,ok:=scalar(typ);return ok&&name=="object"
}

// OpenAPI 3.1/3.2 use the same JSON Schema keyword semantics. Only JSON
// resources participate here: YAML subtree spelling needs a separate exact
// lexical recovery proof and therefore remains opaque.
func (w *openAPIProvenanceWalker)discoverDependentRequiredAssertion(node openAPIProvenanceNode,dialect string)error{
    if w.openAPI30||!node.doc.isJSON{return nil};schema,err:=node.doc.json.At(node.pointer);if err!=nil{return err};raw,ok:=schema.Lookup("dependentRequired");if !ok{return nil};predicate,projectable,err:=dependentRequiredProjection(raw,schemajson.DefaultNodes,maxJSONValueSourceBytes);if problem,yes:=err.(*Error);yes&&problem.Pointer==""{problem.Pointer=node.doc.resource.URI+"#"+node.pointer+"/dependentRequired"};if err!=nil{return err};if !projectable||!jsonSchemaExplicitObject(schema){return nil};return w.add(node,"dependentRequired","((Map String) JSON)",predicate,raw.Raw(),dialect,[]string{"member"})
}

// dependentRequiredProjection validates and canonicalizes one complete native
// keyword. Limits are parameters so small deterministic tests can prove that
// count/source admission happens before large slices or ASTs are allocated.
func dependentRequiredProjection(raw schemajson.Node,workLimit,sourceLimit int)(string,bool,error){
    if workLimit<1||sourceLimit<32{return "",false,nil};if schemajson.KindName(raw.Kind())!="object"{return "",false,&Error{Code:"native.dependent_required",Message:"dependentRequired must be an object of string arrays"}}
    count:=raw.MemberCount();if count>workLimit-1||count>(sourceLimit-32)/64{return "",false,nil};work:=1+count;estimated:=32;ordering:=uint64(0);maximumTrigger:=0
    members:=raw.Members();entries:=make([]dependentRequiredEntry,len(members))
    for i,member:=range members{
        trigger,err:=member.Key.UTF8();if err!=nil{return "",false,nil};shown:=dependentRequiredTextSourceSize(trigger);if shown>sourceLimit-estimated-64{return "",false,nil};estimated+=shown+64;triggerText:=member.Key;if triggerText.Length()>maximumTrigger{maximumTrigger=triggerText.Length()}
        if schemajson.KindName(member.Value.Kind())!="array"{return "",false,&Error{Code:"native.dependent_required",Message:"each dependentRequired value must be an array of unique strings"}}
        amount:=member.Value.ElementCount();if amount>workLimit-work||amount>(sourceLimit-estimated)/32{return "",false,nil};work+=amount;items:=member.Value.Elements();required:=make([]value.Text,len(items));seen:=map[string]bool{};maximumRequired:=0
        for j,item:=range items{text,ok:=item.Text();if !ok{return "",false,&Error{Code:"native.dependent_required",Message:"each dependentRequired value must contain only strings"}};name,err:=text.UTF8();if err!=nil{return "",false,nil};if seen[name]{return "",false,&Error{Code:"native.dependent_required",Message:"each dependentRequired value must contain unique strings"}};seen[name]=true;shown:=dependentRequiredTextSourceSize(name);if shown>sourceLimit-estimated-32{return "",false,nil};estimated+=shown+32;required[j]=text;if text.Length()>maximumRequired{maximumRequired=text.Length()}}
        if !chargeDependentRequiredOrdering(len(required),maximumRequired,&ordering,dependentRequiredOrderingWorkLimit){return "",false,nil}
        sort.Slice(required,func(left,right int)bool{return required[left].Compare(required[right])<0});entries[i]=dependentRequiredEntry{trigger:triggerText,required:required}
    }
    if !chargeDependentRequiredOrdering(len(entries),maximumTrigger,&ordering,dependentRequiredOrderingWorkLimit){return "",false,nil}
    sort.Slice(entries,func(left,right int)bool{return entries[left].trigger.Compare(entries[right].trigger)<0});predicate:=dependentRequiredExpression(entries);formatted:=language.FormatExpression(predicate);if len(formatted)>sourceLimit{return "",false,nil};return formatted,true,nil
}

func dependentRequiredTextSourceSize(text string)int{size:=2;for len(text)>0{r,n:=utf8.DecodeRuneInString(text);if r=='"'||r=='\\'{size+=2}else if r>=0x20&&r<=0x7e{size++}else if r<=0xffff{size+=6}else{size+=12};text=text[n:]};return size}
func chargeDependentRequiredOrdering(count,maximum int,used *uint64,limit uint64)bool{if count==0{return true};if count<0||maximum<0||used==nil||*used>limit{return false};levels:=uint64(1);for width:=count;width>1;width>>=1{levels++};n,max:=uint64(count),uint64(maximum);if max>(^uint64(0)-1)/2{return false};per:=max*2+1;if n>(^uint64(0))/levels||n*levels>(^uint64(0))/per{return false};cost:=n*levels*per;if cost>(^uint64(0))-n{return false};cost+=n;if cost>limit-*used{return false};*used+=cost;return true}

func dependentRequiredExpression(entries []dependentRequiredEntry)*language.Expr{
    implications:=make([]*language.Expr,len(entries));for i,entry:=range entries{requirements:=make([]*language.Expr,len(entry.required));for j,name:=range entry.required{requirements[j]=dependentRequiredMember(name)};implications[i]=&language.Expr{Form:language.Conditional(dependentRequiredMember(entry.trigger),dependentRequiredAnd(requirements),&language.Expr{Form:language.BoolLiteral(true)})}}
    return dependentRequiredAnd(implications)
}

func dependentRequiredMember(name value.Text)*language.Expr{return &language.Expr{Form:language.Apply(&language.Expr{Form:language.Apply(&language.Expr{Form:language.Variable("member")},&language.Expr{Form:language.TextLiteral(name.Show())})},&language.Expr{Form:language.Variable("it")})}}
func dependentRequiredAnd(items []*language.Expr)*language.Expr{if len(items)==0{return &language.Expr{Form:language.BoolLiteral(true)}};if len(items)==1{return items[0]};middle:=len(items)/2;return &language.Expr{Form:language.Binary("&&",dependentRequiredAnd(items[:middle]),dependentRequiredAnd(items[middle:]))}}

// LowerDependentRequiredConstraint is the exact structural inverse for one
// edited canonical unit. It never executes arbitrary code or accepts a copied
// Constraint that tries to weaken the keyword-derived scope/builtin checks.
func LowerDependentRequiredConstraint(program *language.Program,constraint Constraint)(string,error){
    if constraint.Keyword!="dependentRequired"{return "",dependentRequiredInverseError(constraint,"unsupported dependentRequired provenance keyword")};if program==nil{return "",dependentRequiredInverseError(constraint,"a checked refinement program is required")};module:=program.Syntax();for _,fn:=range module.Functions{if fn.Name=="member"{return "",dependentRequiredInverseError(constraint,"canonical builtin member is shadowed")}}
    var declaration *language.TypeDecl;for i:=range module.Types{if module.Types[i].Name==constraint.Name{item:=module.Types[i];declaration=&item;break}};if declaration==nil||len(declaration.Parameters)!=0||declaration.Body==nil{return "",dependentRequiredInverseError(constraint,"canonical constraint declaration is absent or has parameters")};base:=declaration.Body;rules:=[]language.Where{};for base!=nil{advanced:=false;match base.Form{case language.RefinedType(inner,own):rules=append(rules,own...);base=inner;advanced=true;case _:};if !advanced{break}};if base==nil||language.FormatType(base)!="((Map String) JSON)"||len(rules)!=1{return "",dependentRequiredInverseError(constraint,"edited unit must retain Map String JSON and exactly one canonical clause")}
    entries,err:=lowerDependentRequiredExpression(rules[0].Predicate,constraint);if err!=nil{return "",err};if !dependentRequiredCanonicalOrder(entries){return "",dependentRequiredInverseError(constraint,"dependentRequired predicate is not in canonical UTF-16 order")};canonical:=dependentRequiredExpression(entries);if language.FormatExpression(canonical)!=language.FormatExpression(rules[0].Predicate){return "",dependentRequiredInverseError(constraint,"dependentRequired predicate is not in canonical balanced order")}
    object:=map[string][]string{};for _,entry:=range entries{trigger,err:=entry.trigger.UTF8();if err!=nil{return "",dependentRequiredInverseError(constraint,"dependentRequired trigger is not Unicode scalar text")};required:=make([]string,len(entry.required));for i,item:=range entry.required{name,err:=item.UTF8();if err!=nil{return "",dependentRequiredInverseError(constraint,"dependentRequired property is not Unicode scalar text")};required[i]=name};object[trigger]=required};encoded,err:=json.Marshal(object);if err!=nil{return "",dependentRequiredInverseError(constraint,"dependentRequired object cannot be encoded")};return string(encoded),nil
}

func lowerDependentRequiredExpression(expression *language.Expr,constraint Constraint)([]dependentRequiredEntry,error){
    leaves:=[]*language.Expr{};work:=0;if !dependentRequiredFlattenAnd(expression,&leaves,&work){return nil,dependentRequiredInverseError(constraint,"dependentRequired inverse exceeds the expression work limit")};if len(leaves)==1{match leaves[0].Form{case language.BoolLiteral(enabled):if enabled{return []dependentRequiredEntry{},nil};case _:}}
    sourceBytes:=32;entries:=make([]dependentRequiredEntry,len(leaves));seen:=map[string]bool{};for i,leaf:=range leaves{if sourceBytes>maxJSONValueSourceBytes-64{return nil,dependentRequiredInverseError(constraint,"dependentRequired inverse exceeds the source limit")};sourceBytes+=64;var condition,yes,no *language.Expr;match leaf.Form{case language.Conditional(test,then,otherwise):condition,yes,no=test,then,otherwise;case _:return nil,dependentRequiredInverseError(constraint,"dependentRequired must use canonical member implications")};if !dependentRequiredTrue(no){return nil,dependentRequiredInverseError(constraint,"dependentRequired implication else branch must be True")};trigger,ok:=dependentRequiredMemberName(condition);if !ok{return nil,dependentRequiredInverseError(constraint,"dependentRequired trigger must use member with a text literal")};triggerName,err:=trigger.UTF8();if err!=nil||seen[triggerName]{return nil,dependentRequiredInverseError(constraint,"dependentRequired triggers must be unique Unicode scalar text")};shown:=dependentRequiredTextSourceSize(triggerName);if shown>maxJSONValueSourceBytes-sourceBytes{return nil,dependentRequiredInverseError(constraint,"dependentRequired inverse exceeds the source limit")};sourceBytes+=shown;seen[triggerName]=true;requiredLeaves:=[]*language.Expr{};if !dependentRequiredFlattenAnd(yes,&requiredLeaves,&work){return nil,dependentRequiredInverseError(constraint,"dependentRequired inverse exceeds the expression work limit")};required:=[]value.Text{};if !(len(requiredLeaves)==1&&dependentRequiredTrue(requiredLeaves[0])){required=make([]value.Text,len(requiredLeaves));requiredSeen:=map[string]bool{};for j,item:=range requiredLeaves{name,ok:=dependentRequiredMemberName(item);if !ok{return nil,dependentRequiredInverseError(constraint,"dependentRequired properties must use member with text literals")};text,err:=name.UTF8();if err!=nil||requiredSeen[text]{return nil,dependentRequiredInverseError(constraint,"dependentRequired properties must be unique Unicode scalar text")};shown:=dependentRequiredTextSourceSize(text);if shown>maxJSONValueSourceBytes-sourceBytes-32{return nil,dependentRequiredInverseError(constraint,"dependentRequired inverse exceeds the source limit")};sourceBytes+=shown+32;requiredSeen[text]=true;required[j]=name}};entries[i]=dependentRequiredEntry{trigger:trigger,required:required}}
    return entries,nil
}

func dependentRequiredCanonicalOrder(entries []dependentRequiredEntry)bool{for i,entry:=range entries{if i>0&&entries[i-1].trigger.Compare(entry.trigger)>=0{return false};for j:=1;j<len(entry.required);j++{if entry.required[j-1].Compare(entry.required[j])>=0{return false}}};return true}

func dependentRequiredFlattenAnd(expression *language.Expr,out *[]*language.Expr,work *int)bool{stack:=[]*language.Expr{expression};for len(stack)>0{if *work>=schemajson.DefaultNodes{return false};*work=*work+1;last:=len(stack)-1;item:=stack[last];stack=stack[:last];matched:=false;match item.Form{case language.Binary(operator,left,right):if operator=="&&"{if len(stack)>schemajson.DefaultNodes-2{return false};stack=append(stack,right,left);matched=true};case _:};if !matched{if len(*out)>=schemajson.DefaultNodes{return false};*out=append(*out,item)}};return true}
func dependentRequiredTrue(expression *language.Expr)bool{match expression.Form{case language.BoolLiteral(value):return value;case _:};return false}
func dependentRequiredMemberName(expression *language.Expr)(value.Text,bool){quoted:="";match expression.Form{case language.Apply(call,subject):match subject.Form{case language.Variable(name):if name!="it"{return value.Text{},false};case _:return value.Text{},false};match call.Form{case language.Apply(fn,key):match fn.Form{case language.Variable(name):if name!="member"{return value.Text{},false};case _:return value.Text{},false};match key.Form{case language.TextLiteral(raw):quoted=raw;case _:return value.Text{},false};case _:return value.Text{},false};case _:return value.Text{},false};text,err:=value.ReadText(quoted);return text,err==nil}
func dependentRequiredInverseError(constraint Constraint,message string)*Error{return &Error{Code:"native.inverse",Pointer:constraint.Pointer,Message:message}}
