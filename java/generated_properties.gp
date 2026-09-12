package java

import (
    "crypto/sha256"
    "fmt"
    "math/big"
    "path"
    "sort"
    "strings"

    "goforge.dev/refine/language"
    "goforge.dev/refine/value"
)

type PropertyOutcome uint8
const (ExampleValid PropertyOutcome=iota+1; ExampleInvalid; ExampleIndeterminate)
type PropertyNativeOutcome uint8
const (ExampleNativeValid PropertyNativeOutcome=iota; ExampleNativeInvalid)
type ReplayKind uint8
const (ReplayValid ReplayKind=iota+1; ReplayInvalid)
type PropertyTarget struct { Name string }
type PropertyExample struct { Target string; Value value.Data; Expected PropertyOutcome; NativeExpected PropertyNativeOutcome; DiagnosticCodes []string }
type PropertyReplay struct { Target string; Kind ReplayKind; DiagnosticCode string; SerializedData string }
type PropertyTestOptions struct { Targets []PropertyTarget; CaseCount int; AttemptBudget int; Seed int64; Examples []PropertyExample; Replays []PropertyReplay; JSONModule string; AvroSerde string; NativeJSONValidator string }

type propertyRule struct { target string; code string }
type propertyEmitter struct { declarations map[string]language.TypeDecl; visiting map[string]bool; next int }
func (e *propertyEmitter) fresh(prefix string)string{e.next++;return fmt.Sprintf("%s%d",prefix,e.next)}

func addNumericLiteral(text string,values map[string]bool){if strings.ContainsAny(text,"./eE"){return};n,ok:=new(big.Int).SetString(text,10);if !ok{return};values[n.String()]=true;values[new(big.Int).Sub(n,big.NewInt(1)).String()]=true;values[new(big.Int).Add(n,big.NewInt(1)).String()]=true}
func numericLiterals(expr *language.Expr,values map[string]bool){if expr==nil{return};match expr.Form{case language.NumberLiteral(text):addNumericLiteral(text,values);case language.Binary(_,left,right):numericLiterals(left,values);numericLiterals(right,values);case language.Unary(operator,operand):handled:=false;if operator=="-"{match operand.Form{case language.NumberLiteral(text):addNumericLiteral("-"+text,values);handled=true;case _:}};if !handled{numericLiterals(operand,values)};case language.Apply(fn,arg):numericLiterals(fn,values);numericLiterals(arg,values);case language.Project(record,_):numericLiterals(record,values);case language.Conditional(c,y,n):numericLiterals(c,values);numericLiterals(y,values);numericLiterals(n,values);case language.Let(_,_,v,b):numericLiterals(v,values);numericLiterals(b,values);case language.MapLiteral(entries):for _,entry:=range entries{numericLiterals(entry.Value,values)};case _:}}
func (e *propertyEmitter) integerLike(t *language.Type)bool{match t.Form{case language.RefinedType(base,_):return e.integerLike(base);case language.NamedType(name):if name=="Int"||strings.HasPrefix(name,"Int")||strings.HasPrefix(name,"UInt"){return true};if decl,ok:=e.declarations[name];ok&&decl.Body!=nil{return e.integerLike(decl.Body)};case _:};return false}

