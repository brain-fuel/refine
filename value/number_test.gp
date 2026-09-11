package value

import (
    "testing"
    "testing/quick"
)

func mustNumber(t *testing.T, text string) Number {
    t.Helper()
    n, err := ParseNumber(text)
    if err != nil { t.Fatal(err) }
    return n
}

func TestExactNumberCases(t *testing.T) {
    cases := []struct { input string; show string; decimal string }{
        {"0", "0", "0"}, {"-0", "0", "0"}, {"2/6", "1/3", ""},
        {"1.2500", "5/4", "1.25"}, {"1e-3", "1/1000", "0.001"},
        {"-1.5e2", "-150", "-150"}, {"9007199254740993", "9007199254740993", "9007199254740993"},
    }
    for _, tc := range cases {
        t.Run(tc.input, func(t *testing.T) {
            n := mustNumber(t, tc.input)
            if n.Show() != tc.show { t.Errorf("show = %s; want %s", n.Show(), tc.show) }
            decimal, err := n.Decimal()
            if tc.decimal == "" { if err == nil { t.Fatal("inexact decimal accepted") }; return }
            if err != nil || decimal != tc.decimal { t.Fatalf("decimal = %s, %v; want %s", decimal, err, tc.decimal) }
        })
    }
    for _, input := range []string{"", "NaN", "Infinity", "0x20", "01", "1/0", "1/-3", "+2", "1.", " 1", "1_000", "1e"} {
        if _, err := ParseNumber(input); err == nil { t.Errorf("accepted %q", input) }
    }
}

func TestExactArithmeticLaws(t *testing.T) {
    property := func(a, b, c int64) bool {
        x, y, z := Integer(a), Integer(b), Integer(c)
        original := x.Show()
        sum := x.Add(y)
        if sum.Subtract(y).Compare(x) != 0 || sum.Compare(y.Add(x)) != 0 { return false }
        if x.Multiply(y.Add(z)).Compare(x.Multiply(y).Add(x.Multiply(z))) != 0 { return false }
        if x.Show() != original { return false }
        shown, err := ParseNumber(sum.Show())
        if err != nil || shown.Compare(sum) != 0 { return false }
        if b != 0 {
            q, err := x.Divide(y)
            if err != nil || q.Multiply(y).Compare(x) != 0 { return false }
        }
        return true
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}

func TestFixedWidthAndExplicitWrapping(t *testing.T) {
    cases := []struct { input string; bits uint; signed bool; valid bool; wrapped string }{
        {"127", 8, true, true, "127"}, {"128", 8, true, false, "-128"},
        {"-128", 8, true, true, "-128"}, {"-129", 8, true, false, "127"},
        {"255", 8, false, true, "255"}, {"256", 8, false, false, "0"},
        {"-1", 8, false, false, "255"}, {"0", 1, true, true, "0"},
        {"1", 1, true, false, "-1"},
    }
    for _, tc := range cases {
        n := mustNumber(t, tc.input)
        _, err := n.FixedWidth(tc.bits, tc.signed)
        if (err == nil) != tc.valid { t.Errorf("%s fits %d signed=%v: %v", tc.input, tc.bits, tc.signed, err) }
        w, err := n.Wrap(tc.bits, tc.signed)
        if err != nil || w.Show() != tc.wrapped { t.Errorf("wrap %s: %s, %v", tc.input, w.Show(), err) }
    }
    if _, err := Integer(1).Divide(Integer(0)); err == nil { t.Fatal("division by zero accepted") }
    if _, err := mustNumber(t, "1/2").FixedWidth(8, true); err == nil { t.Fatal("fraction coerced to integer") }
    if _, err := mustNumber(t, "1/2").Wrap(8, true); err == nil { t.Fatal("fraction wrapped") }
    if (Number{}).Show() != "0" { t.Fatal("zero value is not zero") }
}

func TestRationalReadShowLaw(t *testing.T) {
    property := func(a int64, b uint64) bool {
        denominator := Integer(int64(b>>1) + 1)
        // int64 maximum + 1 wraps; any nonzero denominator still exercises the law.
        q, err := Integer(a).Divide(denominator)
        if err != nil { return false }
        read, err := ParseNumber(q.Show())
        return err == nil && read.Compare(q) == 0
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}
