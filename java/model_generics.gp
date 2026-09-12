package java

import (
    "fmt"
    "strings"

    "goforge.dev/refine/language"
)

func (m *modelEmitter) genericModel(decl language.TypeDecl)string{
    frames:=m.modelFrames(decl);self,root:=frames[0],frames[len(frames)-1]
    m.useFrame(root);shape:=unrefined(root.declaration.Body);fields:=[]modelField{};record:=false
    match shape.Form{case language.RecordType(_):record=true;fields=m.recordFields(root.declaration.Name,shape);case _:m.javaType(shape)}
    fieldParams,fieldArgs:=[]string{},[]string{};raw:=""
    if record{for _,field:=range fields{fieldParams=append(fieldParams,m.javaType(field.typ)+" "+field.member);fieldArgs=append(fieldArgs,field.member)};raw=m.rawRecord(fields)}else{fieldParams=[]string{m.javaType(shape)+" value"};fieldArgs=[]string{"value"};raw=m.encode(shape,"value",`""`)}
    m.useFrame(self);types,parameters,arguments:=m.genericParts(decl);suffix:=genericSuffix(types);name:=decl.Name;full:=name+suffix
    if len(parameters)>250{unsupported(decl.At,"generic model witness arity exceeds JVM method limits")}
    join:=func(extra ...string)string{return strings.Join(append(append([]string{},parameters...),extra...),", ")}
    args:=func(extra ...string)string{return strings.Join(append(append([]string{},arguments...),extra...),", ")}
    target:="ModelTypes.for"+name+"("+args()+")"
    parent:=m.parents[name];modifier,inheritance,permits:="final","",""
    if len(m.children[name])>0{modifier="sealed";permits=" permits "+strings.Join(m.children[name],", ")}
    if parent!=""{inheritance=" extends "+m.qualified(parent)+genericSuffix(frames[1].typeArguments)}
    factoryName:=m.modelFactoryName();factory:=m.factoryInstance(decl,arguments)
    diamond:="";if suffix!=""{diamond="<>"}
    var out strings.Builder;fmt.Fprintf(&out,"public %s class %s%s%s {\n",modifier,full,inheritance,permits)
    if parent==""{out.WriteString("    private final Data $raw;\n")}
    for _,p:=range parameters{fmt.Fprintf(&out,"    private final %s;\n",p)}
    fmt.Fprintf(&out,"    protected %s(%s) {\n",name,join("ModelSupport.GenericEvidence evidence"))
    if parent!=""{superArgs:=append(append([]string{},frames[1].arguments...),"evidence");fmt.Fprintf(&out,"        super(%s);\n        evidence.dataFor(%s);\n",strings.Join(superArgs,","),target)}else{fmt.Fprintf(&out,"        this.$raw=evidence.dataFor(%s);\n",target)}
    for _,arg:=range arguments{fmt.Fprintf(&out,"        this.%s=java.util.Objects.requireNonNull(%s);\n",arg,arg)};out.WriteString("    }\n")
    positional:=len(parameters)+len(fieldParams)<=253
    if positional{
        fmt.Fprintf(&out,"    public %s(%s) { this(%s); }\n",name,join(fieldParams...),args(append(append([]string{},fieldArgs...),"Budget.Limits.defaults()")...))
        fmt.Fprintf(&out,"    public %s(%s) { this(%s); }\n",name,join(append(append([]string{},fieldParams...),"Budget.Limits caller")...),args("ModelSupport.validate("+target+","+raw+",caller)"))
    }
    fmt.Fprintf(&out,"    public Validation.Outcome validate() { return validate(Budget.Limits.defaults()); }\n    public Validation.Outcome validate(Budget.Limits caller) { return %s.validateData(rawData(),caller); }\n",target)
    if parent==""{
        fmt.Fprintf(&out,"    public final Data rawData() { return $raw; }\n    public final String showWithoutValidation() { return showWithoutValidation(Budget.Limits.defaults()); }\n    public final String showWithoutValidation(Budget.Limits caller) { return %s.showWithoutValidation($raw,caller); }\n",m.contract)
        m.useFrame(root)
        if record{for _,field:=range fields{fmt.Fprintf(&out,"    public final %s %s() { return %s; }\n",m.javaType(field.typ),field.member,m.decode(field.typ,"ModelSupport.field($raw,"+javaQuote(field.name)+")"))}}else{fmt.Fprintf(&out,"    public final %s value() { return %s; }\n",m.javaType(shape),m.decode(shape,"$raw"))}
        m.useFrame(self)
    }
    draftName:=m.modelDraftName();draft:=m.qualified(root.declaration.Name)+"."+draftName+genericSuffix(root.typeArguments)
    newDraft:=func(raw string)string{return m.qualified(root.declaration.Name)+".$newDraft("+strings.Join(append(append([]string{},root.arguments...),raw),",")+")"}
    if record{for _,ending:=range []string{"","WithoutValidation"}{
        fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change) { return update%s(change,Budget.Limits.defaults()); }\n",full,ending,draft,ending)
        fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change,Budget.Limits caller) { var draft=%s; change.accept(draft); return %s.fromData%s(draft.freeze(),caller); }\n",full,ending,draft,newDraft("rawData()"),factory,ending)
    }}
    // Static generic method hiding is unsound for transformed parent arguments.
    // Each declaration owns an independent factory; root shorthands are retained.
    staticWrapper:=func(method,result string,params,call []string){
        if parent!=""{return}
        fmt.Fprintf(&out,"    public static %s %s %s(%s) { return %s.%s(%s); }\n",suffix,result,method,join(params...),factory,method,strings.Join(call,","))
    }
    for _,ending:=range []string{"","WithoutValidation"}{
        staticWrapper("fromData"+ending,full,[]string{"Data raw"},[]string{"raw"})
        staticWrapper("fromData"+ending,full,[]string{"Data raw","Budget.Limits caller"},[]string{"raw","caller"})
        if record{staticWrapper("create"+ending,full,[]string{"java.util.function.Consumer<"+draft+"> initialize"},[]string{"initialize"});staticWrapper("create"+ending,full,[]string{"java.util.function.Consumer<"+draft+"> initialize","Budget.Limits caller"},[]string{"initialize","caller"})}
    }
    if positional{staticWrapper("createWithoutValidation",full,fieldParams,fieldArgs);staticWrapper("createWithoutValidation",full,append(append([]string{},fieldParams...),"Budget.Limits caller"),append(append([]string{},fieldArgs...),"caller"))}
    staticWrapper("read",full,[]string{"String text"},[]string{"text"});staticWrapper("read",full,[]string{"String text","Budget.Limits caller"},[]string{"text","caller"})
    staticWrapper("validateData","Validation.Outcome",[]string{"Data raw"},[]string{"raw"});staticWrapper("validateData","Validation.Outcome",[]string{"Data raw","Budget.Limits caller"},[]string{"raw","caller"})
    fmt.Fprintf(&out,"    public static final class %s%s {\n",factoryName,suffix)
    for _,p:=range parameters{fmt.Fprintf(&out,"        private final %s;\n",p)}
    fmt.Fprintf(&out,"        public %s(%s) {\n",factoryName,join())
    for _,arg:=range arguments{fmt.Fprintf(&out,"            this.%s=java.util.Objects.requireNonNull(%s);\n",arg,arg)};out.WriteString("        }\n")
    for _,ending:=range []string{"","WithoutValidation"}{
        method:="validate";if ending!=""{method="withoutValidation"}
        fmt.Fprintf(&out,"        public %s fromData%s(Data raw) { return fromData%s(raw,Budget.Limits.defaults()); }\n",full,ending,ending)
        fmt.Fprintf(&out,"        public %s fromData%s(Data raw,Budget.Limits caller) { return new %s%s(%s); }\n",full,ending,name,diamond,args("ModelSupport."+method+"("+target+",raw,caller)"))
        if record{
            fmt.Fprintf(&out,"        public %s create%s(java.util.function.Consumer<%s> initialize) { return create%s(initialize,Budget.Limits.defaults()); }\n",full,ending,draft,ending)
            fmt.Fprintf(&out,"        public %s create%s(java.util.function.Consumer<%s> initialize,Budget.Limits caller) { var draft=%s; initialize.accept(draft); return fromData%s(draft.freeze(),caller); }\n",full,ending,draft,newDraft("new Data.Struct(java.util.List.of())"),ending)
        }
    }
    if positional{
        fmt.Fprintf(&out,"        public %s createWithoutValidation(%s) { return createWithoutValidation(%s); }\n",full,strings.Join(fieldParams,","),strings.Join(append(append([]string{},fieldArgs...),"Budget.Limits.defaults()"),","))
        fmt.Fprintf(&out,"        public %s createWithoutValidation(%s) { return fromDataWithoutValidation(%s,caller); }\n",full,strings.Join(append(append([]string{},fieldParams...),"Budget.Limits caller"),","),raw)
    }
    fmt.Fprintf(&out,"        public %s read(String text) { return read(text,Budget.Limits.defaults()); }\n        public %s read(String text,Budget.Limits caller) { return new %s%s(%s); }\n",full,full,name,diamond,args("ModelSupport.read("+target+",text,caller)"))
    fmt.Fprintf(&out,"        public Validation.Outcome validateData(Data raw) { return validateData(raw,Budget.Limits.defaults()); }\n        public Validation.Outcome validateData(Data raw,Budget.Limits caller) { return %s.validateData(raw,caller); }\n    }\n",target)
    if parent==""&&record{out.WriteString(m.genericDraft(decl,fields))}
    out.WriteString("}\n");return out.String()
}

