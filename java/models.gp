package java

import (
    "fmt"
    "path"
    "strconv"
    "strings"
    "unicode"

    "goforge.dev/refine/language"
)

type modelField struct { name string; member string; setter string; typ *language.Type }
type modelEmitter struct {
    module *language.Module
    namespace string
    contract string
    declarations map[string]language.TypeDecl
    parents map[string]string
    children map[string][]string
    fields map[string][]modelField
    alternatives map[string]map[string]string
    unionViews map[string]string
    locals map[string]bool
    next int
}
func unrefined(t *language.Type)*language.Type{for{match t.Form{case language.RefinedType(base,_):t=base;case _:return t}}}
func integerType(name string)bool{
    if name=="Int"{return true}
    digits:=strings.TrimPrefix(strings.TrimPrefix(name,"UInt"),"Int")
    if digits==name{return false};n,err:=strconv.ParseUint(digits,10,32);return err==nil&&n>0&&strconv.FormatUint(n,10)==digits
}
func (m *modelEmitter) fresh()string{for{m.next++;name:=fmt.Sprintf("_refine%d",m.next);if !m.locals[name]{m.locals[name]=true;return name}}}
func (m *modelEmitter) qualified(name string)string{if m.namespace==""{return name};return m.namespace+"."+name}
func (m *modelEmitter) shape(name string)*language.Type{
    seen:=map[string]bool{}
    for{
        if seen[name]{unsupported(m.declarations[name].At,"cyclic model alias has no structural representation")};seen[name]=true
        decl:=m.declarations[name];if decl.Body==nil{return nil}
        t:=unrefined(decl.Body)
        match t.Form{case language.NamedType(parent):if _,found:=m.declarations[parent];found{name=parent;continue};case _:}
        return t
    }
}
func applied(t *language.Type)(string,[]*language.Type){
    args:=[]*language.Type{}
    for{stop:=false;match t.Form{case language.AppliedType(fn,arg):args=append([]*language.Type{arg},args...);t=fn;case _:stop=true};if stop{break}}
    match t.Form{case language.NamedType(name):return name,args;case _:unsupported(t.At,"unsupported model type application")};return "",nil
}
func (m *modelEmitter) javaType(t *language.Type)string{
    t=unrefined(t)
    match t.Form{
    case language.NamedType(name):
        if integerType(name){return "java.math.BigInteger"}
        switch name{case "Real":return "Rational";case "String":return "java.lang.String";case "Bool":return "java.lang.Boolean";case "Timestamp":return "Timestamp"}
        if _,found:=m.declarations[name];found{return m.qualified(name)}
        unsupported(t.At,"unsupported Java model type "+name)
    case language.ListType(element):return "java.util.List<"+m.javaType(element)+">"
    case language.AppliedType(_,_):
        name,args:=applied(t);javaName:=""
        switch name{case "Maybe":javaName="ModelMaybe";case "Nullable":javaName="ModelNullable";case "Result":javaName="ModelResult";default:unsupported(t.At,"parameterized domain models remain required")}
        types:=[]string{};for _,arg:=range args{types=append(types,m.javaType(arg))};return javaName+"<"+strings.Join(types,", ")+">"
    case language.RecordType(_):unsupported(t.At,"anonymous nested record model classes remain required")
    case _:unsupported(t.At,"unsupported Java model representation")
    }
    return ""
}
func (m *modelEmitter) encode(t *language.Type,input,location string)string{
    t=unrefined(t)
    match t.Form{
    case language.NamedType(name):
        method:="";if integerType(name){method="integer"}else{switch name{case "Real":method="real";case "String":method="text";case "Bool":method="bool";case "Timestamp":method="timestamp"}}
        if method!=""{return "ModelSupport."+method+"("+input+","+location+")"}
        m.javaType(t);return "ModelSupport.nonNull("+input+","+location+").rawData()"
    case language.ListType(element):
        item,where:=m.fresh(),m.fresh();return "ModelSupport.list("+input+",("+item+","+where+") -> "+m.encode(element,item,where)+","+location+")"
    case language.AppliedType(_,_):
        name,args:=applied(t);m.javaType(t);method:=strings.ToLower(name)
        pieces:=[]string{input};for _,arg:=range args{item,where:=m.fresh(),m.fresh();pieces=append(pieces,"("+item+","+where+") -> "+m.encode(arg,item,where))};pieces=append(pieces,location)
        return "ModelSupport."+method+"("+strings.Join(pieces,",")+")"
    case _:unsupported(t.At,"unsupported model encoder")
    };return ""
}
func (m *modelEmitter) decode(t *language.Type,input string)string{
    t=unrefined(t)
    match t.Form{
    case language.NamedType(name):
        if integerType(name){return "((Data.Number)"+input+").value().numerator()"}
        switch name{case "Real":return "((Data.Number)"+input+").value()";case "String":return "((Data.Text)"+input+").value()";case "Bool":return "((Data.Bool)"+input+").value()";case "Timestamp":return "Timestamp.parse(((Data.Text)"+input+").value())"}
        m.javaType(t);return m.qualified(name)+".fromDataWithoutValidation("+input+")"
    case language.ListType(element):item:=m.fresh();return "ModelSupport.list("+input+","+item+" -> "+m.decode(element,item)+")"
    case language.AppliedType(_,_):
        name,args:=applied(t);m.javaType(t);pieces:=[]string{input};for _,arg:=range args{item:=m.fresh();pieces=append(pieces,item+" -> "+m.decode(arg,item))}
        return "ModelSupport."+strings.ToLower(name)+"("+strings.Join(pieces,",")+")"
    case _:unsupported(t.At,"unsupported model decoder")
    };return ""
}
func fieldIdentifier(name string)string{
    if packageName(name)==nil&&!strings.Contains(name,"."){return name}
    var out strings.Builder
    for i,r:=range name{valid:=unicode.IsLetter(r)||unicode.In(r,unicode.Nl,unicode.Sc,unicode.Pc);if i>0{valid=valid||unicode.IsDigit(r)||unicode.In(r,unicode.Mn,unicode.Mc)};if valid{out.WriteRune(r)}else{fmt.Fprintf(&out,"_u%x_",r)}}
    result:=out.String();if result==""{result="field"};for packageName(result)!=nil{result+="_"};return result
}
func upperFirst(name string)string{runes:=[]rune(name);runes[0]=unicode.ToUpper(runes[0]);return string(runes)}
func sourceNameKey(name string)string{
    var out strings.Builder
    for _,r:=range name{smallest:=r;for next:=unicode.SimpleFold(r);next!=r;next=unicode.SimpleFold(next){if next<smallest{smallest=next}};out.WriteRune(smallest)}
    return out.String()
}
func (m *modelEmitter) recordFields(root string,t *language.Type)[]modelField{
    if fields,found:=m.fields[root];found{return fields}
    reserved:=" rawData validate fromData fromDataWithoutValidation create createWithoutValidation update updateWithoutValidation validateData read showWithoutValidation equals hashCode toString getClass wait notify notifyAll draft newDraft freeze caller raw change evidence source "
    used,setters:=map[string]bool{},map[string]bool{};result:=[]modelField{}
    match t.Form{case language.RecordType(fields):for _,field:=range fields{
        member:=fieldIdentifier(field.Name);for used[member]||strings.Contains(reserved," "+member+" "){member+="_"};used[member]=true;m.locals[member]=true
        setter:="set"+upperFirst(member);for setters[setter]{setter+="_"};setters[setter]=true
        m.javaType(field.Type);result=append(result,modelField{name:field.Name,member:member,setter:setter,typ:field.Type})
    };case _:panic("recordFields requires a record")}
    m.fields[root]=result;return result
}
func (m *modelEmitter) rawRecord(fields []modelField)string{
    values:=[]string{};for _,field:=range fields{location:="/"+strings.ReplaceAll(strings.ReplaceAll(field.name,"~","~0"),"/","~1");values=append(values,"new Data.Field("+javaQuote(field.name)+","+m.encode(field.typ,field.member,javaQuote(location))+")")}
    return "new Data.Struct("+javaList(values)+")"
}
func (m *modelEmitter) modelDraftName()string{
    used:=map[string]bool{sourceNameKey(m.contract):true}
    for name:=range m.declarations{used[sourceNameKey(name)]=true}
    name:="Draft";for used[sourceNameKey(name)]{name+="_"};return name
}
func (m *modelEmitter) model(decl language.TypeDecl)string{
    name:=decl.Name;parent:=m.parents[name];root:=name;for m.parents[root]!=""{root=m.parents[root]}
    shape:=m.shape(name);record:=false;match shape.Form{case language.RecordType(_):record=true;case _:}
    fields:=[]modelField{};if record{fields=m.recordFields(root,shape)}else{m.javaType(shape)}
    modifier:="final";permits:="";if len(m.children[name])>0{modifier="sealed";permits=" permits "+strings.Join(m.children[name],", ")}
    inheritance:="";if parent!=""{inheritance=" extends "+parent}
    var out strings.Builder;fmt.Fprintf(&out,"public %s class %s%s%s {\n",modifier,name,inheritance,permits)
    if parent==""{out.WriteString("    private final Data raw;\n")}
    fmt.Fprintf(&out,"    protected %s(ModelSupport.Evidence evidence) {\n",name)
    if parent!=""{out.WriteString("        super(evidence);\n");fmt.Fprintf(&out,"        evidence.dataFor(%s);\n",javaQuote(name))}else{fmt.Fprintf(&out,"        this.raw = evidence.dataFor(%s);\n",javaQuote(name))};out.WriteString("    }\n")
    parameters,arguments:=[]string{},[]string{};raw:=""
    if record{for _,field:=range fields{parameters=append(parameters,m.javaType(field.typ)+" "+field.member);arguments=append(arguments,field.member)};raw=m.rawRecord(fields)}else{parameters=append(parameters,m.javaType(shape)+" value");arguments=append(arguments,"value");raw=m.encode(shape,"value",`""`)}
    withCaller:=append(append([]string(nil),parameters...),"Budget.Limits caller")
    withDefault:=append(append([]string(nil),arguments...),"Budget.Limits.defaults()")
    // Every host representation occupies one reference slot. Reserve slots
    // for this and the caller budget; wider records use typed draft factories.
    if len(parameters)<=253{
        fmt.Fprintf(&out,"    public %s(%s) { this(%s); }\n",name,strings.Join(parameters,", "),strings.Join(withDefault,", "))
        fmt.Fprintf(&out,"    public %s(%s) { this(ModelSupport.validate(%s,%s,caller)); }\n",name,strings.Join(withCaller,", "),javaQuote(name),raw)
        fmt.Fprintf(&out,"    public static %s createWithoutValidation(%s) { return createWithoutValidation(%s); }\n",name,strings.Join(parameters,", "),strings.Join(withDefault,", "))
        fmt.Fprintf(&out,"    public static %s createWithoutValidation(%s) { return new %s(ModelSupport.withoutValidation(%s,%s,caller)); }\n",name,strings.Join(withCaller,", "),name,javaQuote(name),raw)
    }
    for _,bypass:=range []bool{false,true}{
        suffix,method:="","validate";if bypass{suffix,method="WithoutValidation","withoutValidation"}
        fmt.Fprintf(&out,"    public static %s fromData%s(Data raw) { return fromData%s(raw,Budget.Limits.defaults()); }\n",name,suffix,suffix)
        fmt.Fprintf(&out,"    public static %s fromData%s(Data raw, Budget.Limits caller) { return new %s(ModelSupport.%s(%s,ModelSupport.nonNull(raw,\"\"),caller)); }\n",name,suffix,name,method,javaQuote(name))
    }
    out.WriteString("    public static Validation.Outcome validateData(Data raw) { return validateData(raw,Budget.Limits.defaults()); }\n")
    fmt.Fprintf(&out,"    public static %s read(String text) { return read(text,Budget.Limits.defaults()); }\n",name)
    fmt.Fprintf(&out,"    public static %s read(String text, Budget.Limits caller) { return new %s(ModelSupport.read(%s,text,caller)); }\n",name,name,javaQuote(name))
    fmt.Fprintf(&out,"    public static Validation.Outcome validateData(Data raw, Budget.Limits caller) { return %s.validate(%s,raw,caller); }\n",m.contract,javaQuote(name))
    fmt.Fprintf(&out,"    public Validation.Outcome validate() { return validate(Budget.Limits.defaults()); }\n    public Validation.Outcome validate(Budget.Limits caller) { return %s.validate(%s,rawData(),caller); }\n",m.contract,javaQuote(name))
    if parent==""{
        out.WriteString("    public final Data rawData() { return raw; }\n")
        fmt.Fprintf(&out,"    public final String showWithoutValidation() { return showWithoutValidation(Budget.Limits.defaults()); }\n    public final String showWithoutValidation(Budget.Limits caller) { return %s.showWithoutValidation(rawData(),caller); }\n",m.contract)
        if record{for _,field:=range fields{fmt.Fprintf(&out,"    public final %s %s() { return %s; }\n",m.javaType(field.typ),field.member,m.decode(field.typ,"ModelSupport.field(rawData(),"+javaQuote(field.name)+")"))}}else{fmt.Fprintf(&out,"    public final %s value() { return %s; }\n",m.javaType(shape),m.decode(shape,"rawData()"))}
    }
    if record{
        draftName:=m.modelDraftName();draftType:=root+"."+draftName
        for _,bypass:=range []bool{false,true}{
            suffix:="";if bypass{suffix="WithoutValidation"}
            fmt.Fprintf(&out,"    public static %s create%s(java.util.function.Consumer<%s> initialize) { return create%s(initialize,Budget.Limits.defaults()); }\n",name,suffix,draftType,suffix)
            fmt.Fprintf(&out,"    public static %s create%s(java.util.function.Consumer<%s> initialize, Budget.Limits caller) { %s draft = newDraft(); initialize.accept(draft); return fromData%s(draft.freeze(),caller); }\n",name,suffix,draftType,draftType,suffix)
            fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change) { return update%s(change,Budget.Limits.defaults()); }\n",name,suffix,draftType,suffix)
            fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change, Budget.Limits caller) { %s draft = draft(); change.accept(draft); return fromData%s(draft.freeze(),caller); }\n",name,suffix,draftType,draftType,suffix)
        }
        if parent==""{
            fmt.Fprintf(&out,"    protected final %s draft() { return new %s(this); }\n    protected static %s newDraft() { return new %s(); }\n    public static final class %s {\n",draftName,draftName,draftName,draftName,draftName)
            baseline:=m.fresh();changed:=[]string{}
            fmt.Fprintf(&out,"        private final Data %s;\n",baseline)
            for _,field:=range fields{fmt.Fprintf(&out,"        private %s %s;\n",m.javaType(field.typ),field.member)}
            for range fields{flag:=m.fresh();changed=append(changed,flag);fmt.Fprintf(&out,"        private boolean %s;\n",flag)}
            fmt.Fprintf(&out,"        private %s() { this.%s = new Data.Struct(java.util.List.of()); }\n",draftName,baseline)
            fmt.Fprintf(&out,"        private %s(%s source) { this.%s = source.rawData(); }\n",draftName,name,baseline)
            for i,field:=range fields{fmt.Fprintf(&out,"        public void %s(%s value) { this.%s = value; this.%s = true; }\n",field.setter,m.javaType(field.typ),field.member,changed[i])}
            out.WriteString("        Data freeze() {\n            var changes = new java.util.LinkedHashMap<String, Data>();\n")
            for i:=0;i<len(fields);i+=64{fmt.Fprintf(&out,"            fields%d(changes);\n",i/64)}
            fmt.Fprintf(&out,"            return ModelSupport.applyChanges(this.%s,changes);\n        }\n",baseline)
            for start:=0;start<len(fields);start+=64{
                fmt.Fprintf(&out,"        private void fields%d(java.util.Map<String,Data> changes) {\n",start/64)
                for i:=start;i<min(start+64,len(fields));i++{field:=fields[i];location:="/"+strings.ReplaceAll(strings.ReplaceAll(field.name,"~","~0"),"/","~1");fmt.Fprintf(&out,"            if (this.%s) changes.put(%s,%s);\n",changed[i],javaQuote(field.name),m.encode(field.typ,"this."+field.member,javaQuote(location)))}
                out.WriteString("        }\n")
            }
            out.WriteString("    }\n")
        }
    }
    out.WriteString("}\n");return out.String()
}

