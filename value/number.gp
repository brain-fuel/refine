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
// Truncate, Floor, Ceiling and RoundHalfEven are explicit exact-to-integer
// rounding operations. They return new values and never modify the payload.
func (n Number) Truncate()Number{r:=n.rat();return numberFromRat(new(big.Rat).SetInt(new(big.Int).Quo(r.Num(),r.Denom())))}
func (n Number) Floor()Number{r:=n.rat();q,rem:=new(big.Int),new(big.Int);q.QuoRem(r.Num(),r.Denom(),rem);if rem.Sign()<0{q.Sub(q,big.NewInt(1))};return numberFromRat(new(big.Rat).SetInt(q))}
func (n Number) Ceiling()Number{r:=n.rat();q,rem:=new(big.Int),new(big.Int);q.QuoRem(r.Num(),r.Denom(),rem);if rem.Sign()>0{q.Add(q,big.NewInt(1))};return numberFromRat(new(big.Rat).SetInt(q))}
func (n Number) RoundHalfEven()Number{r:=n.rat();q,rem:=new(big.Int),new(big.Int);q.QuoRem(r.Num(),r.Denom(),rem);distance:=new(big.Int).Lsh(new(big.Int).Abs(rem),1).Cmp(r.Denom());if distance>0||distance==0&&q.Bit(0)==1{q.Add(q,big.NewInt(int64(r.Sign())))};return numberFromRat(new(big.Rat).SetInt(q))}
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

// ExactFloat32 and ExactFloat64 admit only finite IEEE-754 values whose
// mathematical value is exactly n. They do not convert through a host float,
// so their result is deterministic and retains the exact rational value.
func (n Number) ExactFloat32() (Number,error) { return n.exactBinaryFloat(24,-126,127,"Float32") }
func (n Number) ExactFloat64() (Number,error) { return n.exactBinaryFloat(53,-1022,1023,"Float64") }

// RoundFloat32 and RoundFloat64 explicitly round to the nearest finite IEEE
// value, resolving ties toward an even significand. A result which would be an
// infinity is rejected. IEEE signed zero has no distinct language identity.
func (n Number) RoundFloat32() (Number,error) { return n.roundBinaryFloat(24,-126,127) }
func (n Number) RoundFloat64() (Number,error) { return n.roundBinaryFloat(53,-1022,1023) }

func (n Number) exactBinaryFloat(precision uint,minExponent,maxExponent int,name string)(Number,error){
    rounded,err:=n.roundBinaryFloat(precision,minExponent,maxExponent)
    if err!=nil{return Number{},err}
    if rounded.Compare(n)!=0{return Number{},errors.New("number is not exactly representable as "+name)}
    return n,nil
}

// roundBinaryFloat quantizes an exact rational directly onto the IEEE normal
// or subnormal grid. Work to locate its binary exponent is proportional to the
// already-materialized input; callers must apply the same resource discipline
// required by ParseNumber before invoking this unmetered value primitive.
func (n Number) roundBinaryFloat(precision uint,minExponent,maxExponent int)(Number,error){
    source:=n.rat();sign:=source.Sign()
    if sign==0{return Number{},nil}
    numerator:=new(big.Int).Abs(source.Num());denominator:=source.Denom()
    exponent:=numerator.BitLen()-denominator.BitLen()
    if exponent>=0 {
        if numerator.Cmp(new(big.Int).Lsh(new(big.Int).Set(denominator),uint(exponent)))<0{exponent--}
    } else if new(big.Int).Lsh(new(big.Int).Set(numerator),uint(-exponent)).Cmp(denominator)<0{exponent--}
    if exponent>maxExponent{return Number{},errors.New("binary floating-point overflow")}
    step:=minExponent-int(precision-1)
    if exponent>=minExponent{step=exponent-int(precision-1)}
    scaledNumerator:=new(big.Int).Set(numerator);scaledDenominator:=new(big.Int).Set(denominator)
    if step<0{scaledNumerator.Lsh(scaledNumerator,uint(-step))}else{scaledDenominator.Lsh(scaledDenominator,uint(step))}
    quotient,remainder:=new(big.Int),new(big.Int);quotient.QuoRem(scaledNumerator,scaledDenominator,remainder)
    distance:=new(big.Int).Lsh(new(big.Int).Set(remainder),1).Cmp(scaledDenominator)
    if distance>0||distance==0&&quotient.Bit(0)==1{quotient.Add(quotient,big.NewInt(1))}
    if exponent>=minExponent&&exponent==maxExponent&&quotient.BitLen()>int(precision){return Number{},errors.New("binary floating-point overflow")}
    if quotient.Sign()==0{return Number{},nil}
    roundedNumerator:=new(big.Int).Set(quotient);roundedDenominator:=big.NewInt(1)
    if step<0{roundedDenominator.Lsh(roundedDenominator,uint(-step))}else{roundedNumerator.Lsh(roundedNumerator,uint(step))}
    if sign<0{roundedNumerator.Neg(roundedNumerator)}
    return numberFromRat(new(big.Rat).SetFrac(roundedNumerator,roundedDenominator)),nil
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
