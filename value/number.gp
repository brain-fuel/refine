// Package value provides immutable, language-neutral refinement values.
package value

import (
    "errors"
    "math/big"
    "regexp"
    "strings"
)

// Number is an immutable exact rational. Its zero value is zero. No mutable
// math/big object is exposed or shared between arithmetic operations.
type Number struct { canonical string }

var numberSyntax = regexp.MustCompile(`^-?(?:0|[1-9][0-9]*)(?:/[1-9][0-9]*|(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)$`)

// ParseNumber accepts decimal integers/fractions/exponents or a rational n/d.
// Errors deliberately omit input values. Callers must budget input size before
// parsing; this value primitive does not own a validation execution budget.
func ParseNumber(text string) (Number, error) {
    if !numberSyntax.MatchString(text) { return Number{}, errors.New("invalid exact number") }
    r, ok := new(big.Rat).SetString(text)
    if !ok { return Number{}, errors.New("invalid exact number") }
    return numberFromRat(r), nil
}

func Integer(n int64) Number { return numberFromRat(new(big.Rat).SetInt64(n)) }
func numberFromRat(r *big.Rat) Number { return Number{canonical: r.RatString()} }
func (n Number) rat() *big.Rat {
    if n.canonical == "" { return new(big.Rat) }
    r, ok := new(big.Rat).SetString(n.canonical)
    if !ok { panic("corrupt internal exact number") }
    return r
}

// Show is canonical: reduced fractions have positive denominators; whole
// numbers have no denominator. The payload is never rounded or normalized in
// place; all Number instances are immutable mathematical values.
func (n Number) Show() string {
    if n.canonical == "" { return "0" }
    return n.canonical
}
func (n Number) IsInteger() bool { return n.rat().IsInt() }
func (n Number) Sign() int { return n.rat().Sign() }
func (n Number) Compare(other Number) int { return n.rat().Cmp(other.rat()) }
func (n Number) Add(other Number) Number { return numberFromRat(new(big.Rat).Add(n.rat(), other.rat())) }
func (n Number) Subtract(other Number) Number { return numberFromRat(new(big.Rat).Sub(n.rat(), other.rat())) }
func (n Number) Multiply(other Number) Number { return numberFromRat(new(big.Rat).Mul(n.rat(), other.rat())) }
func (n Number) Negate() Number { return numberFromRat(new(big.Rat).Neg(n.rat())) }
func (n Number) Divide(other Number) (Number, error) {
    if other.Sign() == 0 { return Number{}, errors.New("division by zero") }
    return numberFromRat(new(big.Rat).Quo(n.rat(), other.rat())), nil
}

// Remainder uses a quotient truncated toward zero; a nonzero remainder has the
// dividend's sign. It is integer-only and never rounds a fractional operand.
func (n Number) Remainder(other Number) (Number,error) {
    left,right := n.rat(),other.rat()
    if !left.IsInt() || !right.IsInt() { return Number{},errors.New("remainder requires integers") }
    if right.Sign() == 0 { return Number{},errors.New("remainder by zero") }
    result := new(big.Int).Rem(left.Num(),right.Num())
    return numberFromRat(new(big.Rat).SetInt(result)),nil
}

// FixedWidth rejects values outside the explicitly requested integer type.
// The returned value is unchanged. Wrapping must use Wrap explicitly.
func (n Number) FixedWidth(bits uint, signed bool) (Number, error) {
    if bits == 0 || bits > 65536 { return Number{}, errors.New("integer width must be between 1 and 65536 bits") }
    r := n.rat()
    if !r.IsInt() { return Number{}, errors.New("expected an integer") }
    upper := new(big.Int).Lsh(big.NewInt(1), bits)
    lower := new(big.Int)
    if signed {
        upper.Rsh(upper, 1)
        lower.Neg(upper)
    }
    if r.Num().Cmp(lower) < 0 || r.Num().Cmp(upper) >= 0 { return Number{}, errors.New("fixed-width integer overflow") }
    return n, nil
}

func (n Number) Wrap(bits uint, signed bool) (Number, error) {
    if bits == 0 || bits > 65536 { return Number{}, errors.New("integer width must be between 1 and 65536 bits") }
    r := n.rat()
    if !r.IsInt() { return Number{}, errors.New("expected an integer") }
    modulus := new(big.Int).Lsh(big.NewInt(1), bits)
    v := new(big.Int).Mod(r.Num(), modulus)
    if signed && v.Cmp(new(big.Int).Rsh(new(big.Int).Set(modulus), 1)) >= 0 { v.Sub(v, modulus) }
    return numberFromRat(new(big.Rat).SetInt(v)), nil
}

// Decimal returns an exact finite decimal for wire encodings which support it.
// Nonterminating fractions fail instead of silently rounding (e.g. 1/3).
func (n Number) Decimal() (string, error) {
    r := n.rat()
    denom := new(big.Int).Set(r.Denom())
    two, five := big.NewInt(2), big.NewInt(5)
    a, b := 0, 0
    rem := new(big.Int)
    for rem.Mod(denom, two).Sign() == 0 { denom.Quo(denom, two); a++ }
    for rem.Mod(denom, five).Sign() == 0 { denom.Quo(denom, five); b++ }
    if denom.Cmp(big.NewInt(1)) != 0 { return "", errors.New("number has no exact finite decimal encoding") }
    places := max(a, b)
    result := r.FloatString(places)
    if places > 0 { result = strings.TrimRight(strings.TrimRight(result, "0"), ".") }
    return result, nil
}