func generatedRuleCode(path string,rule language.Where)string{if rule.Code!=""{return rule.Code};sum:=sha256.Sum256([]byte(fmt.Sprintf("%s:%d:%s",path,rule.At.Start.Offset,language.FormatExpression(rule.Predicate))));return fmt.Sprintf("refine.%x",sum[:8])}
func (e *propertyEmitter) rules(target,path string,t *language.Type)([]propertyRule,error){
    result:=[]propertyRule{}
    match t.Form{
    case language.RefinedType(base,rules):
        nested,err:=e.rules(target,path,base);if err!=nil{return nil,err};result=append(result,nested...);for _,rule:=range rules{result=append(result,propertyRule{target:target,code:generatedRuleCode(path,rule)})}
    case language.RecordType(fields):for _,field:=range fields{nested,err:=e.rules(target,path+"/"+strings.ReplaceAll(strings.ReplaceAll(field.Name,"~","~0"),"/","~1"),field.Type);if err!=nil{return nil,err};result=append(result,nested...)}
    case language.ListType(element):nested,err:=e.rules(target,path+"/0",element);if err!=nil{return nil,err};result=append(result,nested...)
    case language.NamedType(name):if decl,ok:=e.declarations[name];ok{if e.visiting[name]{return result,nil};e.visiting[name]=true;if decl.Body!=nil{nested,err:=e.rules(target,path,decl.Body);if err!=nil{return nil,err};result=append(result,nested...)}else{for _,variant:=range decl.Variants{for index,argument:=range variant.Arguments{nested,err:=e.rules(target,fmt.Sprintf("%s/%d",path,index),argument);if err!=nil{return nil,err};result=append(result,nested...)}}};delete(e.visiting,name)}
    case language.AppliedType(_,_):name,args:=applied(t);if name=="Maybe"||name=="Nullable"{if len(args)!=1{return nil,fmt.Errorf("%s requires one payload type",name)};return e.rules(target,path,args[0])};if name=="Map"{if len(args)!=2{return nil,fmt.Errorf("Map requires String keys and one value type")};return e.rules(target,path+"/0",args[1])};if name=="Result"{if len(args)!=2{return nil,fmt.Errorf("Result requires two payload types")};for _,argument:=range args{nested,err:=e.rules(target,path+"/0",argument);if err!=nil{return nil,err};result=append(result,nested...)};return result,nil};decl,ok:=e.declarations[name];if !ok||len(args)!=len(decl.Parameters){return nil,fmt.Errorf("unsupported applied payload type %s",name)};if e.visiting[name]{return result,nil};e.visiting[name]=true;defer delete(e.visiting,name);bindings:=map[string]*language.Type{};for i,param:=range decl.Parameters{bindings[param]=args[i]};if decl.Body==nil{for _,variant:=range decl.Variants{for index,argument:=range variant.Arguments{closed,err:=language.SubstituteType(argument,bindings);if err!=nil{return nil,err};nested,err:=e.rules(target,fmt.Sprintf("%s/%d",path,index),closed);if err!=nil{return nil,err};result=append(result,nested...)}}}else{closed,err:=language.SubstituteType(decl.Body,bindings);if err!=nil{return nil,err};return e.rules(target,path,closed)}
    case language.ArrowType(_,_):return nil,fmt.Errorf("function payloads cannot be generated")
    }
    return result,nil
}

