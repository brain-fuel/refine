package provenance

import (
    "strings"
    "testing"

    "goforge.dev/refine/language"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func dependentRequiredOrigin(t *testing.T,raw string,includeCardinality bool)*JSONSchema{
    t.Helper();document,err:=schemajson.Parse([]byte(raw),schemajson.Limits{});if err!=nil{t.Fatal(err)};root:=document.Root();origin:=&JSONSchema{document:document,maxValueNodes:1000000,maxValueDepth:508}
    if includeCardinality{count,ok:=root.Lookup("minProperties");if !ok{t.Fatal("missing minProperties")};if _,err:=origin.cardinalityConstraint(root,"","minProperties",count);err!=nil{t.Fatal(err)}}
    keyword,ok:=root.Lookup("dependentRequired");if !ok{t.Fatal("missing dependentRequired")};handled,err:=origin.dependentRequiredConstraint(root,"","dependentRequired",keyword);if err!=nil{t.Fatal(err)};if !handled{t.Fatal("dependentRequired was not handled")};return origin
}

func dependentRequiredMap(t *testing.T,entries ...value.MapEntry)value.Data{t.Helper();mapping,err:=value.Map(entries);if err!=nil{t.Fatal(err)};return mapping}

func TestDependentRequiredPureDiscoveryInverseAndOracle(t *testing.T){
    raw:=`{"type":"object","dependentRequired":{"credit_card":["postal","billing_address"],"\u0065mpty":[]}}`;origin:=dependentRequiredOrigin(t,raw,false);constraints:=origin.Constraints();if len(constraints)!=1{t.Fatalf("constraints: %+v",constraints)};constraint:=constraints[0]
    if constraint.Keyword!="dependentRequired"||constraint.Scope!="((Map String) JSON)"||constraint.Pointer!="/dependentRequired"||constraint.Native!=`{"credit_card":["postal","billing_address"],"\u0065mpty":[]}`||len(constraint.Builtins)!=1||constraint.Builtins[0]!="member"{t.Fatalf("constraint: %+v",constraint)}
    source:=origin.ConstraintSource();program,err:=language.Compile(source);if err!=nil{t.Fatal(err)};if recovered,err:=origin.RecoverNative(constraint.Name,source);err!=nil||recovered!=constraint.Native{t.Fatalf("exact recovery: %q %v",recovered,err)}
    if lowered,err:=LowerDependentRequiredConstraint(program,constraint);err!=nil||lowered!=`{"credit_card":["billing_address","postal"],"empty":[]}`{t.Fatalf("canonical inverse: %q %v",lowered,err)}
    oracle:=nativeOracle(t,raw);cases:=[]struct{name string;native any;data value.Data;valid bool}{
        {"absent",map[string]any{},dependentRequiredMap(t),true},
        {"present-null-missing",map[string]any{"credit_card":nil},dependentRequiredMap(t,jsonEntry(t,"credit_card",jsonNullData(t))),false},
        {"dependencies-null-and-extra",map[string]any{"credit_card":nil,"billing_address":nil,"postal":nil,"extra":nil},dependentRequiredMap(t,jsonEntry(t,"extra",jsonNullData(t)),jsonEntry(t,"postal",jsonNullData(t)),jsonEntry(t,"credit_card",jsonNullData(t)),jsonEntry(t,"billing_address",jsonNullData(t))),true},
        {"decoded-trigger",map[string]any{"empty":nil},dependentRequiredMap(t,jsonEntry(t,"empty",jsonNullData(t))),true},
    }
    for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){nativeValid:=oracle.Validate(tc.native)==nil;report:=program.ValidateData(constraint.Name,tc.data,validation.Limits{});actual:=validation.StateName(report.State())=="valid";if nativeValid!=tc.valid||actual!=tc.valid{t.Fatalf("native=%v refine=%s diagnostics=%+v",nativeValid,validation.StateName(report.State()),report.Diagnostics())}})}
    editedRaw:=`{"credit_card":["billing_address","country","postal"],"empty":[]}`;editedDocument,err:=schemajson.Parse([]byte(editedRaw),schemajson.Limits{});if err!=nil{t.Fatal(err)};editedPredicate,ok,err:=dependentRequiredProjection(editedDocument.Root(),schemajson.DefaultNodes,maxJSONValueSourceBytes);if err!=nil||!ok{t.Fatalf("edited projection: %q %v",editedPredicate,err)};editedSource:=strings.Replace(source,constraint.Predicate,editedPredicate,1);editedProgram,err:=language.Compile(editedSource);if err!=nil{t.Fatal(err)};if lowered,err:=LowerDependentRequiredConstraint(editedProgram,constraint);err!=nil||lowered!=editedRaw{t.Fatalf("edited inverse: %q %v",lowered,err)}
}

