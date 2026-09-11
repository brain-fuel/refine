package schemajson

import (
    "encoding/json"
    "errors"
    "strings"
    "testing"
    "testing/quick"

    "goforge.dev/refine/value"
)

func TestLosslessNativeFixtures(t *testing.T) {
    cases := []struct { name string; source string }{
        {"json-schema", " {\n  \"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"allOf\":[{\"minimum\":0.00}],\"maximum\":1e20,\"type\":\"integer\"\n}\n"},
        {"avro", `{"type":"record","name":"Person","fields":[{"name":"z","type":"long"},{"name":"a","type":["null","string"],"default":null}]}`},
        {"openapi", `{"openapi":"3.1.0","info":{"title":"Test","version":"1.0.0"},"paths":{},"x-example":{"escaped":"\ud800","n":9007199254740993}}`},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            input := []byte(tc.source)
            doc, err := Parse(input, Limits{})
            if err != nil { t.Fatal(err) }
            input[0] = 'X'
            if doc.Raw() != tc.source { t.Fatal("source bytes lost or mutable") }
            again, err := Parse([]byte(doc.Raw()), Limits{})
            if err != nil || again.Raw() != tc.source { t.Fatal("second round trip changed source") }
        })
    }
}

func TestDuplicateKeys(t *testing.T) {
    cases := []struct { source string; path string }{
        {`{"x":1,"x":1}`, "/x"}, {`{"x":1,"\u0078":2}`, "/x"},
        {`{"items":[{"a/b~c":0,"a/b~c":1}]}`, "/items/0/a~1b~0c"},
        {`{"😀":1,"\ud83d\ude00":2}`, "/😀"},
    }
    for _, tc := range cases {
        _, err := Parse([]byte(tc.source), Limits{})
        var problem *Error
        if !errors.As(err, &problem) || problem.Code != "json.duplicate-key" || problem.Path != tc.path { t.Errorf("%s: %v", tc.source, err) }
    }
    for _, source := range []string{`{"é":1,"e\u0301":2}`, `{"\ud800":1,"\ud801":2}`, `{"x":{"id":1},"y":{"id":2}}`} {
        if _, err := Parse([]byte(source), Limits{}); err != nil { t.Errorf("distinct keys rejected: %v", err) }
    }
}

func TestOrderedImmutableAccess(t *testing.T) {
    doc, err := Parse([]byte(`{"z":[1e2,9007199254740993],"a":"\ud800"}`), Limits{})
    if err != nil { t.Fatal(err) }
    members := doc.Root().Members()
    if members[0].Key.Show() != `"z"` || members[1].Key.Show() != `"a"` { t.Fatal("member order lost") }
    list, ok := doc.Root().Lookup("z")
    if !ok || list.Elements()[0].Raw() != "1e2" || list.Elements()[1].Raw() != "9007199254740993" { t.Fatal("number spelling/precision lost") }
    members[0] = Member{}
    elements := list.Elements()
    elements[0] = Node{}
    if doc.Root().Members()[0].Key.Show() != `"z"` || list.Elements()[0].Raw() != "1e2" { t.Fatal("mutable tree escaped") }
    node, _ := doc.Root().Lookup("a")
    text, ok := node.Text()
    if !ok || text.Show() != `"\ud800"` { t.Fatal("unpaired surrogate silently replaced") }
}

func TestSyntaxAndResourceLimits(t *testing.T) {
    for _, source := range []string{"", "{}{}", `{"x":NaN}`, `{"x":1,}`, "\"\xff\""} {
        if _, err := Parse([]byte(source), Limits{}); err == nil { t.Errorf("accepted invalid input %q", source) }
    }
    cases := []struct { source string; limits Limits }{
        {`{"a":1}`, Limits{Bytes: 2}}, {`[[[0]]]`, Limits{Depth: 2}},
        {`[1,2]`, Limits{Nodes: 2}}, {`0`, Limits{Bytes: -1}},
    }
    for _, tc := range cases {
        var problem *Error
        _, err := Parse([]byte(tc.source), tc.limits)
        if !errors.As(err, &problem) || problem.Code != "json.limit" { t.Errorf("limit not reported: %v", err) }
    }
    if _, err := Parse([]byte(`[[0]]`), Limits{Depth: 2, Nodes: 3, Bytes: 5}); err != nil { t.Fatal(err) }
}