func (e *propertyEmitter) generator(t *language.Type)(string,error){
    match t.Form{
    case language.RefinedType(base,rules):raw,err:=e.generator(base);if err!=nil{return "",err};if !e.integerLike(base){return raw,nil};values:=map[string]bool{"-1":true,"0":true,"1":true};for _,rule:=range rules{numericLiterals(rule.Predicate,values)};numbers:=make([]string,0,len(values));for n:=range values{numbers=append(numbers,n)};sort.Slice(numbers,func(i,j int)bool{left,_:=new(big.Int).SetString(numbers[i],10);right,_:=new(big.Int).SetString(numbers[j],10);return left.Cmp(right)<0});parts:=[]string{};for _,n:=range numbers{parts=append(parts,"new java.math.BigInteger("+javaQuote(n)+")")};boundary:="org.jetbrains.jetCheck.Generator.sampledFrom("+strings.Join(parts,",")+").<Data>map(n -> new Data.Number(Rational.of(n),\"Int\"))";return "org.jetbrains.jetCheck.Generator.<Data>frequency(3,"+raw+",2,"+boundary+")",nil
    case language.NamedType(name):
        if name!="Int"&&integerType(name){return fixedIntegerPropertyGenerator(name)}
        switch name{case "Int":return `org.jetbrains.jetCheck.Generator.integers(-10000,10000).<Data>map(n -> new Data.Number(Rational.of(n),"Int"))`,nil;case "Real":return `org.jetbrains.jetCheck.Generator.zipWith(org.jetbrains.jetCheck.Generator.integers(-10000,10000),org.jetbrains.jetCheck.Generator.integers(1,1000),(n,d) -> new Data.Number(new Rational(java.math.BigInteger.valueOf(n),java.math.BigInteger.valueOf(d)),"Real")).<Data>map(n -> n)`,nil;case "Float32","Float64":return `org.jetbrains.jetCheck.Generator.zipWith(org.jetbrains.jetCheck.Generator.integers(-65536,65536),org.jetbrains.jetCheck.Generator.integers(0,20),(n,p) -> new Data.Number(new Rational(java.math.BigInteger.valueOf(n),java.math.BigInteger.ONE.shiftLeft(p)),"`+name+`")).<Data>map(n -> n)`,nil;case "String":return `org.jetbrains.jetCheck.Generator.stringsOf(org.jetbrains.jetCheck.IntDistribution.uniform(0,24),org.jetbrains.jetCheck.Generator.asciiPrintableChars()).<Data>map(Data.Text::new)`,nil;case "Bool":return `org.jetbrains.jetCheck.Generator.booleans().<Data>map(Data.Bool::new)`,nil}
        decl,ok:=e.declarations[name];if !ok{return "",fmt.Errorf("unsupported payload type %s",name)};if e.visiting[name]{return "",fmt.Errorf("recursive occurrence of %s is unsupported outside its direct union strategy",name)};if decl.Body==nil{e.visiting[name]=true;result,err:=e.unionGenerator(name,decl);delete(e.visiting,name);return result,err};e.visiting[name]=true;result,err:=e.generator(decl.Body);delete(e.visiting,name);return result,err
    case language.ListType(element):item,err:=e.generator(element);if err!=nil{return "",err};name:=e.fresh("xs");return "org.jetbrains.jetCheck.Generator.listsOf(org.jetbrains.jetCheck.IntDistribution.uniform(0,8),"+item+").<Data>map("+name+" -> new Data.Sequence("+name+"))",nil
    case language.RecordType(fields):
        environment:=e.fresh("env");pieces:=[]string{};for _,field:=range fields{item,err:=e.generator(field.Type);if err!=nil{return "",err};pieces=append(pieces,"new Data.Field("+javaQuote(field.Name)+","+environment+".generate("+item+"))")};return "org.jetbrains.jetCheck.Generator.<Data>from("+environment+" -> new Data.Struct(java.util.List.of("+strings.Join(pieces,",")+")))",nil
    case language.AppliedType(_,_):
        name,args:=applied(t);if name=="Maybe"||name=="Nullable"{if len(args)!=1{return "",fmt.Errorf("%s requires one payload type",name)};item,err:=e.generator(args[0]);if err!=nil{return "",err};variable:=e.fresh("value");if name=="Maybe"{return "org.jetbrains.jetCheck.Generator.<Data>anyOf(org.jetbrains.jetCheck.Generator.<Data>constant(new Data.Variant(\"Nothing\",java.util.List.of())),"+item+".<Data>map("+variable+" -> new Data.Variant(\"Just\",java.util.List.of("+variable+"))))",nil};return "org.jetbrains.jetCheck.Generator.<Data>anyOf(org.jetbrains.jetCheck.Generator.<Data>constant(new Data.Variant(\"Null\",java.util.List.of())),"+item+".<Data>map("+variable+" -> new Data.Variant(\"NonNull\",java.util.List.of("+variable+"))))",nil};decl,ok:=e.declarations[name];if !ok||len(args)!=len(decl.Parameters){return "",fmt.Errorf("unsupported applied payload type %s",name)};if e.visiting[name]{return "",fmt.Errorf("recursive generic application %s is unsupported",name)};bindings:=map[string]*language.Type{};for i,param:=range decl.Parameters{bindings[param]=args[i]};if decl.Body==nil{return "",fmt.Errorf("generic union %s is unsupported as a generated property payload",name)};closed,err:=language.SubstituteType(decl.Body,bindings);if err!=nil{return "",err};e.visiting[name]=true;result,err:=e.generator(closed);delete(e.visiting,name);return result,err
    case language.ArrowType(_,_):return "",fmt.Errorf("function payloads cannot be generated")
    }
    return "",fmt.Errorf("unsupported payload generator")
}

func directNamed(t *language.Type,name string)bool{match t.Form{case language.RefinedType(base,_):return directNamed(base,name);case language.NamedType(found):return found==name;case _:return false}}
func (e *propertyEmitter) unionGenerator(name string,decl language.TypeDecl)(string,error){
    self:=e.fresh("self");base,recursive:=[]string{},[]string{};for _,variant:=range decl.Variants{environment:=e.fresh("env");pieces:=[]string{};usesSelf:=false;for _,argument:=range variant.Arguments{item:="";if directNamed(argument,name){item=self;usesSelf=true}else{var err error;item,err=e.generator(argument);if err!=nil{return "",err}};pieces=append(pieces,environment+".generate("+item+")")};source:="org.jetbrains.jetCheck.Generator.<Data>from("+environment+" -> new Data.Variant("+javaQuote(variant.Name)+",java.util.List.of("+strings.Join(pieces,",")+")))";if usesSelf{recursive=append(recursive,source)}else{base=append(base,source)}}
    if len(base)==0{return "",fmt.Errorf("recursive union %s has no finite base alternative",name)};all:=append(append([]string(nil),base...),recursive...);if len(recursive)==0{return "org.jetbrains.jetCheck.Generator.<Data>anyOf("+strings.Join(all,",")+")",nil};return "org.jetbrains.jetCheck.Generator.<Data>recursive("+self+" -> org.jetbrains.jetCheck.Generator.<Data>anyOf("+strings.Join(all,",")+")).withBase(org.jetbrains.jetCheck.Generator.<Data>anyOf("+strings.Join(base,",")+"))",nil
}