func TestDependentRequiredIsolationShadowingAndBounds(t *testing.T){
    origin:=dependentRequiredOrigin(t,`{"type":"object","minProperties":1,"dependentRequired":{"a":["b"],"c":[]}}`,true);if len(origin.Constraints())!=2{t.Fatalf("constraints: %+v",origin.Constraints())};dependent:=origin.Constraints()[1];source:=origin.ConstraintSource()
    shadowed:=source+"\nmember :: String -> Map String JSON -> Bool\nmember _ _ = True\n";findings,err:=origin.AuditSource(shadowed);if err!=nil{t.Fatal(err)};for _,finding:=range findings{want:="unchanged";if finding.Constraint.Keyword=="dependentRequired"{want="changed"};if StatusName(finding.Status)!=want{t.Fatalf("shadowing leaked across constraints: %+v",finding)}};program,err:=language.Compile(shadowed);if err!=nil{t.Fatal(err)};untrusted:=dependent;untrusted.Builtins=nil;untrusted.Scope="JSON";if _,err:=LowerDependentRequiredConstraint(program,untrusted);err==nil{t.Fatal("caller-mutated constraint disabled member shadow guard")}
    removed:=strings.Replace(source,"type "+dependent.Name+" = "+dependent.Scope+" where "+dependent.Predicate+"\n","",1);findings,err=origin.AuditSource(removed);if err!=nil{t.Fatal(err)};for _,finding:=range findings{if finding.Constraint.Keyword=="dependentRequired"&&StatusName(finding.Status)!="removed"{t.Fatalf("removed unit retained authority: %+v",finding)};if finding.Constraint.Keyword=="minProperties"{if StatusName(finding.Status)!="unchanged"{t.Fatalf("adjacent cardinality changed: %+v",finding)};if got,err:=origin.RecoverNative(finding.Constraint.Name,removed);err!=nil||got!="1"{t.Fatalf("adjacent cardinality recovery: %q %v",got,err)}}}
    malformed:=strings.Replace(source,dependent.Predicate,`member "a" it`,1);program,err=language.Compile(malformed);if err!=nil{t.Fatal(err)};if _,err:=LowerDependentRequiredConstraint(program,dependent);err==nil{t.Fatal("noncanonical predicate lowered")}
    a,_:=value.TextFromUTF8("a");b,_:=value.TextFromUTF8("b");c,_:=value.TextFromUTF8("c");unsortedPredicate:=language.FormatExpression(dependentRequiredExpression([]dependentRequiredEntry{{trigger:c},{trigger:a,required:[]value.Text{b}}}));unsorted:=strings.Replace(source,dependent.Predicate,unsortedPredicate,1);program,err=language.Compile(unsorted);if err!=nil{t.Fatal(err)};if _,err:=LowerDependentRequiredConstraint(program,dependent);err==nil{t.Fatal("noncanonical UTF-16 order lowered")}
    invalid:=[]string{`[]`,`{"a":true}`,`{"a":[1]}`,`{"a":["b","b"]}`};for _,raw:=range invalid{document,err:=schemajson.Parse([]byte(raw),schemajson.Limits{});if err!=nil{t.Fatal(err)};if _,_,err:=dependentRequiredProjection(document.Root(),schemajson.DefaultNodes,maxJSONValueSourceBytes);err==nil||!strings.Contains(err.Error(),"native.dependent_required"){t.Fatalf("invalid %s: %v",raw,err)}}
    for _,raw:=range []string{`{"dependentRequired":{"a":["b"]}}`,`{"type":["object","null"],"dependentRequired":{"a":["b"]}}`,`{"type":"string","dependentRequired":{"a":["b"]}}`}{opaque:=dependentRequiredOrigin(t,raw,false);if len(opaque.Constraints())!=0||opaque.Original()!=raw{t.Fatalf("non-singleton object acquired authority: %s %+v",raw,opaque.Constraints())}}
    document,err:=schemajson.Parse([]byte(`{"long-trigger":["first","second"],"other":[]}`),schemajson.Limits{});if err!=nil{t.Fatal(err)};for _,limits:=range []struct{work int;source int}{{3,maxJSONValueSourceBytes},{schemajson.DefaultNodes,40}}{predicate,projectable,err:=dependentRequiredProjection(document.Root(),limits.work,limits.source);if err!=nil||projectable||predicate!=""{t.Fatalf("bounded projection leaked partial output: %q %v %v",predicate,projectable,err)}}
    emptyDocument,err:=schemajson.Parse([]byte(`{}`),schemajson.Limits{});if err!=nil{t.Fatal(err)};predicate,projectable,err:=dependentRequiredProjection(emptyDocument.Root(),1,64);if err!=nil||!projectable||predicate!="True"{t.Fatalf("empty keyword semantics: %q %v %v",predicate,projectable,err)}
    used:=uint64(0);if chargeDependentRequiredOrdering(2,10,&used,85)||used!=0{t.Fatal("failed ordering preflight consumed budget")};if !chargeDependentRequiredOrdering(2,10,&used,86)||used!=86{t.Fatalf("exact ordering bound rejected: %d",used)}
    if dependentRequiredTextSourceSize("a")!=3||dependentRequiredTextSourceSize("\"")!=4||dependentRequiredTextSourceSize("é")!=8||dependentRequiredTextSourceSize("😀")!=14{t.Fatal("canonical text source size changed")}
}

