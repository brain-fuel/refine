package java

import (
    "fmt"
    "math/big"
    "sort"
    "strings"

    "goforge.dev/refine/language"
)

type propertyStrategy struct { source string; viable bool; references map[string]bool }
const propertyStrategySpecializationLimit = 512
func emptyPropertyStrategy()propertyStrategy{return propertyStrategy{references:make(map[string]bool)}}
func propertySource(source string)propertyStrategy{return propertyStrategy{source:source,viable:true,references:make(map[string]bool)}}
func propertyReferences(items ...propertyStrategy)map[string]bool{result:=make(map[string]bool);for _,item:=range items{for key:=range item.references{result[key]=true}};return result}
func copyPropertyStrings(source map[string]string)map[string]string{result:=make(map[string]string,len(source));for key,value:=range source{result[key]=value};return result}
func copyPropertyBools(source map[string]bool)map[string]bool{result:=make(map[string]bool,len(source));for key,value:=range source{result[key]=value};return result}

func (e *propertyEmitter) boundedGenerator(t *language.Type)(string,error){strategy,err:=e.propertyStrategy(t,map[string]string{},map[string]bool{});if err!=nil{return "",err};if !strategy.viable{return "",fmt.Errorf("payload has no finite generated value")};return strategy.source,nil}

func (e *propertyEmitter) propertyStrategy(t *language.Type,active map[string]string,cut map[string]bool)(propertyStrategy,error){
    if t==nil{return emptyPropertyStrategy(),fmt.Errorf("invalid nil payload type")}
    match t.Form{
    case language.RefinedType(base,rules):result,err:=e.propertyStrategy(base,active,cut);if err!=nil||!result.viable{return result,err};if !e.integerLike(base){return result,nil};values:=map[string]bool{"-1":true,"0":true,"1":true};for _,rule:=range rules{numericLiterals(rule.Predicate,values)};numbers:=make([]string,0,len(values));for n:=range values{numbers=append(numbers,n)};sortBigIntegers(numbers);parts:=[]string{};for _,n:=range numbers{parts=append(parts,"new java.math.BigInteger("+javaQuote(n)+")")};boundary:="org.jetbrains.jetCheck.Generator.sampledFrom("+strings.Join(parts,",")+").<Data>map(n -> new Data.Number(Rational.of(n),\"Int\"))";result.source="org.jetbrains.jetCheck.Generator.<Data>frequency(3,"+result.source+",2,"+boundary+")";return result,nil
    case language.NamedType(name):primitive,ok,err:=propertyPrimitive(name);if ok||err!=nil{return primitive,err};decl,found:=e.declarations[name];if !found{return emptyPropertyStrategy(),fmt.Errorf("unsupported payload type %s",name)};return e.propertyNominal(t,name,nil,decl,active,cut)
    case language.ListType(element):item,err:=e.propertyStrategy(element,active,cut);if err!=nil{return emptyPropertyStrategy(),err};if !item.viable{return propertySource("org.jetbrains.jetCheck.Generator.<Data>constant(new Data.Sequence(java.util.List.of()))"),nil};name:=e.fresh("xs");return propertyStrategy{source:"org.jetbrains.jetCheck.Generator.listsOf(org.jetbrains.jetCheck.IntDistribution.uniform(0,8),"+item.source+").<Data>map("+name+" -> new Data.Sequence("+name+"))",viable:true,references:propertyReferences(item)},nil
    case language.RecordType(fields):environment:=e.fresh("env");pieces:=[]string{};items:=[]propertyStrategy{};for _,field:=range fields{item,err:=e.propertyStrategy(field.Type,active,cut);if err!=nil{return emptyPropertyStrategy(),err};if !item.viable{return emptyPropertyStrategy(),nil};items=append(items,item);pieces=append(pieces,"new Data.Field("+javaQuote(field.Name)+","+environment+".generate("+item.source+"))")};return propertyStrategy{source:"org.jetbrains.jetCheck.Generator.<Data>from("+environment+" -> new Data.Struct(java.util.List.of("+strings.Join(pieces,",")+")))",viable:true,references:propertyReferences(items...)},nil
    case language.AppliedType(_,_):name,args:=applied(t);if name=="Maybe"||name=="Nullable"{if len(args)!=1{return emptyPropertyStrategy(),fmt.Errorf("%s requires one payload type",name)};item,err:=e.propertyStrategy(args[0],active,cut);if err!=nil{return emptyPropertyStrategy(),err};none,some:="Nothing","Just";if name=="Nullable"{none,some="Null","NonNull"};empty:="org.jetbrains.jetCheck.Generator.<Data>constant(new Data.Variant("+javaQuote(none)+",java.util.List.of()))";if !item.viable{return propertySource(empty),nil};variable:=e.fresh("value");return propertyStrategy{source:"org.jetbrains.jetCheck.Generator.<Data>anyOf("+empty+","+item.source+".<Data>map("+variable+" -> new Data.Variant("+javaQuote(some)+",java.util.List.of("+variable+"))))",viable:true,references:propertyReferences(item)},nil};if name=="Result"{if len(args)!=2{return emptyPropertyStrategy(),fmt.Errorf("Result requires two payload types")};return e.propertySum([]language.Variant{{Name:"Err",Arguments:[]*language.Type{args[0]}},{Name:"Ok",Arguments:[]*language.Type{args[1]}}},active,cut)};decl,found:=e.declarations[name];if !found||len(args)!=len(decl.Parameters)||len(args)==0{return emptyPropertyStrategy(),fmt.Errorf("unsupported applied payload type %s",name)};return e.propertyNominal(t,name,args,decl,active,cut)
    case language.ArrowType(_,_):return emptyPropertyStrategy(),fmt.Errorf("function payloads cannot be generated")
    }
    return emptyPropertyStrategy(),fmt.Errorf("unsupported payload generator")
}

