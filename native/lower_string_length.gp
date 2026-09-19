package native

import (
    "encoding/json"
    "strings"
    "goforge.dev/refine/language"
)

// Native string bounds count code points, never the UTF-16 units measured by length.
func (l *lowerer) stringLengthRule(schema any,rule language.Where)bool{
    object,ok:=schema.(map[string]any);if !ok||object["type"]!="string"||lowererHasFunction(l,"codePointLength"){return false}
    match rule.Predicate.Form{
    case language.Binary(operator,left,right):
        if operator!=">="&&operator!="<="{return false};raw,ok:=loweringNumberLiteral(right);if !ok||strings.ContainsAny(raw,"-.eE/"){return false}
        match left.Form{case language.Apply(fn,subject):if !isIt(subject){return false};match fn.Form{case language.Variable(name):if name!="codePointLength"{return false};case _:return false};case _:return false}
        keyword:="minLength";if operator=="<="{keyword="maxLength"};putConstraint(object,keyword,json.Number(raw));return true
    case _:return false
    }
}
