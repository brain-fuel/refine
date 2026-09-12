package native

import (
    "encoding/binary"
    "errors"
    "math"
    "strconv"

    avro "github.com/hamba/avro/v2"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

// ValidateAvroJSON checks exactly one datum using Avro's JSON encoding, not
// ordinary JSON model encoding. Non-null unions require their native type tag;
// bytes/fixed use code points 0..255. Defaults never fill missing writer fields.
// The JSON parser and binary transcode have independent bounded work/storage.
func (p *Project) ValidateAvroJSON(input []byte,limits AvroPayloadLimits)error{
    encoded,bounded,err:=p.avroJSONBinary(input,limits);if err!=nil{return err}
    return p.ValidateAvroBinary(encoded,bounded)
}

// DecodeAndValidateAvroJSON composes strict Avro JSON framing, the native writer
// schema, exact binary-to-Data decoding, and the selected Refine predicates.
// Reader-schema resolution is provided by generated Java adapters; this API
// intentionally takes one writer project and never guesses a reader schema.
func (p *Project) DecodeAndValidateAvroJSON(input []byte,payloadLimits AvroPayloadLimits,refinementLimits validation.Limits)(value.Data,validation.Report,error){
    encoded,bounded,err:=p.avroJSONBinary(input,payloadLimits);if err!=nil{return value.Data{},validation.Report{},err}
    return p.DecodeAndValidateAvro(encoded,bounded,refinementLimits)
}

func (p *Project) avroJSONBinary(input []byte,limits AvroPayloadLimits)([]byte,AvroPayloadLimits,error){
    if p==nil||p.document==nil{return nil,limits,&Error{Code:"native.project",Message:"a checked project is required"}}
    if p.Format()!=Avro{return nil,limits,&Error{Code:"native.enforcement",Format:p.Format(),Message:"Avro JSON validation requires an Avro project"}}
    bounded,err:=normalizeAvroPayloadLimits(limits);if err!=nil{return nil,limits,wrap(Avro,"native.limit","",err)}
    doc,err:=schemajson.Parse(input,schemajson.Limits{Bytes:bounded.Bytes,Depth:bounded.Depth,Nodes:bounded.Values});if err!=nil{var syntax *schemajson.Error;code:="native.payload";if errors.As(err,&syntax)&&syntax.Code=="json.limit"{code="native.limit"};return nil,bounded,wrap(Avro,code,"",err)}
    schema,err:=p.avroWriterSchema();if err!=nil{return nil,bounded,err};if err=avroSchemaEnforceable(schema,map[avro.Schema]bool{});err!=nil{return nil,bounded,wrap(Avro,"native.enforcement","",err)}
    encoder:=avroJSONEncoder{limits:bounded};if err=encoder.encode(schema,doc.Root(),0,"$");err!=nil{return nil,bounded,err};return encoder.output,bounded,nil
}

type avroJSONEncoder struct {limits AvroPayloadLimits;nodes int;output []byte}
func (e *avroJSONEncoder)invalid(path,message string)error{return &Error{Code:"native.payload",Format:Avro,Pointer:path,Message:message}}
func (e *avroJSONEncoder)limit(path,message string)error{return &Error{Code:"native.limit",Format:Avro,Pointer:path,Message:message}}
func (e *avroJSONEncoder)append(path string,input []byte)error{if len(input)>e.limits.Bytes-len(e.output){return e.limit(path,"Avro JSON transcode byte limit exceeded")};e.output=append(e.output,input...);return nil}
func (e *avroJSONEncoder)long(path string,number int64)error{var raw [10]byte;size:=binary.PutUvarint(raw[:],uint64(number<<1)^uint64(number>>63));return e.append(path,raw[:size])}
func (e *avroJSONEncoder)text(path string,text value.Text)error{if text.Length()>e.limits.StringBytes{return e.limit(path,"Avro JSON string byte limit exceeded")};encoded,err:=text.UTF8();if err!=nil{return e.invalid(path,"Avro string contains an unpaired UTF-16 surrogate")};if len(encoded)>e.limits.StringBytes{return e.limit(path,"Avro JSON string byte limit exceeded")};if err=e.long(path,int64(len(encoded)));err!=nil{return err};return e.append(path,[]byte(encoded))}

func (e *avroJSONEncoder)encode(schema avro.Schema,node schemajson.Node,depth int,path string)error{
    if depth>e.limits.Depth{return e.limit(path,"Avro JSON datum nesting limit exceeded")};if e.nodes>=e.limits.Values{return e.limit(path,"Avro JSON datum value count limit exceeded")};e.nodes++;schema=avroDereference(schema);kind:=schemajson.KindName(node.Kind())
    switch schema.Type(){
    case avro.Null:if kind!="null"{return e.invalid(path,"expected Avro null")};return nil
    case avro.Boolean:if kind!="boolean"{return e.invalid(path,"expected Avro boolean")};if node.Raw()=="true"{return e.append(path,[]byte{1})};return e.append(path,[]byte{0})
    case avro.Int,avro.Long:
        if kind!="number"{return e.invalid(path,"expected Avro integer")};bits:=64;if schema.Type()==avro.Int{bits=32};number,err:=strconv.ParseInt(node.Raw(),10,bits);if err!=nil{return e.invalid(path,"Avro integer must be an in-range JSON integer token")};return e.long(path,number)
    case avro.Float,avro.Double:
        if kind!="number"{return e.invalid(path,"expected Avro floating-point number")};bits:=64;if schema.Type()==avro.Float{bits=32};number,err:=strconv.ParseFloat(node.Raw(),bits);if err!=nil||math.IsInf(number,0)||math.IsNaN(number){return e.invalid(path,"Avro JSON floating-point number is outside the finite wire range")};var raw [8]byte;if bits==32{binary.LittleEndian.PutUint32(raw[:4],math.Float32bits(float32(number)));return e.append(path,raw[:4])};binary.LittleEndian.PutUint64(raw[:],math.Float64bits(number));return e.append(path,raw[:])
    case avro.String:text,ok:=node.Text();if !ok{return e.invalid(path,"expected Avro string")};return e.text(path,text)
    case avro.Bytes,avro.Fixed:
        text,ok:=node.Text();if !ok{return e.invalid(path,"expected Avro byte string")};if text.Length()>e.limits.StringBytes{return e.limit(path,"Avro JSON byte string limit exceeded")};if schema.Type()==avro.Fixed&&text.Length()!=schema.(*avro.FixedSchema).Size(){return e.invalid(path,"Avro fixed byte count does not match its schema")};units:=text.Units();if len(units)>e.limits.Bytes-len(e.output){return e.limit(path,"Avro JSON transcode byte limit exceeded")};raw:=make([]byte,len(units));for i,unit:=range units{if unit>255{return e.invalid(path,"Avro byte strings require code points between 0 and 255")};raw[i]=byte(unit)};if schema.Type()==avro.Bytes{if err:=e.long(path,int64(len(raw)));err!=nil{return err}};return e.append(path,raw)
    case avro.Enum:
        text,ok:=node.Text();if !ok{return e.invalid(path,"expected Avro enum symbol")};symbol,err:=text.UTF8();if err!=nil{return e.invalid(path,"invalid Avro enum text")};for i,candidate:=range schema.(*avro.EnumSchema).Symbols(){if symbol==candidate{return e.long(path,int64(i))}};return e.invalid(path,"unknown Avro enum symbol")
    case avro.Record:
        if kind!="object"{return e.invalid(path,"expected Avro record object")};fields:=schema.(*avro.RecordSchema).Fields();members:=node.Members();if len(members)!=len(fields){return e.invalid(path,"Avro record must contain every writer field and no undeclared fields")};indexed:=map[string]schemajson.Node{};for _,member:=range members{name,err:=member.Key.UTF8();if err!=nil{return e.invalid(path,"invalid Avro record field name")};indexed[name]=member.Value};for _,field:=range fields{item,ok:=indexed[field.Name()];if !ok{return e.invalid(path,"required Avro writer field is absent")};if err:=e.encode(field.Type(),item,depth+1,path+"."+field.Name());err!=nil{return err}};return nil
    case avro.Array:
        if kind!="array"{return e.invalid(path,"expected Avro array")};items:=node.Elements();if len(items)>e.limits.Values-e.nodes{return e.limit(path,"Avro JSON array value count limit exceeded")};if len(items)>0{if err:=e.long(path,int64(len(items)));err!=nil{return err};for _,item:=range items{if err:=e.encode(schema.(*avro.ArraySchema).Items(),item,depth+1,path+"[]");err!=nil{return err}}};return e.long(path,0)
    case avro.Map:
        if kind!="object"{return e.invalid(path,"expected Avro map object")};items:=node.Members();if len(items)>e.limits.Values-e.nodes{return e.limit(path,"Avro JSON map value count limit exceeded")};if len(items)>0{if err:=e.long(path,int64(len(items)));err!=nil{return err};for _,item:=range items{if err:=e.text(path+"{key}",item.Key);err!=nil{return err};if err:=e.encode(schema.(*avro.MapSchema).Values(),item.Value,depth+1,path+"{}");err!=nil{return err}}};return e.long(path,0)
    case avro.Union:return e.union(schema.(*avro.UnionSchema),node,depth,path)
    };return &Error{Code:"native.enforcement",Format:Avro,Pointer:path,Message:"compiled Avro type cannot be transcoded from JSON"}
}

func (e *avroJSONEncoder)union(schema *avro.UnionSchema,node schemajson.Node,depth int,path string)error{
    kind:=schemajson.KindName(node.Kind());tag:="null";payload:=node
    if kind!="null"{if kind!="object"{return e.invalid(path,"non-null Avro union requires a one-member tagged object")};members:=node.Members();if len(members)!=1{return e.invalid(path,"Avro union requires exactly one tag")};var err error;tag,err=members[0].Key.UTF8();if err!=nil||tag=="null"{return e.invalid(path,"invalid Avro union tag")};payload=members[0].Value}
    for i,branch:=range schema.Types(){resolved:=avroDereference(branch);name:=string(resolved.Type());if named,ok:=resolved.(avro.NamedSchema);ok{name=named.FullName()};if name==tag{if err:=e.long(path,int64(i));err!=nil{return err};return e.encode(resolved,payload,depth+1,path+"<union>")}}
    return e.invalid(path,"Avro union tag is not a branch of the writer schema")
}
