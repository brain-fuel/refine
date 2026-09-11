package value

import (
    "encoding/json"
    "os"
    "testing"
)

// This fixture is language-neutral and will also be consumed by Java runtime
// conformance tests. A Go pass alone does not establish Java parity.
func TestNumberConformanceData(t *testing.T) {
    data, err := os.ReadFile("testdata/numbers.json")
    if err != nil { t.Fatal(err) }
    var cases []struct { Name string; Op string; Left string; Right string; Result string; Error string }
    if err := json.Unmarshal(data, &cases); err != nil { t.Fatal(err) }
    if len(cases) == 0 { t.Fatal("empty conformance fixture") }
    for _, tc := range cases {
        t.Run(tc.Name, func(t *testing.T) {
            left := mustNumber(t, tc.Left)
            right := Integer(0)
            if tc.Right != "" { right = mustNumber(t, tc.Right) }
            var actual Number
            var failure error
            switch tc.Op {
            case "add": actual = left.Add(right)
            case "subtract": actual = left.Subtract(right)
            case "multiply": actual = left.Multiply(right)
            case "divide": actual, failure = left.Divide(right)
            case "negate": actual = left.Negate()
            default: t.Fatalf("unknown fixture operation %q", tc.Op)
            }
            if tc.Error != "" {
                if failure == nil || failure.Error() != tc.Error { t.Fatalf("failure = %v, want %s", failure, tc.Error) }
            } else if failure != nil || actual.Show() != tc.Result { t.Fatalf("result = %s, %v; want %s", actual.Show(), failure, tc.Result) }
        })
    }
}
