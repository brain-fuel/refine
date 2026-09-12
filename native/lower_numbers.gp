package native

import (
    "strings"

    "goforge.dev/refine/language"
)

// loweringNumberBounded rejects a compact decimal token whose exponent would
// require disproportionate exact-number expansion later in native validation.
// The checked parser already establishes token grammar; this preflight performs
// only bounded digit accumulation and never constructs the represented number.
func loweringNumberBounded(raw string)bool{if len(raw)>DefaultNumericExpansion{return false};index:=strings.IndexAny(raw,"eE");if index<0{return true};index++;if index<len(raw)&&(raw[index]=='+'||raw[index]=='-'){index++};magnitude:=0;for ;index<len(raw);index++{digit:=int(raw[index]-'0');if digit<0||digit>9{return false};if magnitude>(DefaultNumericExpansion-digit)/10{return false};magnitude=magnitude*10+digit};return magnitude<=DefaultNumericExpansion}
func loweringNumberLiteral(expr *language.Expr)(string,bool){raw,ok:=numberLiteral(expr);return raw,ok&&loweringNumberBounded(raw)}
