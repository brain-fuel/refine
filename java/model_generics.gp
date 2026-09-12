package java

import (
    "fmt"
    "strings"

    "goforge.dev/refine/language"
)

// Generic roots own their witnesses and immutable data. Nominal generic parent
// substitutions and generic unions are separate, explicitly rejected gates.
func (m *modelEmitter) genericModel(decl language.TypeDecl)string{
    types,parameters,arguments:=m.genericParts(decl);suffix:=genericSuffix(types);name:=decl.Name;full:=name+suffix
    if len(parameters)>250{unsupported(decl.At,"generic model witness arity exceeds JVM method limits")}
    shape:=unrefined(decl.Body);fields:=[]modelField{};record:=false
    match shape.Form{case language.RecordType(_):record=true;fields=m.recordFields(name,shape);case _:m.javaType(shape)}
    join:=func(extra ...string)string{return strings.Join(append(append([]string{},parameters...),extra...),", ")}
    args:=func(extra ...string)string{return strings.Join(append(append([]string{},arguments...),extra...),", ")}
    target:="ModelTypes.for"+name+"("+args()+")"
    var out strings.Builder;fmt.Fprintf(&out,"public final class %s {\n    private final Data $raw;\n",full)
    for _,p:=range parameters{fmt.Fprintf(&out,"    private final %s;\n",p)}
    fmt.Fprintf(&out,"    private %s(%s) {\n        this.$raw = $raw;\n",name,join("Data $raw","boolean $checked"))
    for _,arg:=range arguments{fmt.Fprintf(&out,"        this.%s = java.util.Objects.requireNonNull(%s);\n",arg,arg)};out.WriteString("    }\n")
    ctorParams,ctorArgs:=[]string{},[]string{};raw:=""
    if record{for _,field:=range fields{ctorParams=append(ctorParams,m.javaType(field.typ)+" "+field.member);ctorArgs=append(ctorArgs,field.member)};raw=m.rawRecord(fields)}else{ctorParams=[]string{m.javaType(shape)+" value"};ctorArgs=[]string{"value"};raw=m.encode(shape,"value",`""`)}
    // Reserve this, caller and every explicit witness in the JVM slot count.
    if len(parameters)+len(ctorParams)<=253{
        fmt.Fprintf(&out,"    public %s(%s) { this(%s); }\n",name,join(ctorParams...),args(append(ctorArgs,"Budget.Limits.defaults()")...))
        fmt.Fprintf(&out,"    public %s(%s) { this(%s); }\n",name,join(append(ctorParams,"Budget.Limits caller")...),args("$require("+args(raw,"caller","true")+")","true"))
        fmt.Fprintf(&out,"    public static %s %s createWithoutValidation(%s) { return createWithoutValidation(%s); }\n",suffix,full,join(ctorParams...),args(append(ctorArgs,"Budget.Limits.defaults()")...))
        fmt.Fprintf(&out,"    public static %s %s createWithoutValidation(%s) { return fromDataWithoutValidation(%s); }\n",suffix,full,join(append(ctorParams,"Budget.Limits caller")...),args(raw,"caller"))
    }
    fmt.Fprintf(&out,"    private static %s Data $require(%s) { %s.modelValidate(%s.type,raw,caller,refinements).orThrow(); return raw; }\n",suffix,join("Data raw","Budget.Limits caller","boolean refinements"),m.contract,target)
    for _,bypass:=range []bool{false,true}{
        ending:="";check:="true";if bypass{ending="WithoutValidation";check="false"}
        fmt.Fprintf(&out,"    public static %s %s fromData%s(%s) { return fromData%s(%s); }\n",suffix,full,ending,join("Data raw"),ending,args("raw","Budget.Limits.defaults()"))
        fmt.Fprintf(&out,"    public static %s %s fromData%s(%s) { return new %s<>(%s); }\n",suffix,full,ending,join("Data raw","Budget.Limits caller"),name,args("$require("+args("raw","caller",check)+")","true"))
    }
    fmt.Fprintf(&out,"    public static %s %s read(%s) { return read(%s); }\n",suffix,full,join("String text"),args("text","Budget.Limits.defaults()"))
    fmt.Fprintf(&out,"    public static %s %s read(%s) { return new %s<>(%s); }\n",suffix,full,join("String text","Budget.Limits caller"),name,args(m.contract+".modelRead("+target+".type,text,caller).orThrow()","true"))
    fmt.Fprintf(&out,"    public static %s Validation.Outcome validateData(%s) { return validateData(%s); }\n",suffix,join("Data raw"),args("raw","Budget.Limits.defaults()"))
    fmt.Fprintf(&out,"    public static %s Validation.Outcome validateData(%s) { return %s.validateData(raw,caller); }\n",suffix,join("Data raw","Budget.Limits caller"),target)
    fmt.Fprintf(&out,"    public Validation.Outcome validate() { return validate(Budget.Limits.defaults()); }\n    public Validation.Outcome validate(Budget.Limits caller) { return validateData(%s); }\n",args("$raw","caller"))
    fmt.Fprintf(&out,"    public Data rawData() { return $raw; }\n    public String showWithoutValidation() { return showWithoutValidation(Budget.Limits.defaults()); }\n    public String showWithoutValidation(Budget.Limits caller) { return %s.showWithoutValidation($raw,caller); }\n",m.contract)
    if record{
        for _,field:=range fields{fmt.Fprintf(&out,"    public %s %s() { return %s; }\n",m.javaType(field.typ),field.member,m.decode(field.typ,"ModelSupport.field($raw,"+javaQuote(field.name)+")"))}
        draftName:=m.modelDraftName();draft:=draftName+suffix
        for _,bypass:=range []bool{false,true}{
            ending:="";if bypass{ending="WithoutValidation"}
            fmt.Fprintf(&out,"    public static %s %s create%s(%s) { return create%s(%s); }\n",suffix,full,ending,join("java.util.function.Consumer<"+draft+"> initialize"),ending,args("initialize","Budget.Limits.defaults()"))
            fmt.Fprintf(&out,"    public static %s %s create%s(%s) { var draft = new %s<>(%s); initialize.accept(draft); return fromData%s(%s); }\n",suffix,full,ending,join("java.util.function.Consumer<"+draft+"> initialize","Budget.Limits caller"),draftName,args("new Data.Struct(java.util.List.of())"),ending,args("draft.freeze()","caller"))
            fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change) { return update%s(change,Budget.Limits.defaults()); }\n",full,ending,draft,ending)
            fmt.Fprintf(&out,"    public %s update%s(java.util.function.Consumer<%s> change,Budget.Limits caller) { var draft = new %s<>(%s); change.accept(draft); return fromData%s(%s); }\n",full,ending,draft,draftName,args("$raw"),ending,args("draft.freeze()","caller"))
        }
        fmt.Fprintf(&out,"    public static final class %s {\n        private final Data $baseline;\n",draft)
        for _,p:=range parameters{fmt.Fprintf(&out,"        private final %s;\n",p)}
        fmt.Fprintf(&out,"        private %s(%s) { this.$baseline = baseline;\n",draftName,join("Data baseline"))
        for _,arg:=range arguments{fmt.Fprintf(&out,"            this.%s = java.util.Objects.requireNonNull(%s);\n",arg,arg)};out.WriteString("        }\n")
        for i,field:=range fields{fmt.Fprintf(&out,"        private %s %s;\n        private boolean $changed%d;\n        public void %s(%s value) { this.%s = value; this.$changed%d = true; }\n",m.javaType(field.typ),field.member,i,field.setter,m.javaType(field.typ),field.member,i)}
        out.WriteString("        private Data freeze() { var changes = new java.util.LinkedHashMap<String,Data>();\n")
        for i:=0;i<len(fields);i+=64{fmt.Fprintf(&out,"            $fields%d(changes);\n",i/64)}
        out.WriteString("            return ModelSupport.applyChanges($baseline,changes);\n        }\n")
        for start:=0;start<len(fields);start+=64{
            fmt.Fprintf(&out,"        private void $fields%d(java.util.Map<String,Data> changes) {\n",start/64)
            for i:=start;i<min(start+64,len(fields));i++{field:=fields[i];location:="/"+strings.ReplaceAll(strings.ReplaceAll(field.name,"~","~0"),"/","~1");fmt.Fprintf(&out,"            if ($changed%d) changes.put(%s,%s);\n",i,javaQuote(field.name),m.encode(field.typ,"this."+field.member,javaQuote(location)))}
            out.WriteString("        }\n")
        }
        out.WriteString("    }\n")
    }else{fmt.Fprintf(&out,"    public %s value() { return %s; }\n",m.javaType(shape),m.decode(shape,"$raw"))}
    out.WriteString("}\n");return out.String()
}
