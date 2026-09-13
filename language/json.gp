package language

// JSON is an intrinsic closed algebraic type. Its constructors deliberately
// use ordinary language types so canonical show/read and predicate evaluation
// need no second dynamic value representation.
type jsonConstructorSpec struct { name string; arguments []*Type }

func jsonNamed(name string)*Type{return &Type{Form:NamedType(name)}}
func jsonType()*Type{return jsonNamed("JSON")}
func jsonConstructorSpecs()[]jsonConstructorSpec{
    list:=&Type{Form:ListType(jsonType())}
    mapping:=&Type{Form:AppliedType(&Type{Form:AppliedType(jsonNamed("Map"),jsonNamed("String"))},jsonType())}
    return []jsonConstructorSpec{
        {name:"JSONNull"},
        {name:"JSONBoolean",arguments:[]*Type{jsonNamed("Bool")}},
        {name:"JSONNumber",arguments:[]*Type{jsonNamed("Real")}},
        {name:"JSONString",arguments:[]*Type{jsonNamed("String")}},
        {name:"JSONArray",arguments:[]*Type{list}},
        {name:"JSONObject",arguments:[]*Type{mapping}},
    }
}

func jsonConstructor(name string)(jsonConstructorSpec,bool){for _,item:=range jsonConstructorSpecs(){if item.name==name{return item,true}};return jsonConstructorSpec{},false}
