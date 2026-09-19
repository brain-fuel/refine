package provenance

import (
    "encoding/json"
    "fmt"
    "strings"
    "sync"
    "testing"
    "testing/quick"

    oracle "github.com/santhosh-tekuri/jsonschema/v6"
    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func discover(t *testing.T,source string)*JSONSchema{t.Helper();s,err:=DiscoverJSONSchema([]byte(source),schemajson.Limits{});if err!=nil{t.Fatal(err)};return s}
func find(t *testing.T,s *JSONSchema,path string)Constraint{t.Helper();for _,c:=range s.Constraints(){if c.Pointer==path{return c}};t.Fatalf("missing constraint %s",path);return Constraint{}}

func TestNativeBoundCanonicalForms(t *testing.T){
    for _,tc:=range []struct{typ string;key string;bound string;predicate string}{
        {"integer","minimum","0","(it >= 0)"},
        {"integer","maximum","9007199254740993","(it <= 9007199254740993)"},
        {"integer","exclusiveMinimum","1.1","((it / 1) > 1.1)"},
        {"integer","exclusiveMaximum","-1.1","((it / 1) < (-1.1))"},
        {"integer","minimum","0.00","((it / 1) >= 0.00)"},
        {"number","minimum","1","(it >= (1 / 1))"},
        {"number","maximum","-1","(it <= ((-1) / 1))"},
        {"number","maximum","1e+20","(it <= 1e+20)"},
        {"number","exclusiveMinimum","-0.0","(it > (-0.0))"},
        {"integer","multipleOf","2","(isInteger (it / 2))"},
        {"integer","multipleOf","1.5","(isInteger ((it / 1) / 1.5))"},
        {"number","multipleOf","2","(isInteger (it / (2 / 1)))"},
        {"number","multipleOf","0.1","(isInteger (it / 0.1))"},
    }{t.Run(tc.typ+"/"+tc.key+"/"+tc.bound,func(t *testing.T){
        raw:=fmt.Sprintf(` { "type":%q, %q:%s, "description":"keep me" } `,tc.typ,tc.key,tc.bound)
        s:=discover(t,raw);cs:=s.Constraints();if len(cs)!=1{t.Fatalf("%+v",cs)};c:=cs[0]
        if c.Predicate!=tc.predicate||c.Native!=tc.bound||c.Pointer!="/"+tc.key{t.Fatalf("%+v",c)}
        recovered,err:=s.RecoverNative(c.Name,s.ConstraintSource());if err!=nil||recovered!=tc.bound{t.Fatalf("native recovery: %s %v",recovered,err)}
        if s.Original()!=raw{t.Fatal("lost native source bytes")}
    })}
}

func TestPerConstraintDeviationIsolation(t *testing.T){
    raw:=`{"type":"integer","minimum":0.00,"maximum":100,"x-arbitrary":{"minimum":999},"description":"native text"}`
    s:=discover(t,raw);minimum,maximum:=find(t,s,"/minimum"),find(t,s,"/maximum")
    if len(s.Constraints())!=2{t.Fatal("annotation was mistaken for a schema")}
    original:=s.ConstraintSource()
    edited:=strings.Replace(original,minimum.Predicate,"(it > 0)",1)
    findings,err:=s.AuditSource(edited);if err!=nil{t.Fatal(err)}
    if StatusName(findings[0].Status)!="changed"||StatusName(findings[1].Status)!="unchanged"{t.Fatalf("%+v",findings)}
    if _,err:=s.RecoverNative(minimum.Name,edited);err==nil||err.(*Error).Code!="native.bijection_changed"{t.Fatal("edited minimum claimed original bijection")}
    got,err:=s.RecoverNative(maximum.Name,edited);if err!=nil||got!="100"{t.Fatal("editing minimum invalidated maximum")}
    if s.Original()!=raw{t.Fatal("audit changed original")}
    // A logically equivalent rewrite is intentionally outside the guarantee.
    equivalent:=strings.Replace(original,maximum.Predicate,"not (it > 100)",1)
    if _,err:=s.RecoverNative(maximum.Name,equivalent);err==nil{t.Fatal("arbitrary equivalence treated as canonical")}
    // New arbitrary rules/functions have no pre-existing native guarantee to lose.
    extra:=original+"\nodd :: Int -> Bool\nodd n = n % 2 /= 0\ntype Extra = Int where odd it\n"
    extra=strings.Replace(extra,minimum.Predicate,minimum.Predicate+" where odd it",1)
    findings,err=s.AuditSource(extra);if err!=nil{t.Fatal(err)}
    for _,finding:=range findings{if StatusName(finding.Status)!="unchanged"{t.Fatal("additional refinement broke unrelated native guarantee")}}
    // The normal formatter is layout-only and does not cause a deviation.
    parsed,err:=language.Parse(extra);if err!=nil{t.Fatal(err)}
    if _,err:=s.RecoverNative(minimum.Name,language.Format(parsed));err!=nil{t.Fatal(err)}
    for _,source:=range []string{"",strings.Replace(original,"type "+minimum.Name+" = Int where "+minimum.Predicate+"\n","",1)}{
        findings,err:=s.AuditSource(source);if err!=nil{t.Fatal(err)};if StatusName(findings[0].Status)!="removed"{t.Fatal("removed declaration retained its guarantee")}
    }
    if _,err:=s.AuditSource(strings.Replace(original,minimum.Predicate,"123",1));err==nil{t.Fatal("non-Boolean edited rule accepted")}
    if _,err:=s.RecoverNative("unknown",original);err==nil{t.Fatal("forged origin recovered")}
}

func TestSchemaPositionTraversalAndNativeRetention(t *testing.T){
    raw:=`{
      "$schema":"https://json-schema.org/draft/2020-12/schema",
      "$defs":{"a/b~c":{"type":"integer","minimum":1}},
      "not":{"type":"number","exclusiveMaximum":2.0},
      "if":{"type":["integer"],"maximum":3},
      "allOf":[{"type":"integer","minimum":4}],
      "prefixItems":[{"type":"integer","minimum":5}],
      "properties":{"number":{"type":"integer","minimum":6},"text":{"type":"string","minLength":2,"pattern":"(?=x)x"}},
      "examples":[{"type":"integer","minimum":700}],
      "default":{"type":"integer","minimum":800},
      "const":{"type":"integer","minimum":900},
      "x-extension":{"type":"integer","minimum":1000}
    }`
    s:=discover(t,raw)
    if len(s.Constraints())!=7{t.Fatalf("wrong schema traversal: %+v",s.Constraints())}
    if find(t,s,"/const").Native!=`{"type":"integer","minimum":900}`{t.Fatal("const value was not retained as one opaque value")}
    for _,constraint:=range s.Constraints(){if strings.HasPrefix(constraint.Pointer,"/const/"){t.Fatal("const payload was traversed as a schema")}}
    c:=find(t,s,"/$defs/a~1b~0c/minimum");if c.SchemaPointer!="/$defs/a~1b~0c"{t.Fatal("lost escaped schema context")}
    if find(t,s,"/not/exclusiveMaximum").SchemaPointer!="/not"{t.Fatal("lost negated applicator context")}
    if s.Original()!=raw{t.Fatal("untranslated native clauses were changed")}
    for _,raw:=range []string{`true`,`false`,`{"minimum":0}`,`{"type":["integer","null"],"minimum":0}`,`{"type":"string","minimum":0}`,`{"$ref":"external.json"}`} {
        if s:=discover(t,raw);len(s.Constraints())!=0||s.Original()!=raw{t.Fatal("invented numeric type or resolved external reference")}
    }
    for _,tc:=range []struct{raw string;code string}{
        {`[]`,"native.schema_position"},{`{"minimum":"0"}`,"native.bound"},
        {`{"type":"integer","minimum":0,"minimum":1}`,"json.duplicate-key"},
        {`{"$schema":"http://json-schema.org/draft-07/schema#"}`,"native.dialect"},
        {`{"$defs":{"x":{"$schema":"http://json-schema.org/draft-07/schema#"}}}`,"native.dialect"},
        {`{"allOf":{}}`,"native.schema_array"},{`{"properties":[]}`,"native.schema_map"},
        {`{"items":3}`,"native.schema_position"},{`{"properties":{"\ud800":true}}`,"native.pointer_encoding"},
        {`{"multipleOf":0}`,"native.multiple"},{`{"multipleOf":-1}`,"native.multiple"},
        {`{"multipleOf":0.000e+999999999}`,"native.multiple"},{`{"multipleOf":-0.0}`,"native.multiple"},
    }{_,err:=DiscoverJSONSchema([]byte(tc.raw),schemajson.Limits{});if err==nil||!strings.Contains(err.Error(),tc.code){t.Fatalf("%s: %v",tc.raw,err)}}
}

func TestBuiltinShadowingInvalidatesOnlyDependentOrigins(t *testing.T){
    s:=discover(t,`{"type":"number","minimum":0,"multipleOf":0.1}`)
    minimum,multiple:=find(t,s,"/minimum"),find(t,s,"/multipleOf")
    source:=s.ConstraintSource()+"\nisInteger :: Real -> Bool\nisInteger _ = True\n"
    findings,err:=s.AuditSource(source);if err!=nil{t.Fatal(err)}
    if StatusName(findings[0].Status)!="unchanged"||StatusName(findings[1].Status)!="changed"{t.Fatal("shadowed native helper kept a false guarantee")}
    if _,err:=s.RecoverNative(multiple.Name,source);err==nil{t.Fatal("recovered under changed predicate binding")}
    if _,err:=s.RecoverNative(minimum.Name,source);err!=nil{t.Fatal("shadowing unrelated helper invalidated minimum")}
    findings[1].Constraint.Builtins[0]="forged"
    cs:=s.Constraints();cs[1].Builtins[0]="forged"
    if s.Constraints()[1].Builtins[0]!="isInteger"{t.Fatal("mutable binding metadata escaped")}
}

func TestConstraintSourceIsolationAndIdentity(t *testing.T){
    raw:=[]byte(`{"type":"integer","minimum":1,"maximum":10}`)
    s,err:=DiscoverJSONSchema(raw,schemajson.Limits{});if err!=nil{t.Fatal(err)};raw[0]='x'
    original:=s.ConstraintSource();cs:=s.Constraints();cs[0].Predicate="False";cs[0].Native="999"
    if s.ConstraintSource()!=original||s.Constraints()[0].Native!="1"{t.Fatal("mutable provenance escaped")}
    changed:=discover(t,`{"type":"integer","minimum":2,"maximum":10}`)
    for i,c:=range s.Constraints(){other:=changed.Constraints()[i];if c.Name!=other.Name{t.Fatal("identity depends on edited native value")};if (c.Fingerprint==other.Fingerprint)!=(c.Keyword=="maximum"){t.Fatal("fingerprint granularity is not per constraint")}}
    var group sync.WaitGroup
    for i:=0;i<8;i++{group.Add(1);go func(){defer group.Done();for j:=0;j<10;j++{if _,err:=s.AuditSource(original);err!=nil{t.Error(err)}}}()};group.Wait()
}

// Native oracle is a pinned ecosystem implementation, used only by tests. The
// production provenance package cannot claim its projection is full validation.
func nativeOracle(t *testing.T,raw string)*oracle.Schema{
    t.Helper();doc,err:=oracle.UnmarshalJSON(strings.NewReader(raw));if err!=nil{t.Fatal(err)}
    compiler:=oracle.NewCompiler();compiler.DefaultDraft(oracle.Draft2020)
    if err:=compiler.AddResource("https://refine.invalid/schema",doc);err!=nil{t.Fatal(err)}
    schema,err:=compiler.Compile("https://refine.invalid/schema");if err!=nil{t.Fatal(err)};return schema
}

func TestNativeBoundSemanticProperties(t *testing.T){
    property:=func(bound int16,scale uint8,n int16,kind uint8)bool{
        typ:="integer";if kind%2==1{typ="number"}
        keyword:=[]string{"minimum","maximum","exclusiveMinimum","exclusiveMaximum","multipleOf"}[int(kind/2)%5]
        rawBound:=fmt.Sprintf("%d.%0*d",bound,int(scale%4)+1,1)
        if keyword=="multipleOf"{rawBound=strings.TrimPrefix(rawBound,"-")}
        raw:=fmt.Sprintf(`{"type":%q,%q:%s}`,typ,keyword,rawBound)
        native:=nativeOracle(t,raw);s:=discover(t,raw)
        program,err:=language.Compile(s.ConstraintSource());if err!=nil{t.Fatal(err)}
        payload:=fmt.Sprint(n);if typ=="number"{payload+=".125"}
        number,err:=value.ParseNumber(payload);if err!=nil{t.Fatal(err)}
        actual:=program.ValidateData(s.Constraints()[0].Name,value.OfNumber(number),validation.Limits{})
        expected:=native.Validate(json.Number(payload))==nil
        state:=validation.StateName(actual.State())
        if state=="indeterminate"||expected!=(state=="valid"){t.Fatalf("native %s payload %s: %s vs %v",raw,payload,state,expected)}
        recovered,err:=s.RecoverNative(s.Constraints()[0].Name,s.ConstraintSource())
        return err==nil&&recovered==rawBound
    }
    if err:=quick.Check(property,&quick.Config{MaxCount:1000});err!=nil{t.Fatal(err)}
}

func TestExactFractionalMultiples(t *testing.T){
    for _,tc:=range []struct{typ string;bound string;payload string;valid bool}{
        {"number","0.1","0.3",true},{"number","0.1","0.31",false},
        {"number","0.1","-0.3",true},{"number","1e-30","3e-30",true},
        {"integer","1.5","3",true},{"integer","1.5","1",false},
        {"integer","1.5","-3",true},{"integer","1.5","0",true},
        {"integer","9007199254740993","9007199254740993",true},
        {"integer","9007199254740993","9007199254740992",false},
    }{
        raw:=fmt.Sprintf(`{"type":%q,"multipleOf":%s}`,tc.typ,tc.bound)
        native:=nativeOracle(t,raw);s:=discover(t,raw);p,err:=language.Compile(s.ConstraintSource());if err!=nil{t.Fatal(err)}
        n,err:=value.ParseNumber(tc.payload);if err!=nil{t.Fatal(err)}
        report:=p.ValidateData(s.Constraints()[0].Name,value.OfNumber(n),validation.Limits{})
        state:=validation.StateName(report.State())
        if state=="indeterminate"||(state=="valid")!=tc.valid||(native.Validate(json.Number(tc.payload))==nil)!=tc.valid{t.Fatalf("%s payload %s: %+v",raw,tc.payload,report.Diagnostics())}
    }
}

func FuzzNativeConstraintRoundTrip(f *testing.F){
    for _,raw:=range []string{`{"type":"integer","minimum":0}`,`{"type":"number","maximum":1e20}`,`{"allOf":[{"type":"integer","minimum":-0.5}]}`,`{"properties":{"a/b~":{"type":"integer","minimum":3}}}`,`{"type":"number","multipleOf":0.1}`,`{"const":{"b":[1,true],"a":null}}`,`{"enum":[]}`,`{"enum":[1,1.0,"e\u0301"]}`}{f.Add(raw)}
    f.Fuzz(func(t *testing.T,raw string){
        if len(raw)>2000{t.Skip()};s,err:=DiscoverJSONSchema([]byte(raw),schemajson.Limits{Depth:30,Nodes:1000});if err!=nil{return}
        if s.Original()!=raw{t.Fatal("native source not preserved")}
        source:=s.ConstraintSource();findings,err:=s.AuditSource(source);if err!=nil{t.Fatal(err)}
        again,err:=DiscoverJSONSchema([]byte(s.Original()),schemajson.Limits{Depth:30,Nodes:1000});if err!=nil||again.ConstraintSource()!=source{t.Fatal("nondeterministic projection")}
        for _,finding:=range findings{if StatusName(finding.Status)!="unchanged"{t.Fatal("round trip changed provenance")};back,err:=s.RecoverNative(finding.Constraint.Name,source);if err!=nil||back!=finding.Constraint.Native{t.Fatal("canonical-to-native recovery failed")}}
    })
}