func (m *modelEmitter) genericDraft(decl language.TypeDecl,fields []modelField)string{
    types,parameters,arguments:=m.genericParts(decl);suffix:=genericSuffix(types);draftName:=m.modelDraftName();draft:=draftName+suffix;diamond:="";if suffix!=""{diamond="<>"}
    var out strings.Builder
    params:=append(append([]string{},parameters...),"Data baseline");args:=append(append([]string{},arguments...),"baseline")
    fmt.Fprintf(&out,"    protected static %s %s $newDraft(%s) { return new %s%s(%s); }\n",suffix,draft,strings.Join(params,","),draftName,diamond,strings.Join(args,","))
    fmt.Fprintf(&out,"    public static final class %s {\n        private final Data $baseline;\n",draft)
    for _,p:=range parameters{fmt.Fprintf(&out,"        private final %s;\n",p)}
    fmt.Fprintf(&out,"        private %s(%s) { this.$baseline=baseline;\n",draftName,strings.Join(params,","))
    for _,arg:=range arguments{fmt.Fprintf(&out,"            this.%s=java.util.Objects.requireNonNull(%s);\n",arg,arg)};out.WriteString("        }\n")
    for i,field:=range fields{fmt.Fprintf(&out,"        private %s %s;\n        private boolean $changed%d;\n        public void %s(%s value) { this.%s=value; this.$changed%d=true; }\n",m.javaType(field.typ),field.member,i,field.setter,m.javaType(field.typ),field.member,i)}
    out.WriteString("        Data freeze() { var changes=new java.util.LinkedHashMap<String,Data>();\n")
    for i:=0;i<len(fields);i+=64{fmt.Fprintf(&out,"            $fields%d(changes);\n",i/64)}
    out.WriteString("            return ModelSupport.applyChanges($baseline,changes);\n        }\n")
    for start:=0;start<len(fields);start+=64{
        fmt.Fprintf(&out,"        private void $fields%d(java.util.Map<String,Data> changes) {\n",start/64)
        for i:=start;i<min(start+64,len(fields));i++{field:=fields[i];location:="/"+strings.ReplaceAll(strings.ReplaceAll(field.name,"~","~0"),"/","~1");fmt.Fprintf(&out,"            if ($changed%d) changes.put(%s,%s);\n",i,javaQuote(field.name),m.encode(field.typ,"this."+field.member,javaQuote(location)))}
        out.WriteString("        }\n")
    }
    out.WriteString("    }\n");return out.String()
}
