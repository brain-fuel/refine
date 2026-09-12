package language

import "sort"

// Capabilities never introduce a conversion. Num admits only an already-bound
// numeric type, while Ord admits an already-bound numeric, String or Timestamp.
func capabilityName(class string)string {
    switch class{case "equality":return "Eq";case "show":return "Show";case "read":return "Read";case "numeric":return "Num";case "integral":return "Integral";case "ordering":return "Ord"}
    return class
}

func supportedCapability(name string)bool {
    switch name{case "Eq","Show","Read","Num","Integral","Ord":return true};return false
}

type capabilityOwner struct { function string; variable string }

// solveCapabilities computes a least fixed point. Direct overloaded uses seed
// requirements; references to named functions propagate the callee's effective
// requirements through that reference's already-unified instantiation. This
// handles forward, higher-order and recursive references without checking order.
func (c *checker) solveCapabilities() {
    effective:=make(map[string]map[string]map[string]Span)
    owners:=make(map[int]capabilityOwner)
    for _,fn:=range c.module.Functions{
        variables:=c.functionVariables[fn.Name]
        byVariable:=make(map[string]map[string]Span);effective[fn.Name]=byVariable
        for name,term:=range variables{owners[term.variable]=capabilityOwner{function:fn.Name,variable:name}}
        seen:=make(map[string]bool)
        for _,constraint:=range fn.Constraints{
            if !supportedCapability(constraint.Capability){typeError(constraint.At,"unknown capability "+constraint.Capability+"; expected Eq, Show, Read, Num, Integral, or Ord")}
            if _,ok:=variables[constraint.Variable];!ok{typeError(constraint.At,"capability variable "+constraint.Variable+" does not occur in the function signature")}
            key:=constraint.Capability+"\x00"+constraint.Variable
            if seen[key]{typeError(constraint.At,"duplicate capability constraint")};seen[key]=true
            addCapability(effective,fn.Name,constraint.Variable,constraint.Capability,constraint.At)
        }
    }
    changed:=true
    for _,requirement:=range c.capabilityRequirements{
        c.requireCapability(requirement.class,requirement.typ,requirement.at,effective,owners,make(map[string][]*term))
    }
    // Each pass can add at least one supported capability to a finite number of
    // signature variables. The explicit bound is defensive against regressions.
    variables:=0;for _,scope:=range c.functionVariables{variables+=len(scope)}
    limit:=variables*6+1
    for pass:=0;changed&&pass<limit;pass++{
        changed=false
        for _,call:=range c.capabilityCalls{
            for variable,classes:=range effective[call.callee]{
                instantiated,ok:=call.bindings[variable];if !ok{continue}
                for class:=range classes{
                    if c.requireCapability(class,instantiated,call.at,effective,owners,make(map[string][]*term)){changed=true}
                }
            }
        }
    }
    c.module.functionCapabilities=make(map[string][]CapabilityConstraint,len(effective))
    order:=map[string]int{"Eq":0,"Ord":1,"Num":2,"Integral":3,"Show":4,"Read":5}
    for _,fn:=range c.module.Functions{
        items:=[]CapabilityConstraint{}
        for variable,classes:=range effective[fn.Name]{for class,at:=range classes{items=append(items,CapabilityConstraint{Capability:class,Variable:variable,At:at})}}
        sort.Slice(items,func(i,j int)bool{if items[i].Variable!=items[j].Variable{return items[i].Variable<items[j].Variable};return order[items[i].Capability]<order[items[j].Capability]})
        c.module.functionCapabilities[fn.Name]=items
    }
}

func addCapability(effective map[string]map[string]map[string]Span,function,variable,class string,at Span)bool {
    variables:=effective[function];if variables==nil{variables=make(map[string]map[string]Span);effective[function]=variables}
    classes:=variables[variable];if classes==nil{classes=make(map[string]Span);variables[variable]=classes}
    if _,exists:=classes[class];exists{return false};classes[class]=at;return true
}

func capabilityFailure(class string,at Span) {
    switch class{
    case "Eq":typeError(at,"functions do not support value equality")
    case "Show":typeError(at,"functions do not support canonical display")
    case "Read":typeError(at,"functions are not readable payload values")
    case "Num":typeError(at,"numeric operations require a numeric type")
    case "Integral":typeError(at,"remainder requires an integer type")
    case "Ord":typeError(at,"ordering requires a numeric, String, or Timestamp type")
    }
}