func TestDependentRequiredPublicJSONSchemaDiscoveryMatchesOracle(t *testing.T){
    raw:=`{"type":"object","dependentRequired":{"kind":["payload"]}}`;origin,err:=DiscoverJSONSchema([]byte(raw),schemajson.Limits{});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=1{t.Fatalf("constraints: %+v",constraints)};constraint:=constraints[0];program,err:=language.Compile(origin.ConstraintSource());if err!=nil{t.Fatal(err)};oracle:=nativeOracle(t,raw)
    cases:=[]struct{native map[string]any;data value.Data}{
        {map[string]any{},dependentRequiredMap(t)},
        {map[string]any{"kind":nil},dependentRequiredMap(t,jsonEntry(t,"kind",jsonNullData(t)))},
        {map[string]any{"kind":nil,"payload":nil},dependentRequiredMap(t,jsonEntry(t,"payload",jsonNullData(t)),jsonEntry(t,"kind",jsonNullData(t)))},
    };for _,tc:=range cases{expected:=oracle.Validate(tc.native)==nil;actual:=validation.StateName(program.ValidateData(constraint.Name,tc.data,validation.Limits{}).State())=="valid";if actual!=expected{t.Fatalf("oracle mismatch for %+v: refine=%v native=%v",tc.native,actual,expected)}}
    if got,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||got!=`{"kind":["payload"]}`{t.Fatalf("public exact recovery: %q %v",got,err)}
    for _,invalid:=range []string{`{"type":"object","dependentRequired":[]}`,`{"type":"object","dependentRequired":{"kind":[1]}}`}{if _,err:=DiscoverJSONSchema([]byte(invalid),schemajson.Limits{});err==nil||!strings.Contains(err.Error(),"native.dependent_required"){t.Fatalf("invalid public keyword %s: %v",invalid,err)}}
}

func TestDependentRequiredOpenAPIJSONActualPositionsAndRecovery(t *testing.T){
    uri:="https://example.test/dependent.json";source:=`{"openapi":"3.1.2","info":{"title":"Dependent","version":"1"},"paths":{"/items":{"post":{"requestBody":{"content":{"application/json":{"schema":{"type":"object","dependentRequired":{"mode":["payload"]}}}}},"responses":{"204":{"description":"none"}}}}},"components":{"schemas":{"Envelope":{"type":"object","dependentRequired":{"credit_card":["billing_address"],"\u0065mpty":[]}}}},"x-example":{"type":"object","dependentRequired":{"ignored":["value"]}}}`
    origin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:uri,Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(source)}},OpenAPIOptions{EntryResource:uri});if err!=nil{t.Fatal(err)};constraints:=origin.Constraints();if len(constraints)!=2{t.Fatalf("actual Schema Object positions: %+v",constraints)};expected:=map[string]string{
        "/components/schemas/Envelope/dependentRequired":`{"credit_card":["billing_address"],"\u0065mpty":[]}`,
        "/paths/~1items/post/requestBody/content/application~1json/schema/dependentRequired":`{"mode":["payload"]}`,
    };for _,constraint:=range constraints{native,ok:=expected[constraint.Pointer];if !ok||constraint.Keyword!="dependentRequired"||constraint.Scope!="((Map String) JSON)"{t.Fatalf("unexpected constraint: %+v",constraint)};if got,err:=origin.RecoverNative(constraint.Name,origin.ConstraintSource());err!=nil||got!=native{t.Fatalf("%s exact recovery: %q %v",constraint.Pointer,got,err)}}
    yamlSource:="openapi: 3.1.2\ninfo: {title: Dependent, version: '1'}\npaths: {}\ncomponents:\n  schemas:\n    Envelope:\n      type: object\n      dependentRequired: {kind: [payload]}\n";yamlOrigin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:uri,Syntax:OpenAPIYAML,Role:OpenAPIDocument,Source:[]byte(yamlSource)}},OpenAPIOptions{EntryResource:uri});if err!=nil{t.Fatal(err)};if len(yamlOrigin.Constraints())!=0{t.Fatalf("YAML keyword acquired unsupported lexical recovery: %+v",yamlOrigin.Constraints())}
    oas30:=strings.Replace(source,"3.1.2","3.0.4",1);oldOrigin,err:=DiscoverOpenAPI([]OpenAPIResource{{URI:uri,Syntax:OpenAPIJSON,Role:OpenAPIDocument,Source:[]byte(oas30)}},OpenAPIOptions{EntryResource:uri});if err!=nil{t.Fatal(err)};if len(oldOrigin.Constraints())!=0{t.Fatalf("OpenAPI 3.0 acquired unsupported dependentRequired authority: %+v",oldOrigin.Constraints())}
}
