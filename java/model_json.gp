package java

import "goforge.dev/refine/language"

func typeUsesJSON(t *language.Type)bool{
    if t==nil{return false}
    match t.Form{
    case language.NamedType(name):return name=="JSON"
    case language.ListType(element):return typeUsesJSON(element)
    case language.RecordType(fields):for _,field:=range fields{if typeUsesJSON(field.Type){return true}}
    case language.RefinedType(base,_):return typeUsesJSON(base)
    case language.AppliedType(fn,arg):return typeUsesJSON(fn)||typeUsesJSON(arg)
    case language.ArrowType(arg,result):return typeUsesJSON(arg)||typeUsesJSON(result)
    }
    return false
}

func moduleUsesJSON(module *language.Module)bool{for _,decl:=range module.Types{if typeUsesJSON(decl.Body){return true};for _,variant:=range decl.Variants{for _,argument:=range variant.Arguments{if typeUsesJSON(argument){return true}}}};return false}

const modelJSONJava=`
/** Immutable semantic JSON values. Jackson trees never enter the model API. */
public sealed interface JSONValue permits JSONValue.NullValue, JSONValue.BooleanValue, JSONValue.NumberValue, JSONValue.StringValue, JSONValue.ArrayValue, JSONValue.ObjectValue {
    record NullValue() implements JSONValue {}
    record BooleanValue(Boolean value) implements JSONValue { public BooleanValue { java.util.Objects.requireNonNull(value); } }
    record NumberValue(Rational value) implements JSONValue { public NumberValue { java.util.Objects.requireNonNull(value); } }
    record StringValue(String value) implements JSONValue { public StringValue { java.util.Objects.requireNonNull(value); } }
    record ArrayValue(java.util.List<JSONValue> value) implements JSONValue { public ArrayValue { value=java.util.List.copyOf(value); } }
    record ObjectValue(java.util.Map<String,JSONValue> value) implements JSONValue {
        public ObjectValue {
            java.util.Objects.requireNonNull(value);
            var ordered=new java.util.ArrayList<>(value.entrySet());ordered.sort(java.util.Map.Entry.comparingByKey());
            var copy=new java.util.LinkedHashMap<String,JSONValue>();for(var entry:ordered)copy.put(java.util.Objects.requireNonNull(entry.getKey()),java.util.Objects.requireNonNull(entry.getValue()));
            value=java.util.Collections.unmodifiableMap(copy);
        }
    }
}
`