func TestExactCodeUnitKeysProperty(t *testing.T) {
    property := func(units []uint16) bool {
        key := value.TextFromUnits(units)
        source := "{" + key.Show() + ":1}"
        doc, err := Parse([]byte(source), Limits{})
        if err != nil || doc.Raw() != source { return false }
        child, ok := doc.Root().LookupText(key)
        if !ok || child.Raw() != "1" { return false }
        _, err = Parse([]byte("{"+key.Show()+":1,"+key.Show()+":2}"), Limits{})
        var problem *Error
        return errors.As(err, &problem) && problem.Code == "json.duplicate-key"
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 3000}); err != nil { t.Fatal(err) }
}

func TestPerConstraintEditIsolation(t *testing.T) {
    source := "{\n  \"allOf\": [ { \"minimum\": 0.00 } ],\n  \"maximum\": 1e2, \"description\": \"minimum stays here\"\n}\n"
    doc, err := Parse([]byte(source), Limits{})
    if err != nil { t.Fatal(err) }
    changed, err := doc.Replace("/allOf/0/minimum", []byte(" 21 \n"))
    if err != nil { t.Fatal(err) }
    expected := strings.Replace(source, "0.00", "21", 1)
    if changed.Raw() != expected { t.Fatalf("unrelated native source changed: %s", changed.Raw()) }
    if doc.Raw() != source { t.Fatal("original document mutated") }
    maximum, err := changed.At("/maximum")
    if err != nil || maximum.Raw() != "1e2" { t.Fatal("untouched maximum lost original spelling") }
    restored, err := changed.Replace("/allOf/0/minimum", []byte("0.00"))
    if err != nil || restored.Raw() != source { t.Fatal("restoring original constraint did not restore original document") }
    same, err := doc.Replace("/maximum", []byte("1e2"))
    if err != nil || same.Raw() != source { t.Fatal("identity edit changed document") }
}

func TestJSONPointersAndEditLimits(t *testing.T) {
    doc, err := Parse([]byte(`{"a/b":{"~key":[0,1]},"":true}`), Limits{})
    if err != nil { t.Fatal(err) }
    for pointer, expected := range map[string]string{"/a~1b/~0key/1":"1", "/":"true", "":doc.Root().Raw()} {
        node, err := doc.At(pointer)
        if err != nil || node.Raw() != expected { t.Errorf("pointer %q: %s, %v", pointer, node.Raw(), err) }
    }
    for _, pointer := range []string{"x", "/~2", "/~", "/absent", "/a~1b/~0key/01", "/a~1b/~0key/-", "/a~1b/~0key/2", "/a~1b/~0key/0/x"} {
        if _, err := doc.Replace(pointer, []byte("2")); err == nil { t.Errorf("accepted invalid pointer %q", pointer) }
    }
    if _, err := doc.Replace("/", []byte(`{"x":1,"x":2}`)); err == nil { t.Fatal("duplicate-key replacement accepted") }
    capped, _ := Parse([]byte(`{"x":1}`), Limits{Bytes: 8, Depth: 1})
    if _, err := capped.Replace("/x", []byte("100")); err == nil { t.Fatal("replacement escaped byte cap") }
    depthCapped, _ := Parse([]byte(`{"x":1}`), Limits{Depth: 1})
    if _, err := depthCapped.Replace("/x", []byte("[0]")); err == nil { t.Fatal("replacement escaped depth cap") }
}

func TestReplaceIdentityProperty(t *testing.T) {
    property := func(n int64, units []uint16) bool {
        text := value.TextFromUnits(units)
        source := " {\"a\": " + value.Integer(n).Show() + ",\"b\":" + text.Show() + "} \n"
        doc, err := Parse([]byte(source), Limits{})
        if err != nil { return false }
        for _, pointer := range []string{"", "/a", "/b"} {
            node, err := doc.At(pointer)
            if err != nil { return false }
            copy, err := doc.Replace(pointer, []byte(node.Raw()))
            if err != nil || copy.Raw() != source { return false }
        }
        return true
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}

func FuzzLosslessDocument(f *testing.F) {
    for _, seed := range []string{`{}`, `[]`, `{"x":1,"x":2}`, `{"a":["\ud800",1e20]}`, `"hello"`, `null`, `{"x":"a\\\"b"}`} { f.Add(seed) }
    f.Fuzz(func(t *testing.T, source string) {
        doc, err := Parse([]byte(source), Limits{Bytes: 65536, Depth: 64, Nodes: 10000})
        if err != nil { return }
        if !json.Valid([]byte(source)) || doc.Raw() != source { t.Fatal("accepted invalid JSON or lost source") }
        rootSource := strings.TrimSpace(source)
        if doc.Root().Raw() != rootSource { t.Fatal("root source span is wrong") }
    })
}