func exampleDataJava(v value.Data)(string,error){
    match v.Kind(){
    case value.NumberData():n,_:=v.Number();return "new Data.Number(Rational.parse("+javaQuote(n.Show())+"))",nil
    case value.TextData():text,_:=v.Text();raw,err:=text.UTF8();if err!=nil{return "",fmt.Errorf("example text is not scalar Unicode")};return "new Data.Text("+javaQuote(raw)+")",nil
    case value.BoolData():b,_:=v.Boolean();return fmt.Sprintf("new Data.Bool(%t)",b),nil
    case value.ListData():parts:=[]string{};for _,item:=range v.Elements(){source,err:=exampleDataJava(item);if err!=nil{return "",err};parts=append(parts,source)};return "new Data.Sequence(java.util.List.of("+strings.Join(parts,",")+"))",nil
    case value.RecordData():parts:=[]string{};for _,field:=range v.Fields(){source,err:=exampleDataJava(field.Value);if err!=nil{return "",err};parts=append(parts,"new Data.Field("+javaQuote(field.Name)+","+source+")")};return "new Data.Struct(java.util.List.of("+strings.Join(parts,",")+"))",nil
    case value.VariantData():name,_:=v.Constructor();parts:=[]string{};for _,item:=range v.Elements(){source,err:=exampleDataJava(item);if err!=nil{return "",err};parts=append(parts,source)};return "new Data.Variant("+javaQuote(name)+",java.util.List.of("+strings.Join(parts,",")+"))",nil
    case value.MapData():parts:=[]string{};for _,entry:=range v.Entries(){key,err:=entry.Key.UTF8();if err!=nil{return "",fmt.Errorf("example map key is not scalar Unicode")};source,err:=exampleDataJava(entry.Value);if err!=nil{return "",err};parts=append(parts,"java.util.Map.entry("+javaQuote(key)+","+source+")")};return "new Data.Mapping(java.util.Map.ofEntries("+strings.Join(parts,",")+"))",nil
    }
    return "",fmt.Errorf("unsupported embedded example")
}

func replayKey(target string,kind ReplayKind,code string)string{return fmt.Sprintf("%s\x00%d\x00%s",target,kind,code)}
func targetUsesFactory(t *language.Type,declarations map[string]language.TypeDecl,seen map[string]bool)bool{match t.Form{case language.RefinedType(base,_):return targetUsesFactory(base,declarations,seen);case language.AppliedType(_,_):name,_:=applied(t);if decl,ok:=declarations[name];ok&&len(decl.Parameters)>0{return true};case language.NamedType(name):if seen[name]{return false};decl,ok:=declarations[name];if ok&&decl.Body!=nil{seen[name]=true;return targetUsesFactory(decl.Body,declarations,seen)};case _:};return false}
func seededPropertyGenerator(raw string,seeds []string)string{if len(seeds)==0{return raw};return "org.jetbrains.jetCheck.Generator.<Data>frequency(3,"+raw+",2,org.jetbrains.jetCheck.Generator.<Data>sampledFrom("+strings.Join(seeds,",")+"))"}

