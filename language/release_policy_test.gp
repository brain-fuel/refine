package language

import (
    "bytes"
    "reflect"
    "strings"
    "testing"
)

func testReleasePolicy(reason string) *ReleasePolicy {
    comparison := ReleaseComparison{Baseline:"1.2.3", BaselineSHA256:strings.Repeat("a",64), SnapshotSHA256:strings.Repeat("b",64), Direction:"backward"}
    return &ReleasePolicy{Version:1, Overrides:[]CompatibilityApproval{{ReleaseComparison:comparison,Reason:reason}}, BreakingFixes:[]BreakingFixApproval{{ReleaseComparison:comparison,Justification:"correct an invalid published constraint"}}}
}

func TestReleasePolicyStrictJSON(t *testing.T) {
    raw, err := FormatReleasePolicyJSON(testReleasePolicy("reviewed α")); if err != nil { t.Fatal(err) }
    policy, err := ParseReleasePolicyJSON(raw); if err != nil { t.Fatal(err) }
    again, err := FormatReleasePolicyJSON(policy); if err != nil || !bytes.Equal(raw,again) { t.Fatalf("canonical round trip: %s %v",again,err) }
    tests := []struct{name string; input string}{
        {"null","null"}, {"missing-version","{}"}, {"float-version",`{"version":1.0}`}, {"future-version",`{"version":2}`},
        {"unknown",`{"version":1,"future":true}`}, {"wrong-case",`{"Version":1}`}, {"null-array",`{"version":1,"overrides":null}`},
        {"duplicate-key",`{"version":1,"version":1}`}, {"escaped-duplicate-key",`{"version":1,"\u0076ersion":1}`},
        {"baseline-prefix",strings.Replace(string(raw),`"1.2.3"`,`"v1.2.3"`,1)},
        {"baseline-leading-zero",strings.Replace(string(raw),`"1.2.3"`,`"1.02.3"`,1)},
        {"digest-uppercase",strings.Replace(string(raw),strings.Repeat("a",64),strings.Repeat("A",64),1)},
        {"direction",strings.Replace(string(raw),`"backward"`,`"both"`,1)},
        {"blank-reason",strings.Replace(string(raw),`"reviewed α"`,`"  "`,1)},
        {"null-reason",strings.Replace(string(raw),`"reviewed α"`,`null`,1)},
        {"unpaired-surrogate",strings.Replace(string(raw),`"reviewed α"`,`"\ud800"`,1)},
        {"unknown-record-key",strings.Replace(string(raw),`"reason":`,`"Reason":`,1)},
        {"oversized",strings.Repeat(" ",releasePolicyBytes+1)},
    }
    for _, test := range tests { t.Run(test.name,func(t *testing.T){ if _,err:=ParseReleasePolicyJSON([]byte(test.input));err==nil{t.Fatal("invalid policy accepted")} }) }
    duplicate := testReleasePolicy("reviewed"); duplicate.Overrides=append(duplicate.Overrides,duplicate.Overrides[0])
    if _,err:=FormatReleasePolicyJSON(duplicate);err==nil{t.Fatal("duplicate record accepted")}
    huge:=testReleasePolicy(strings.Repeat("x",releasePolicyExplanationBytes+1));if _,err:=FormatReleasePolicyJSON(huge);err==nil{t.Fatal("unbounded reason accepted")}
    invalid:=testReleasePolicy(string([]byte{0xff}));if _,err:=FormatReleasePolicyJSON(invalid);err==nil{t.Fatal("invalid UTF-8 silently replaced")}
    tooMany:=&ReleasePolicy{Version:1,Overrides:make([]CompatibilityApproval,releasePolicyRecords+1)};if _,err:=FormatReleasePolicyJSON(tooMany);err==nil{t.Fatal("record cap ignored")}
}