// GenerateModels emits semantic Java models and the checked validator they use.
// No filesystem or deployment operations occur. All emitted constructors validate
// by default; named bypass factories retain structural checks. Unsupported model
// forms reject the complete output, never degrade fields to Object or raw Data.
func GenerateModels(program *language.Program,namespace,contractName string)(files []File,failure error){
    defer func(){if caught:=recover();caught!=nil{if err,ok:=caught.(*GenerationError);ok{files=nil;failure=err}else{panic(caught)}}}()
    files,failure=GenerateValidator(program,namespace,contractName);if failure!=nil{return nil,failure}
    m:=&modelEmitter{module:program.Syntax(),namespace:namespace,contract:contractName,declarations:map[string]language.TypeDecl{},parents:map[string]string{},children:map[string][]string{},fields:map[string][]modelField{},alternatives:map[string]map[string]string{},unionViews:map[string]string{},locals:map[string]bool{"value":true}}
    sourceNames:=map[string]bool{}
    for _,file:=range files{sourceNames[sourceNameKey(path.Base(file.Path))]=true}
    for _,name:=range []string{"ModelSupport","ModelMaybe","ModelNullable","ModelResult"}{sourceNames[sourceNameKey(name+".java")]=true}
    for _,decl:=range m.module.Types{
        if err:=javaClassName(decl.Name);err!=nil{unsupported(decl.At,err.Error())}
        if decl.Name==contractName{unsupported(decl.At,"model name conflicts with the chosen contract class")}
        folded:=sourceNameKey(decl.Name+".java");if sourceNames[folded]{unsupported(decl.At,"model source names collide on a case-insensitive filesystem")};sourceNames[folded]=true
        if len(decl.Parameters)>0{unsupported(decl.At,"parameterized domain model emission remains required")}
        m.declarations[decl.Name]=decl
    }
    for _,decl:=range m.module.Types{
        if decl.Body==nil{continue}
        match unrefined(decl.Body).Form{case language.NamedType(parent):if _,found:=m.declarations[parent];found{m.parents[decl.Name]=parent;m.children[parent]=append(m.children[parent],decl.Name)};case _:}
        m.shape(decl.Name)
    }
    // Populate every field spelling before allocating lambda-local names.
    for _,decl:=range m.module.Types{
        root:=decl.Name;for m.parents[root]!=""{root=m.parents[root]};shape:=m.shape(root)
        if shape==nil{m.unionNames(root);continue}
        match shape.Form{case language.RecordType(_):m.recordFields(root,shape);case _:}
    }
    header:="// Generated by Refine: development Java 25 models. MIT licensed.\n";if namespace!=""{header+="package "+namespace+";\n"}
    prefix:=strings.ReplaceAll(namespace,".","/");parents:=[]string{}
    for _,decl:=range m.module.Types{if parent:=m.parents[decl.Name];parent!=""{parents=append(parents,"java.util.Map.entry("+javaQuote(decl.Name)+","+javaQuote(parent)+")")}}
    support:=[]struct{name string;body string}{{"ModelSupport",fmt.Sprintf(modelSupportJava,strings.Join(parents,","),contractName,contractName,contractName)},{"ModelMaybe",modelMaybeJava},{"ModelNullable",modelNullableJava},{"ModelResult",modelResultJava}}
    for _,item:=range support{files=append(files,File{Path:path.Join(prefix,item.name+".java"),Source:header+item.body})}
    for _,decl:=range m.module.Types{
        source:="";if m.shape(decl.Name)==nil{source=m.unionModel(decl)}else{source=m.model(decl)}
        files=append(files,File{Path:path.Join(prefix,decl.Name+".java"),Source:header+source})
    }
    return files,nil
}
