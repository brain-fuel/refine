package native

import (
    "encoding/json"
    "strings"
    "goforge.dev/refine/language"
)

// cardinalityRule recognizes the canonical collection-size comparison only.
// Native string length is intentionally excluded; it is not UTF-16 length.
func (l *lowerer) cardinalityRule(schema any,rule language.Where)bool{
    object,ok:=schema.(map[string]any);if !ok{return false}
    match rule.Predicate.Form{
    case language.Binary(operator,left,right):
        if operator!=">="&&operator!="<="{return false}
        raw,ok:=loweringNumberLiteral(right);if !ok||strings.ContainsAny(raw,"-.eE/"){return false}
        builtin:="";match left.Form{case language.Apply(fn,subject):if !isIt(subject){return false};match fn.Form{case language.Variable(name):builtin=name;case _:return false};case _:return false}
        if lowererHasFunction(l,builtin){return false};keyword:=""
        if builtin=="length"&&object["type"]=="array"{if operator==">="{keyword="minItems"}else{keyword="maxItems"}}
        if builtin=="size"&&object["type"]=="object"{if operator==">="{keyword="minProperties"}else{keyword="maxProperties"}}
        if keyword==""{return false};putConstraint(object,keyword,json.Number(raw));return true
    case _:return false
    }
}
