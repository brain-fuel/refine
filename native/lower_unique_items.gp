package native

import "goforge.dev/refine/language"

// uniqueItemsRule recognizes only the canonical detached intrinsic-JSON
// predicate emitted by provenance. It never grants native authority to a
// user-defined unique function or to uniqueness over a projected item type.
func (l *lowerer) uniqueItemsRule(schema any,rule language.Where,base *language.Type)bool{
    object,ok:=schema.(map[string]any);if !ok||object["type"]!="array"||language.FormatType(base)!="[JSON]"||lowererHasFunction(l,"unique"){return false}
    match rule.Predicate.Form{
    case language.Apply(fn,subject):
        if !isIt(subject){return false}
        match fn.Form{case language.Variable(name):if name!="unique"{return false};case _:return false}
        putConstraint(object,"uniqueItems",true);return true
    case _:return false
    }
}