// GeneratePropertyTests emits an executable Java property suite using JetCheck
// 0.3.0. Unsupported strategies reject the complete output.
func GeneratePropertyTests(program *language.Program,namespace,contractName string,options PropertyTestOptions)([]File,error){
    if program==nil{return nil,fmt.Errorf("property tests require a checked program")};if err:=packageName(namespace);err!=nil{return nil,err};if err:=javaClassName(contractName);err!=nil{return nil,err}
    cases:=options.CaseCount;if cases==0{cases=100};attempts:=options.AttemptBudget;if attempts==0{attempts=10000};if cases<1||attempts<1{return nil,fmt.Errorf("property case count and attempt budget must be positive")}
    declarations:=map[string]language.TypeDecl{};for _,decl:=range program.Syntax().Types{declarations[decl.Name]=decl};targets:=options.Targets;if len(targets)==0{for _,decl:=range program.Syntax().Types{if len(decl.Parameters)==0{targets=append(targets,PropertyTarget{Name:decl.Name})}}};if len(targets)==0{return nil,fmt.Errorf("property tests require at least one closed target")}
    replays:=map[string]string{};for i,replay:=range options.Replays{if replay.Target==""||replay.SerializedData==""{return nil,fmt.Errorf("replay %d requires a target and serialized data",i)};if replay.Kind!=ReplayValid&&replay.Kind!=ReplayInvalid{return nil,fmt.Errorf("replay %d has invalid kind",i)};if replay.Kind==ReplayValid&&replay.DiagnosticCode!=""{return nil,fmt.Errorf("valid replay %d must not name a diagnostic",i)};if replay.Kind==ReplayInvalid&&replay.DiagnosticCode==""{return nil,fmt.Errorf("invalid replay %d requires a diagnostic code",i)};key:=replayKey(replay.Target,replay.Kind,replay.DiagnosticCode);if _,exists:=replays[key];exists{return nil,fmt.Errorf("duplicate replay for %s",replay.Target)};replays[key]=replay.SerializedData}
    hasNative:=options.NativeJSONValidator!=""||options.AvroSerde!="";known:=map[string]bool{};indices:=map[string]int{};for i,target:=range targets{decl,ok:=declarations[target.Name];if !ok||len(decl.Parameters)>0{return nil,fmt.Errorf("property target %s must be a closed declaration",target.Name)};if known[target.Name]{return nil,fmt.Errorf("duplicate property target %s",target.Name)};known[target.Name]=true;indices[target.Name]=i}
    validSeeds:=map[string][]string{};invalidSeeds:=map[string]map[string][]string{};for i,example:=range options.Examples{if !known[example.Target]{return nil,fmt.Errorf("example %d targets unknown property target %s",i,example.Target)};if example.NativeExpected!=ExampleNativeValid&&example.NativeExpected!=ExampleNativeInvalid{return nil,fmt.Errorf("example %d has invalid native expected outcome",i)};if example.NativeExpected==ExampleNativeInvalid&&len(example.DiagnosticCodes)>0{return nil,fmt.Errorf("native-invalid example %d cannot claim refinement diagnostics",i)};if example.NativeExpected==ExampleNativeInvalid&&!hasNative{return nil,fmt.Errorf("example %d expects native rejection but no native property adapter is configured",i)};if example.NativeExpected==ExampleNativeInvalid&&example.Expected==ExampleIndeterminate{return nil,fmt.Errorf("native-invalid example %d cannot have an indeterminate Refine outcome",i)};if example.Expected==ExampleInvalid&&example.NativeExpected==ExampleNativeValid&&len(example.DiagnosticCodes)!=1{return nil,fmt.Errorf("refinement-invalid example %d requires exactly one diagnostic code",i)};if example.NativeExpected==ExampleNativeValid&&(example.Expected==ExampleValid||example.Expected==ExampleInvalid){data,err:=exampleDataJava(example.Value);if err!=nil{return nil,err};if example.Expected==ExampleValid{validSeeds[example.Target]=append(validSeeds[example.Target],data)}else{if invalidSeeds[example.Target]==nil{invalidSeeds[example.Target]=map[string][]string{}};code:=example.DiagnosticCodes[0];invalidSeeds[example.Target][code]=append(invalidSeeds[example.Target][code],data)}}}
    emitter:=&propertyEmitter{declarations:declarations,visiting:map[string]bool{}};var methods strings.Builder;usedReplays:=map[string]bool{}
    for i,target:=range targets{decl:=declarations[target.Name];targetType:=decl.Body;if targetType==nil{targetType=&language.Type{Form:language.NamedType(target.Name),At:decl.At}};raw,err:=emitter.boundedGenerator(targetType);if err!=nil{return nil,fmt.Errorf("property target %s: %w",target.Name,err)};rules,err:=emitter.rules(target.Name,"",targetType);if err!=nil{return nil,err};validKey:=replayKey(target.Name,ReplayValid,"");validReplay:=replays[validKey];if validReplay!=""{usedReplays[validKey]=true};factoryDecl,receiver:="",target.Name+".";if targetUsesFactory(targetType,declarations,map[string]bool{}){factoryDecl="var factory=new "+target.Name+"."+modelFactoryNameFor(declarations,contractName)+"(); ";receiver="factory."};fmt.Fprintf(&methods,"    private static boolean validBoundary%d(Data data) {\n        try { %svar model=%sfromData(data); if (!model.rawData().equals(data) || model.validate().state()!=Validation.State.VALID) return false; var shown=model.showWithoutValidation(); var read=%sread(shown); return read.validate().state()==Validation.State.VALID && read.showWithoutValidation().equals(shown) && wireValid(data,model) && avroWireValid(data,model); } catch (ValidationException failure) { return false; }\n    }\n",i,factoryDecl,receiver,receiver);fmt.Fprintf(&methods,"    private static boolean invalidBoundary%d(Data data,String code) {\n        %svar bypass=%sfromDataWithoutValidation(data); if (!bypass.rawData().equals(data) || !targeted(bypass.validate(),code) || !wireInvalid(bypass,code) || !avroWireInvalid(bypass,code)) return false; try { %sfromData(data); return false; } catch (ValidationException failure) { if (!targeted(failure.outcome(),code)) return false; } try { %sread(bypass.showWithoutValidation()); return false; } catch (ValidationException failure) { return targeted(failure.outcome(),code); }\n    }\n",i,factoryDecl,receiver,receiver,receiver);if hasNative{fmt.Fprintf(&methods,"    private static boolean nativeInvalidBoundary%d(Data data,Validation.State expected) {\n        if (expected==Validation.State.VALID) { if (nativeCandidate(data)) return false; try { %svar model=%sfromData(data); if (!model.rawData().equals(data) || model.validate().state()!=Validation.State.VALID) return false; var shown=model.showWithoutValidation(); var read=%sread(shown); return read.rawData().equals(data) && read.showWithoutValidation().equals(shown) && nativeWireInvalid(data,model); } catch (ValidationException failure) { return false; } } try { %sfromData(data); return false; } catch (ValidationException failure) { if (failure.outcome().state()!=Validation.State.INVALID || failure.outcome().incomplete()) return false; } try { %s%sfromDataWithoutValidation(data); return false; } catch (ValidationException failure) { return structureOnly(failure.outcome()); }\n    }\n",i,factoryDecl,receiver,receiver,receiver,factoryDecl,receiver)};fmt.Fprintf(&methods,"    private static void target%d() {\n        var raw = %s;\n        var validRaw = %s;\n        var valid = requiring(validRaw, d -> nativeCandidate(d) && %s.validate(%s,d).state() == Validation.State.VALID, %d, %s);\n        check(valid, %sGeneratedProperties::validBoundary%d, %s);\n",i,raw,seededPropertyGenerator("raw",validSeeds[target.Name]),contractName,javaQuote(target.Name),attempts,javaQuote("valid "+target.Name),contractName,i,javaQuote(validReplay));for j,rule:=range rules{key:=replayKey(target.Name,ReplayInvalid,rule.code);replay:=replays[key];if replay!=""{usedReplays[key]=true};invalidRaw:=seededPropertyGenerator("raw",invalidSeeds[target.Name][rule.code]);fmt.Fprintf(&methods,"        var invalidRaw%d = %s;\n        var invalid%d = requiring(invalidRaw%d, d -> nativeCandidate(d) && targeted(%s.validate(%s,d),%s), %d, %s);\n        check(invalid%d, d -> invalidBoundary%d(d,%s), %s);\n",j,invalidRaw,j,j,contractName,javaQuote(target.Name),javaQuote(rule.code),attempts,javaQuote("invalid "+target.Name+" "+rule.code),j,i,javaQuote(rule.code),javaQuote(replay))};methods.WriteString("    }\n")}
    for key:=range replays{if !usedReplays[key]{return nil,fmt.Errorf("replay does not match a generated target property")}}
    var examples strings.Builder;for i,example:=range options.Examples{data,err:=exampleDataJava(example.Value);if err!=nil{return nil,err};state:="VALID";if example.Expected==ExampleInvalid{state="INVALID"}else if example.Expected==ExampleIndeterminate{state="INDETERMINATE"}else if example.Expected!=ExampleValid{return nil,fmt.Errorf("example %d has invalid expected outcome",i)};complete:="";if example.Expected==ExampleInvalid{complete=" || example"+fmt.Sprint(i)+".incomplete()"};fmt.Fprintf(&examples,"        var exampleData%d=%s; var example%d = %s.validate(%s,exampleData%d); if (example%d.state() != Validation.State.%s%s) throw new AssertionError(\"embedded example %d outcome\");\n",i,data,i,contractName,javaQuote(example.Target),i,i,state,complete,i);for _,code:=range example.DiagnosticCodes{fmt.Fprintf(&examples,"        if (example%d.diagnostics().stream().noneMatch(d -> d.code().equals(%s))) throw new AssertionError(\"embedded example %d diagnostic\");\n",i,javaQuote(code),i)};targetIndex:=indices[example.Target];if example.NativeExpected==ExampleNativeInvalid{fmt.Fprintf(&examples,"        if (!nativeInvalidBoundary%d(exampleData%d,Validation.State.%s)) throw new AssertionError(\"embedded example %d native/structural boundary\");\n",targetIndex,i,state,i)}else{if hasNative{fmt.Fprintf(&examples,"        if (!nativeCandidate(exampleData%d)) throw new AssertionError(\"embedded example %d is not native-representable\");\n",i,i)};if example.Expected==ExampleValid{fmt.Fprintf(&examples,"        if (!validBoundary%d(exampleData%d)) throw new AssertionError(\"embedded example %d valid boundary\");\n",targetIndex,i,i)}else if example.Expected==ExampleInvalid{fmt.Fprintf(&examples,"        if (!invalidBoundary%d(exampleData%d,%s)) throw new AssertionError(\"embedded example %d invalid boundary\");\n",targetIndex,i,javaQuote(example.DiagnosticCodes[0]),i)}}}
    header:="// Generated by Refine: JetCheck 0.3.0 property tests.\n";if namespace!=""{header+="package "+namespace+";\n"};class:=contractName+"GeneratedProperties";calls:=[]string{};for i:=range targets{calls=append(calls,fmt.Sprintf("target%d();",i))}
    candidateFields:="";jsonCandidate,avroCandidate:="true","true"
    if options.NativeJSONValidator!=""{if options.JSONModule==""{return nil,fmt.Errorf("a native JSON candidate filter requires JSONModule")};if err:=javaClassName(options.NativeJSONValidator);err!=nil{return nil,err};candidateFields="    private static final "+options.JSONModule+" NATIVE_CANDIDATES=new "+options.JSONModule+"();\n";jsonCandidate="NATIVE_CANDIDATES.acceptsNativeCandidate(data)"}
    if options.AvroSerde!=""{if err:=javaClassName(options.AvroSerde);err!=nil{return nil,err};avroCandidate="AVRO.acceptsNativeCandidate(data)"}
    nativeCandidate:=candidateFields+"    private static boolean jsonNativeCandidate(Data data) { return "+jsonCandidate+"; }\n    private static boolean avroNativeCandidate(Data data) { return "+avroCandidate+"; }\n    private static boolean nativeCandidate(Data data) { return jsonNativeCandidate(data) && avroNativeCandidate(data); }\n"
    wireMethods:=nativeCandidate+"    private static boolean wireValid(Data data,Object model) { return true; }\n    private static boolean wireInvalid(Object model,String code) { return true; }\n    private static boolean wireNativeInvalid(Object model) { return false; }\n"
    if options.JSONModule!=""{
        if err:=javaClassName(options.JSONModule);err!=nil{return nil,err};if len(targets)!=1{return nil,fmt.Errorf("a JSON property module currently requires exactly one target")}
        nativeFailureCheck:="";if options.NativeJSONValidator!=""{nativeFailureCheck="if (cause instanceof "+options.NativeJSONValidator+".NativeValidationException nativeFailure) return output.size()==0 && !nativeFailure.isIndeterminate();"}
        wireMethods=nativeCandidate+fmt.Sprintf(`    private static final tools.jackson.databind.json.JsonMapper WIRE=%s.strictMapper();
    private static boolean wireValid(Data data,Object model) {
        String json=WIRE.writeValueAsString(model); var decoded=WIRE.readValue(json,%s.class);
        return decoded.rawData().equals(data) && WIRE.writeValueAsString(decoded).equals(json);
    }
    private static boolean wireInvalid(Object model,String code) {
        var output=new java.io.ByteArrayOutputStream();
        try { WIRE.writeValue(output,model); return false; }
        catch (RuntimeException expected) {
            Throwable cause=expected;
            for (int i=0;cause!=null && i<32;i++,cause=cause.getCause()) {
                if (cause instanceof ValidationException validation) return output.size()==0 && targeted(validation.outcome(),code);
            }
            return false;
        }
    }
    private static boolean wireNativeInvalid(Object model) {
        var output=new java.io.ByteArrayOutputStream();
        try { WIRE.writeValue(output,model); return false; }
        catch (RuntimeException expected) {
            Throwable cause=expected;
            for (int i=0;cause!=null && i<32;i++,cause=cause.getCause()) {
                %s
                if (cause instanceof ValidationException validation) return output.size()==0 && structureOnly(validation.outcome());
                if (cause instanceof ArithmeticException) return output.size()==0;
            }
            return false;
        }
    }
`,options.JSONModule,targets[0].Name,nativeFailureCheck)
    }
    if options.AvroSerde==""{wireMethods+="    private static boolean avroWireValid(Data data,Object model) { return true; }\n    private static boolean avroWireInvalid(Object model,String code) { return true; }\n    private static boolean avroNativeWireInvalid(Object model) { return false; }\n"}else{
        if len(targets)!=1{return nil,fmt.Errorf("an Avro property adapter currently requires exactly one target")}
        wireMethods+=fmt.Sprintf(`    private static final %s AVRO=new %s();
    private static boolean avroWireValid(Data data,Object model) {
        try { var value=(%s)model; byte[] binary=AVRO.writeBinary(value); var decoded=AVRO.readBinary(binary); String json=AVRO.writeJson(value); var jsonDecoded=AVRO.readJson(json); return decoded.rawData().equals(data) && jsonDecoded.rawData().equals(data) && java.util.Arrays.equals(binary,AVRO.writeBinary(decoded)) && json.equals(AVRO.writeJson(jsonDecoded)); }
        catch (java.io.IOException failure) { return false; }
    }
    private static boolean avroWireInvalid(Object model,String code) {
        var output=new java.io.ByteArrayOutputStream();
        try { AVRO.writeBinary((%s)model,output); return false; }
        catch (ValidationException expected) { return output.size()==0 && targeted(expected.outcome(),code); }
        catch (java.io.IOException failure) { return false; }
    }
    private static boolean avroNativeWireInvalid(Object model) {
        var output=new java.io.ByteArrayOutputStream();
        try { AVRO.writeBinary((%s)model,output); return false; }
        catch (ValidationException expected) { return output.size()==0 && structureOnly(expected.outcome()); }
        catch (java.io.IOException failure) { return false; }
    }
`,options.AvroSerde,options.AvroSerde,targets[0].Name,targets[0].Name,targets[0].Name)
    }
    wireMethods+="    private static boolean nativeWireInvalid(Data data,Object model) { boolean rejected=false; if (!jsonNativeCandidate(data)) { rejected=true; if (!wireNativeInvalid(model)) return false; } if (!avroNativeCandidate(data)) { rejected=true; if (!avroNativeWireInvalid(model)) return false; } return rejected; }\n"
    propertyMethods:=methods.String()
    source:=header+fmt.Sprintf(`@SuppressWarnings("deprecation")
public final class %s {
    private static final int CASES=%d; private static final long SEED=%dL;
    private static <T> org.jetbrains.jetCheck.Generator<T> requiring(org.jetbrains.jetCheck.Generator<T> raw, java.util.function.Predicate<T> wanted, int attempts, String label) { return org.jetbrains.jetCheck.Generator.from(env -> { for (int i=0;i<attempts;i++) { T value=env.generate(raw); if (wanted.test(value)) { env.generate(org.jetbrains.jetCheck.Generator.integers()); return value; } } throw new AssertionError("property generation exhausted: "+label+" after "+attempts+" attempts"); }); }
    private static <T extends Data> void check(org.jetbrains.jetCheck.Generator<T> generator, java.util.function.Predicate<T> property, String replay) { if (replay.isEmpty()) org.jetbrains.jetCheck.PropertyChecker.customized().withSeed(SEED).withIterationCount(CASES).silent().forAll(generator,property); else org.jetbrains.jetCheck.PropertyChecker.customized().rechecking(replay).silent().forAll(generator,property); }
    private static boolean targeted(Validation.Outcome outcome,String code) { return outcome.state()==Validation.State.INVALID && !outcome.incomplete() && outcome.diagnostics().stream().anyMatch(d -> d.code().equals(code)); }
    private static boolean structureOnly(Validation.Outcome outcome) { return outcome.state()==Validation.State.INVALID && !outcome.incomplete() && !outcome.diagnostics().isEmpty() && outcome.diagnostics().stream().allMatch(d -> d.code().equals("validation.structure")); }
%s
%s
    public static void main(String[] args) { %s %s }
}
`,class,cases,options.Seed,wireMethods,propertyMethods,examples.String(),strings.Join(calls," "))
    prefix:=strings.ReplaceAll(namespace,".","/");return []File{{Path:path.Join(prefix,class+".java"),Source:source}},nil
}
