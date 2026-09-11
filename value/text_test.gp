package value

import (
    "testing"
    "testing/quick"
)

func TestUTF16LengthAndEquality(t *testing.T) {
    cases := []struct { input string; length int; shown string }{
        {"", 0, `""`}, {"abc", 3, `"abc"`}, {"😀", 2, `"\ud83d\ude00"`},
        {"é", 1, `"\u00e9"`}, {"e\u0301", 2, `"e\u0301"`},
        {"\n\"\\", 3, `"\u000a\"\\"`},
    }
    for _, tc := range cases {
        v, err := TextFromUTF8(tc.input)
        if err != nil { t.Fatal(err) }
        if v.Length() != tc.length || v.Show() != tc.shown { t.Errorf("%q: length %d, show %s", tc.input, v.Length(), v.Show()) }
        back, err := v.UTF8()
        if err != nil || back != tc.input { t.Errorf("UTF-8 round trip: %q, %v", back, err) }
    }
    composed, _ := TextFromUTF8("é")
    decomposed, _ := TextFromUTF8("e\u0301")
    if composed.Equal(decomposed) { t.Fatal("equality silently normalized text") }
}

func TestTextImmutable(t *testing.T) {
    units := []uint16{'a', 'b'}
    v := TextFromUnits(units)
    units[0] = 'z'
    copy := v.Units()
    copy[1] = 'z'
    joined := v.Concat(v)
    if v.Show() != `"ab"` || joined.Show() != `"abab"` { t.Fatal("mutable text backing escaped") }
}

func TestTextReadShowProperty(t *testing.T) {
    property := func(units []uint16) bool {
        v := TextFromUnits(units)
        read, err := ReadText(v.Show())
        return err == nil && read.Equal(v) && read.Show() == v.Show()
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 5000}); err != nil { t.Fatal(err) }
}

func TestMalformedTextAndSurrogates(t *testing.T) {
    for _, input := range []string{`abc`, `"\u00"`, `"\u+123"`, `"\q"`, `"a"b"`, "\"\n\"", "\"\xff\""} {
        if _, err := ReadText(input); err == nil { t.Errorf("accepted malformed text %q", input) }
    }
    for _, input := range []string{`"\ud800"`, `"\udc00"`, `"\ud800x"`} {
        v, err := ReadText(input)
        if err != nil { t.Fatal(err) }
        if _, err := v.UTF8(); err == nil { t.Errorf("silently encoded unpaired surrogate: %s", input) }
        if v.Show() != input { t.Errorf("lost code units: %s", v.Show()) }
    }
    if _, err := TextFromUTF8("\xff"); err == nil { t.Fatal("invalid UTF-8 accepted") }
}

func FuzzTextReadShow(f *testing.F) {
    for _, seed := range []string{`"hello"`, `"\ud800"`, `"😀"`, `"e\u0301"`, `"\\"`} { f.Add(seed) }
    f.Fuzz(func(t *testing.T, input string) {
        v, err := ReadText(input)
        if err != nil { return }
        next, err := ReadText(v.Show())
        if err != nil || !next.Equal(v) { t.Fatalf("show/read lost text: %s", v.Show()) }
    })
}
