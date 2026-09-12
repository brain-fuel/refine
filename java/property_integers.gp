package java

import (
    "fmt"
    "math/big"
    "strconv"
    "strings"
)

func fixedIntegerPropertyGenerator(name string)(string,error){
    digits:=strings.TrimPrefix(strings.TrimPrefix(name,"UInt"),"Int")
    width,err:=strconv.ParseUint(digits,10,32);if err!=nil||width==0||width>65536{return "",fmt.Errorf("fixed integer property width must be 1 through 65536")}
    count:=new(big.Int).Lsh(big.NewInt(1),uint(width));minimum:=new(big.Int)
    if !strings.HasPrefix(name,"UInt"){minimum.Neg(new(big.Int).Rsh(new(big.Int).Set(count),1))}
    maximum:=new(big.Int).Sub(new(big.Int).Add(minimum,count),big.NewInt(1))
    number:=func(n *big.Int)string{return "new java.math.BigInteger("+javaQuote(n.String())+")"}
    random:="org.jetbrains.jetCheck.Generator.integers(-10000,10000).<Data>map(n -> new Data.Number(Rational.of(java.math.BigInteger.valueOf(n).mod("+number(count)+").add("+number(minimum)+")),"+javaQuote(name)+"))"
    boundary:="org.jetbrains.jetCheck.Generator.sampledFrom("+number(minimum)+","+number(maximum)+",java.math.BigInteger.ZERO).<Data>map(n -> new Data.Number(Rational.of(n),"+javaQuote(name)+"))"
    return "org.jetbrains.jetCheck.Generator.<Data>frequency(3,"+random+",2,"+boundary+")",nil
}