func TestReleasePolicyFooterPreservesContractBytesAndSpans(t *testing.T) {
    for _, base := range []string{"type Age = Int where it >= 0", "type Age = Int where it >= 0\n", "-- retained\r\ntype Age = Int where it >= 0\r\n", "type Age = Int where it >= 0 -- retained comment"} {
        source,err:=AppendReleasePolicyFooter(base,testReleasePolicy("reviewed \"text\"\nnext line"));if err!=nil{t.Fatal(err)}
        restored,policy,present,err:=SplitReleasePolicyFooter(source);if err!=nil||!present||restored!=base||policy.Overrides[0].Reason!="reviewed \"text\"\nnext line"{t.Fatalf("exact restoration failed: %q %v",restored,err)}
        original,err:=Compile(base);if err!=nil{t.Fatal(err)};compiled,err:=Compile(source);if err!=nil{t.Fatal(err)}
        if original.Syntax().Types[0].At!=compiled.Syntax().Types[0].At{t.Fatal("declaration spans moved")}
        if !reflect.DeepEqual(original.Syntax().Types,compiled.Syntax().Types){t.Fatal("contract syntax or nested rule spans changed")}
        before:=original.Syntax().Types[0].Body;after:=compiled.Syntax().Types[0].Body
        if before.At!=after.At{t.Fatal("type spans moved")}
        if compiled.Source()!=source{t.Fatal("original source not retained")}
        detached:=compiled.ReleasePolicy();detached.Overrides[0].Reason="mutated";detached.BreakingFixes[0].Justification="mutated"
        if compiled.ReleasePolicy().Overrides[0].Reason=="mutated"||compiled.ReleasePolicy().BreakingFixes[0].Justification=="mutated"{t.Fatal("policy aliases checked state")}
        formatted:=compiled.Formatted();parsed,err:=Parse(formatted);if err!=nil||Format(parsed)!=formatted{t.Fatalf("unstable formatting: %v",err)}
        if _,err:=AppendReleasePolicyFooter(source,testReleasePolicy("duplicate"));err==nil{t.Fatal("replaced existing footer")}
    }
}

func TestReleasePolicyFooterCannotHideInCommentsOrMoveBeforeContract(t *testing.T) {
    fake:=`@releasePolicy "not JSON"`
    for _,source:=range []string{"type X = Int\n-- "+fake+"\n", "type X = Int\n{-\n"+fake+"\n-}\n", "type X = Int\n{- outer {-\n"+fake+"\n-} -}\n"} {
        base,policy,present,err:=SplitReleasePolicyFooter(source);if err!=nil||present||policy!=nil||base!=source{t.Fatalf("comment acquired authority: %v",err)}
        if _,err:=Compile(source);err!=nil{t.Fatal(err)}
    }
    source,err:=AppendReleasePolicyFooter("type X = Int\n",testReleasePolicy("reviewed"));if err!=nil{t.Fatal(err)}
    footer:=source[strings.Index(source,"@releasePolicy"):]
    for _,invalid:=range []string{source+"\n",source+"-- comment\n",source+"type Y = Int\n",footer+"type X = Int\n", "type X = Int\n "+footer, "type X = Int\n"+strings.Replace(footer,"@releasePolicy ","@releasePolicy  ",1), strings.TrimSuffix(source,"\n"), source+footer} {
        if _,err:=Parse(invalid);err==nil{t.Fatalf("invalid footer accepted: %q",invalid)}
    }
}

func TestReleasePolicyImportsKeepOnlyEntryAuthority(t *testing.T) {
    dependency,err:=AppendReleasePolicyFooter("type Age = Int where it >= 0\n",testReleasePolicy("dependency only"));if err!=nil{t.Fatal(err)}
    base:="import \"age.refine\"\ntype Person = {age :: Age}\n"
    baseline,err:=CompileSources("entry.refine",map[string]string{"entry.refine":base,"age.refine":"type Age = Int where it >= 0\n"});if err!=nil{t.Fatal(err)}
    without,err:=CompileSources("entry.refine",map[string]string{"entry.refine":base,"age.refine":dependency});if err!=nil{t.Fatal(err)}
    if without.ReleasePolicy()!=nil||without.Program().Source()!=baseline.Program().Source(){t.Fatal("imported policy changed flattened contract or granted authority")}
    entry,err:=AppendReleasePolicyFooter(base,testReleasePolicy("entry only"));if err!=nil{t.Fatal(err)}
    bundle,err:=CompileSources("entry.refine",map[string]string{"entry.refine":entry,"age.refine":dependency});if err!=nil{t.Fatal(err)}
    if bundle.ReleasePolicy().Overrides[0].Reason!="entry only"{t.Fatal("entry authority lost")}
    restored,_,present,err:=SplitReleasePolicyFooter(bundle.Program().Source());if err!=nil||!present||restored!=baseline.Program().Source(){t.Fatal("flattened contract changed",err)}
    if bundle.Sources()["age.refine"]!=dependency||bundle.Sources()["entry.refine"]!=entry{t.Fatal("original source bytes lost")}
    detached:=bundle.ReleasePolicy();detached.Overrides[0].Reason="mutated";if bundle.ReleasePolicy().Overrides[0].Reason!="entry only"{t.Fatal("bundle policy aliases state")}
}