func (e *propertyEmitter) propertyNominal(t *language.Type,name string,args []*language.Type,decl language.TypeDecl,active map[string]string,cut map[string]bool)(propertyStrategy,error){
    key:=language.FormatType(t);if self,recursive:=active[key];recursive{if cut[key]{return emptyPropertyStrategy(),nil};result:=propertySource(self);result.references[key]=true;return result,nil}
    if len(active)>=propertyStrategySpecializationLimit{return emptyPropertyStrategy(),fmt.Errorf("property strategy specialization limit of %d exceeded",propertyStrategySpecializationLimit)}
    next:=copyPropertyStrings(active);self:=e.fresh("self");next[key]=self;all,err:=e.propertyDeclaration(decl,args,next,cut);if err!=nil{return emptyPropertyStrategy(),err};if !all.viable{return all,nil};if !all.references[key]{return all,nil}
    baseCut:=copyPropertyBools(cut);baseCut[key]=true;base,err:=e.propertyDeclaration(decl,args,next,baseCut);if err!=nil{return emptyPropertyStrategy(),err};if !base.viable{return emptyPropertyStrategy(),fmt.Errorf("recursive type %s has no finite base strategy",key)}
    delete(all.references,key);delete(base.references,key);return propertyStrategy{source:"org.jetbrains.jetCheck.Generator.<Data>recursive("+self+" -> "+all.source+").withBase("+base.source+")",viable:true,references:propertyReferences(all,base)},nil
}

func (e *propertyEmitter) propertyDeclaration(decl language.TypeDecl,args []*language.Type,active map[string]string,cut map[string]bool)(propertyStrategy,error){
    bindings:=make(map[string]*language.Type,len(args));for i,parameter:=range decl.Parameters{bindings[parameter]=args[i]}
    if decl.Body!=nil{body:=decl.Body;if len(args)>0{closed,err:=language.SubstituteTypeBounded(body,bindings,language.DefaultSubstitutionNodes);if err!=nil{return emptyPropertyStrategy(),err};body=closed};return e.propertyStrategy(body,active,cut)}
    variants:=make([]language.Variant,len(decl.Variants));for i,variant:=range decl.Variants{variants[i]=variant;variants[i].Arguments=make([]*language.Type,len(variant.Arguments));for j,argument:=range variant.Arguments{if len(args)==0{variants[i].Arguments[j]=argument;continue};closed,err:=language.SubstituteTypeBounded(argument,bindings,language.DefaultSubstitutionNodes);if err!=nil{return emptyPropertyStrategy(),err};variants[i].Arguments[j]=closed}};return e.propertySum(variants,active,cut)
}

func (e *propertyEmitter) propertySum(variants []language.Variant,active map[string]string,cut map[string]bool)(propertyStrategy,error){sources:=[]string{};items:=[]propertyStrategy{};for _,variant:=range variants{environment:=e.fresh("env");pieces:=[]string{};arguments:=[]propertyStrategy{};viable:=true;for _,argument:=range variant.Arguments{item,err:=e.propertyStrategy(argument,active,cut);if err!=nil{return emptyPropertyStrategy(),err};if !item.viable{viable=false;break};arguments=append(arguments,item);pieces=append(pieces,environment+".generate("+item.source+")")};if !viable{continue};item:=propertyStrategy{source:"org.jetbrains.jetCheck.Generator.<Data>from("+environment+" -> new Data.Variant("+javaQuote(variant.Name)+",java.util.List.of("+strings.Join(pieces,",")+")))",viable:true,references:propertyReferences(arguments...)};items=append(items,item);sources=append(sources,item.source)};if len(sources)==0{return emptyPropertyStrategy(),nil};return propertyStrategy{source:"org.jetbrains.jetCheck.Generator.<Data>anyOf("+strings.Join(sources,",")+")",viable:true,references:propertyReferences(items...)},nil}