// requireCapability either proves a closed structural type supports a class or
// records the class on a rigid function variable. Declaration-only rigid
// variables remain deferred until the closed payload boundary, matching the
// existing generic refinement model.
func (c *checker) requireCapability(class string,t *term,at Span,effective map[string]map[string]map[string]Span,owners map[int]capabilityOwner,visiting map[string][]*term)bool {
    t=c.prune(t)
    if t.variable!=0{
        if binding,ok:=owners[t.variable];ok{return addCapability(effective,binding.function,binding.variable,class,at)}
        if t.rigid{
            // Type declarations do not yet have a qualified-context surface.
            // Preserve the existing generic codec allowance, whose closed
            // payload boundary excludes functions, but never invent numeric,
            // ordering, or equality evidence for a declaration parameter.
            switch class{case "Read","Show":return false;case "Eq":typeError(at,"equality operand type cannot be inferred; add a concrete annotation");case "Num":typeError(at,"numeric type cannot be inferred; add an annotation");case "Integral":typeError(at,"integer type cannot be inferred; add an annotation");case "Ord":typeError(at,"ordered type cannot be inferred; add an annotation")}
        }
        switch class{case "Read":typeError(at,"read target type cannot be inferred; add an annotation");case "Eq":typeError(at,"equality operand type cannot be inferred; add a concrete annotation");case "Show":typeError(at,"show operand type cannot be inferred; add an annotation");case "Num":typeError(at,"numeric type cannot be inferred; add an annotation");case "Integral":typeError(at,"integer type cannot be inferred; add an annotation");case "Ord":typeError(at,"ordered type cannot be inferred; add an annotation")}
    }
    if t.name=="->"{capabilityFailure(class,at);return false}
    if primitive(t.name){
        if class=="Num" && !numericCapabilityPrimitive(t.name){capabilityFailure(class,at)}
        if class=="Integral" && !integralCapabilityPrimitive(t.name){capabilityFailure(class,at)}
        if class=="Ord" && !numericCapabilityPrimitive(t.name) && t.name!="String" && t.name!="Timestamp"{capabilityFailure(class,at)}
        return false
    }
    changed:=false
    if class=="Num"||class=="Integral"||class=="Ord"{
        declaration,declared:=c.declarations[t.name]
        if !declared||declaration.Body==nil{capabilityFailure(class,at);return false}
        if previous,seen:=visiting[t.name];seen{
            if sameCapabilityTerms(c,previous,t.args){return false}
            for _,arg:=range t.args{if c.requireCapability(class,arg,at,effective,owners,visiting){changed=true}}
            return changed
        }
        visiting[t.name]=append([]*term(nil),t.args...);defer delete(visiting,t.name)
        expanded,_:=c.expandOne(t)
        return c.requireCapability(class,expanded,at,effective,owners,visiting)
    }
    switch t.name{
    case "[]","Maybe","Nullable","Result":
        for _,arg:=range t.args{if c.requireCapability(class,arg,at,effective,owners,visiting){changed=true}}
        return changed
    case "{}":
        for _,field:=range t.fields{if c.requireCapability(class,field.typ,at,effective,owners,visiting){changed=true}}
        return changed
    }
    declaration,declared:=c.declarations[t.name]
    if !declared{return false}
    if previous,seen:=visiting[t.name];seen{
        if sameCapabilityTerms(c,previous,t.args){return false}
        for _,arg:=range t.args{if c.requireCapability(class,arg,at,effective,owners,visiting){changed=true}}
        return changed
    }
    visiting[t.name]=append([]*term(nil),t.args...);defer delete(visiting,t.name)
    if declaration.Body!=nil{
        expanded,_:=c.expandOne(t)
        return c.requireCapability(class,expanded,at,effective,owners,visiting)
    }
    for _,variant:=range c.family(t){for _,arg:=range variant.arguments{if c.requireCapability(class,arg,at,effective,owners,visiting){changed=true}}}
    return changed
}

func sameCapabilityTerms(c *checker,left,right []*term)bool {
    if len(left)!=len(right){return false}
    for i:=range left{a,b:=c.prune(left[i]),c.prune(right[i]);if a.variable!=b.variable||a.name!=b.name||len(a.args)!=len(b.args)||len(a.fields)!=len(b.fields){return false};if !sameCapabilityTerms(c,a.args,b.args){return false};for j:=range a.fields{if a.fields[j].name!=b.fields[j].name||!sameCapabilityTerms(c,[]*term{a.fields[j].typ},[]*term{b.fields[j].typ}){return false}}}
    return true
}

func numericCapabilityPrimitive(name string)bool {
    return name=="Int"||name=="Real"||name=="Float32"||name=="Float64"||primitive(name)&&(len(name)>=3&&(name[:3]=="Int"||len(name)>=4&&name[:4]=="UInt"))
}
func integralCapabilityPrimitive(name string)bool{return name!="Real"&&name!="Float32"&&name!="Float64"&&numericCapabilityPrimitive(name)}