const modelJSONValuesJava=`
final class JSONValues {
    private JSONValues() {}
    private static final int MAX_DEPTH=512,MAX_NODES=100_000;
    private sealed interface EncodeTask permits EncodeValue,EncodeArray,EncodeObject {}
    private record EncodeValue(JSONValue value,String path,int depth)implements EncodeTask {}
    private record EncodeArray(int size)implements EncodeTask {}
    private record EncodeObject(java.util.List<String> keys)implements EncodeTask { EncodeObject { keys=java.util.List.copyOf(keys); } }
    static Data encode(JSONValue value,String path){
        var tasks=new java.util.ArrayDeque<EncodeTask>();var results=new java.util.ArrayDeque<Data>();tasks.push(new EncodeValue(value,path,0));int scheduled=1;
        while(!tasks.isEmpty())switch(tasks.pop()){
            case EncodeValue item->{if(item.depth()>=MAX_DEPTH)throw limit(item.path());ModelSupport.nonNull(item.value(),item.path());switch(item.value()){
                case JSONValue.NullValue ignored->results.push(new Data.Variant("JSONNull",java.util.List.of()));
                case JSONValue.BooleanValue scalar->results.push(new Data.Variant("JSONBoolean",java.util.List.of(new Data.Bool(scalar.value()))));
                case JSONValue.NumberValue scalar->results.push(new Data.Variant("JSONNumber",java.util.List.of(new Data.Number(scalar.value()))));
                case JSONValue.StringValue scalar->results.push(new Data.Variant("JSONString",java.util.List.of(new Data.Text(scalar.value()))));
                case JSONValue.ArrayValue array->{int size=array.value().size();scheduled=schedule(scheduled,size,item.path());tasks.push(new EncodeArray(size));for(int i=size-1;i>=0;i--)tasks.push(new EncodeValue(array.value().get(i),item.path()+"/0/"+i,item.depth()+1));}
                case JSONValue.ObjectValue object->{scheduled=schedule(scheduled,object.value().size(),item.path());var entries=new java.util.ArrayList<>(object.value().entrySet());var keys=new java.util.ArrayList<String>(entries.size());for(var entry:entries)keys.add(entry.getKey());tasks.push(new EncodeObject(keys));for(int i=entries.size()-1;i>=0;i--){var entry=entries.get(i);String child=item.path()+"/0/"+entry.getKey().replace("~","~0").replace("/","~1");tasks.push(new EncodeValue(entry.getValue(),child,item.depth()+1));}}
            }}
            case EncodeArray frame->{var values=new java.util.ArrayList<Data>(java.util.Collections.nCopies(frame.size(),null));for(int i=frame.size()-1;i>=0;i--)values.set(i,results.pop());results.push(new Data.Variant("JSONArray",java.util.List.of(new Data.Sequence(values))));}
            case EncodeObject frame->{var values=new java.util.LinkedHashMap<String,Data>();for(int i=frame.keys().size()-1;i>=0;i--)values.put(frame.keys().get(i),results.pop());results.push(new Data.Variant("JSONObject",java.util.List.of(new Data.Mapping(values))));}
        }
        if(results.size()!=1)throw new AssertionError("invalid JSON model conversion");return results.pop();
    }
    private sealed interface DecodeTask permits DecodeValue,DecodeArray,DecodeObject {}
    private record DecodeValue(Data value,int depth)implements DecodeTask {}
    private record DecodeArray(int size)implements DecodeTask {}
    private record DecodeObject(java.util.List<String> keys)implements DecodeTask { DecodeObject { keys=java.util.List.copyOf(keys); } }
    static JSONValue decode(Data raw){
        var tasks=new java.util.ArrayDeque<DecodeTask>();var results=new java.util.ArrayDeque<JSONValue>();tasks.push(new DecodeValue(raw,0));int scheduled=1;
        while(!tasks.isEmpty())switch(tasks.pop()){
            case DecodeValue item->{if(item.depth()>=MAX_DEPTH)throw new AssertionError("checked JSON model depth exceeded");var variant=(Data.Variant)item.value();switch(variant.name()){
                case "JSONNull"->results.push(new JSONValue.NullValue());
                case "JSONBoolean"->results.push(new JSONValue.BooleanValue(((Data.Bool)variant.values().getFirst()).value()));
                case "JSONNumber"->results.push(new JSONValue.NumberValue(((Data.Number)variant.values().getFirst()).value()));
                case "JSONString"->results.push(new JSONValue.StringValue(((Data.Text)variant.values().getFirst()).value()));
                case "JSONArray"->{var values=((Data.Sequence)variant.values().getFirst()).values();scheduled=checkedSchedule(scheduled,values.size());tasks.push(new DecodeArray(values.size()));for(int i=values.size()-1;i>=0;i--)tasks.push(new DecodeValue(values.get(i),item.depth()+1));}
                case "JSONObject"->{var mapping=((Data.Mapping)variant.values().getFirst()).entries();scheduled=checkedSchedule(scheduled,mapping.size());var entries=new java.util.ArrayList<>(mapping.entrySet());var keys=new java.util.ArrayList<String>(entries.size());for(var entry:entries)keys.add(entry.getKey());tasks.push(new DecodeObject(keys));for(int i=entries.size()-1;i>=0;i--)tasks.push(new DecodeValue(entries.get(i).getValue(),item.depth()+1));}
                default->throw new AssertionError("invalid checked JSON constructor");
            }}
            case DecodeArray frame->{var values=new java.util.ArrayList<JSONValue>(java.util.Collections.nCopies(frame.size(),null));for(int i=frame.size()-1;i>=0;i--)values.set(i,results.pop());results.push(new JSONValue.ArrayValue(values));}
            case DecodeObject frame->{var values=new java.util.LinkedHashMap<String,JSONValue>();for(int i=frame.keys().size()-1;i>=0;i--)values.put(frame.keys().get(i),results.pop());results.push(new JSONValue.ObjectValue(values));}
        }
        if(results.size()!=1)throw new AssertionError("invalid checked JSON model conversion");return results.pop();
    }
    private static int schedule(int used,int count,String path){if(count<0||count>MAX_NODES-used)throw limit(path);return used+count;}
    private static int checkedSchedule(int used,int count){if(count<0||count>MAX_NODES-used)throw new AssertionError("checked JSON model node count exceeded");return used+count;}
    private static ValidationException limit(String path){return new ValidationException(new Validation.Indeterminate(java.util.List.of(new Validation.Diagnostic("validation.limit",java.util.List.of(path),"","JSON model resource limit exceeded."))));}
}
`