func sortBigIntegers(values []string){sort.Slice(values,func(i,j int)bool{left,_:=new(big.Int).SetString(values[i],10);right,_:=new(big.Int).SetString(values[j],10);return left.Cmp(right)<0})}

func propertyPrimitive(name string)(propertyStrategy,bool,error){
    if name!="Int"&&integerType(name){source,err:=fixedIntegerPropertyGenerator(name);return propertySource(source),true,err}
    switch name{
    case "Int":return propertySource(`org.jetbrains.jetCheck.Generator.integers(-10000,10000).<Data>map(n -> new Data.Number(Rational.of(n),"Int"))`),true,nil
    case "Real":return propertySource(`org.jetbrains.jetCheck.Generator.zipWith(org.jetbrains.jetCheck.Generator.integers(-10000,10000),org.jetbrains.jetCheck.Generator.integers(1,1000),(n,d) -> new Data.Number(new Rational(java.math.BigInteger.valueOf(n),java.math.BigInteger.valueOf(d)),"Real")).<Data>map(n -> n)`),true,nil
    case "Float32","Float64":return propertyFloat(name),true,nil
    case "String":return propertySource(`org.jetbrains.jetCheck.Generator.stringsOf(org.jetbrains.jetCheck.IntDistribution.uniform(0,24),org.jetbrains.jetCheck.Generator.asciiPrintableChars()).<Data>map(Data.Text::new)`),true,nil
    case "Bool":return propertySource(`org.jetbrains.jetCheck.Generator.booleans().<Data>map(Data.Bool::new)`),true,nil
    case "Timestamp":return propertySource(`org.jetbrains.jetCheck.Generator.sampledFrom("1970-01-01T00:00:00Z","2016-12-31T23:59:60Z","2024-02-29T23:59:59.123456789012345678+05:30","9999-12-31T23:59:59.999999999999Z").<Data>map(Data.Text::new)`),true,nil
    };return emptyPropertyStrategy(),false,nil
}

func propertyFloat(name string)propertyStrategy{precision,minExponent,maxExponent:=24,-126,127;if name=="Float64"{precision,minExponent,maxExponent=53,-1022,1023};subnormalExponent:=minExponent-(precision-1);denominator:=new(big.Int).Lsh(big.NewInt(1),uint(-subnormalExponent));halfDenominator:=new(big.Int).Lsh(new(big.Int).Set(denominator),1);maxSubnormal:=new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1),uint(precision-1)),big.NewInt(1));minNormalDenominator:=new(big.Int).Lsh(big.NewInt(1),uint(-minExponent));edge:=new(big.Int).Lsh(big.NewInt(1),uint(precision));maxSignificand:=new(big.Int).Sub(new(big.Int).Lsh(big.NewInt(1),uint(precision)),big.NewInt(1));maxFinite:=new(big.Int).Lsh(maxSignificand,uint(maxExponent-(precision-1)));overflowMidpoint:=new(big.Int).Add(new(big.Int).Set(maxFinite),new(big.Int).Lsh(big.NewInt(1),uint(maxExponent-precision)));candidates:=[]string{"0","1/"+denominator.String(),maxSubnormal.String()+"/"+denominator.String(),"1/"+minNormalDenominator.String(),new(big.Int).Sub(new(big.Int).Set(edge),big.NewInt(1)).String(),edge.String(),new(big.Int).Add(new(big.Int).Set(edge),big.NewInt(2)).String(),maxFinite.String(),"1/"+halfDenominator.String(),"1/3",new(big.Int).Add(new(big.Int).Set(edge),big.NewInt(1)).String(),new(big.Int).Add(new(big.Int).Set(edge),big.NewInt(3)).String(),overflowMidpoint.String(),new(big.Int).Add(new(big.Int).Set(overflowMidpoint),big.NewInt(1)).String()};parts:=[]string{};for _,raw:=range candidates{for _,signed:=range []string{raw,"-"+raw}{if signed=="-0"{continue};parts=append(parts,"new Data.Number(Rational.parse("+javaQuote(signed)+"),"+javaQuote(name)+")")}};random:=`org.jetbrains.jetCheck.Generator.zipWith(org.jetbrains.jetCheck.Generator.integers(-65536,65536),org.jetbrains.jetCheck.Generator.integers(0,20),(n,p) -> new Data.Number(new Rational(java.math.BigInteger.valueOf(n),java.math.BigInteger.ONE.shiftLeft(p)),"`+name+`")).<Data>map(n -> n)`;boundary:="org.jetbrains.jetCheck.Generator.<Data>sampledFrom("+strings.Join(parts,",")+")";return propertySource("org.jetbrains.jetCheck.Generator.<Data>frequency(3,"+random+",2,"+boundary+")")}
