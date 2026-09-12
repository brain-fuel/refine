package native

import (
    "encoding/binary"
    "errors"
    "fmt"
    "math"
    "math/big"

    avro "github.com/hamba/avro/v2"
    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

// DecodeAndValidateAvro is the complete Go Avro boundary for a native
// project. It first enforces the exact writer schema and bounded binary framing,
// decodes the datum into the checked language payload without floating-point
// rounding, and finally evaluates the editable refinements. Native-only
// ValidateAvroBinary deliberately continues to accept Avro NaN and infinities;
// this refined boundary rejects them because value.Data numbers are finite
// exact rationals.
func (p *Project) DecodeAndValidateAvro(input []byte,payloadLimits AvroPayloadLimits,refinementLimits validation.Limits)(value.Data,validation.Report,error){
    if p==nil||p.program==nil{return value.Data{},validation.Report{},&Error{Code:"native.project",Message:"a checked project is required"}}
    if p.Format()!=Avro{return value.Data{},validation.Report{},&Error{Code:"native.enforcement",Format:p.Format(),Message:"the refined Avro boundary requires an Avro project"}}
    bounded,err:=normalizeAvroPayloadLimits(payloadLimits);if err!=nil{return value.Data{},validation.Report{},wrap(Avro,"native.limit","",err)}
    if err:=p.ValidateAvroBinary(input,bounded);err!=nil{return value.Data{},validation.Report{},err}
    schema,err:=p.avroWriterSchema();if err!=nil{return value.Data{},validation.Report{},err};target,err:=p.PayloadType();if err!=nil{return value.Data{},validation.Report{},err};checked:=target.CheckedSyntax()
    decoder:=avroValueDecoder{cursor:avroBinaryCursor{input:input,limits:bounded},metadata:p.Metadata(),declarations:map[string]language.TypeDecl{}}
    for _,decl:=range checked.Module.Syntax.Types{decoder.declarations[decl.Name]=decl}
    data,err:=decoder.decode(checked.Type,schema,nil,"$",0,"");if err!=nil{return value.Data{},validation.Report{},decoder.boundaryError(err)}
    if decoder.cursor.offset!=len(input){return value.Data{},validation.Report{},&Error{Code:"native.decode",Format:Avro,Message:"Avro checked decoder did not consume exactly one datum"}}
    return data,target.ValidateData(data,refinementLimits),nil
}

type avroValueDecoder struct{cursor avroBinaryCursor;metadata WireMetadata;declarations map[string]language.TypeDecl;numericUsed int}

func (d *avroValueDecoder) failure(path,message string)error{return &Error{Code:"native.decode",Format:Avro,Pointer:path,Message:message}}
func (d *avroValueDecoder) boundaryError(err error)error{var native *Error;if errors.As(err,&native){return err};var exhausted *avroPayloadLimitError;if errors.As(err,&exhausted){return wrap(Avro,"native.limit","",err)};return wrap(Avro,"native.decode","",err)}
func avroDereference(schema avro.Schema)avro.Schema{for schema!=nil&&schema.Type()==avro.Ref{schema=schema.(*avro.RefSchema).Schema()};return schema}

// Type aliases and generic applications do not consume wire nodes. Only the
// physical schema branches charge the independent checked-decoder budget.
func (d *avroValueDecoder) decode(t *language.Type,schema avro.Schema,bindings map[string]*language.Type,path string,depth int,nominal string)(value.Data,error){
    if t==nil{return value.Data{},d.failure(path,"checked Avro type is absent")};schema=avroDereference(schema);if schema==nil{return value.Data{},d.failure(path,"compiled Avro schema is absent")}
    match t.Form{
    case language.RefinedType(base,_):return d.decode(base,schema,bindings,path,depth,nominal)
    case language.NamedType(name):
        if bound,ok:=bindings[name];ok{return d.decode(bound,schema,bindings,path,depth,nominal)}
        if encoding,ok:=d.metadata.Scalars[name];ok{return d.scalar(name,encoding,schema,path,depth)}
        switch name{
        case "Bool":return d.primitive(name,schema,path,depth)
        case "String","Timestamp","Real","Float32","Float64":return d.primitive(name,schema,path,depth)
        }
        if jsonLanguageInteger(name){return d.primitive(name,schema,path,depth)}
        decl,ok:=d.declarations[name];if !ok{return value.Data{},d.failure(path,"checked type cannot be represented by the Avro decoder")};if len(decl.Parameters)!=0{return value.Data{},d.failure(path,"generic Avro type is missing arguments")};if decl.Body!=nil{return d.decode(decl.Body,schema,nil,path,depth,name)};return d.union(name,decl.Variants,nil,schema,path,depth)
    case language.ListType(element):return d.list(element,schema,bindings,path,depth)
    case language.RecordType(fields):return d.record(nominal,fields,schema,bindings,path,depth)
    case language.AppliedType(_,_):
        name,args,ok:=jsonApplied(t);if !ok{return value.Data{},d.failure(path,"unsupported applied Avro type")}
        if name=="Nullable"&&len(args)==1{return d.nullable(args[0],schema,bindings,path,depth)}
        decl,found:=d.declarations[name];if !found||len(args)!=len(decl.Parameters){return value.Data{},d.failure(path,"unknown or incorrectly applied generic Avro type")};closed:=map[string]*language.Type{};for key,item:=range bindings{closed[key]=item};for i,param:=range decl.Parameters{argument:=args[i];if bindings!=nil{resolved,subErr:=language.SubstituteType(argument,bindings);if subErr!=nil{return value.Data{},d.failure(path,"generic Avro argument cannot be closed")};argument=resolved};closed[param]=argument};if decl.Body!=nil{return d.decode(decl.Body,schema,closed,path,depth,name)};return d.union(name,decl.Variants,closed,schema,path,depth)
    case language.ArrowType(_,_):return value.Data{},d.failure(path,"functions are not Avro payload values")
    }
    return value.Data{},d.failure(path,"unsupported checked Avro type")
}

func (d *avroValueDecoder) charge(path string,depth int)error{return d.cursor.charge(depth,path)}
func (d *avroValueDecoder) primitive(name string,schema avro.Schema,path string,depth int)(value.Data,error){if err:=d.charge(path,depth);err!=nil{return value.Data{},err};switch schema.Type(){
    case avro.Boolean:if name!="Bool"{return value.Data{},d.failure(path,"Avro boolean does not match the checked type")};raw,err:=d.cursor.take(1,path);if err!=nil{return value.Data{},err};if raw[0]!=0&&raw[0]!=1{return value.Data{},d.failure(path,"invalid Avro boolean")};return value.OfBool(raw[0]==1),nil
    case avro.Int:n,err:=d.cursor.signed(path,5);if err!=nil{return value.Data{},err};if !jsonLanguageInteger(name)&&name!="Real"{return value.Data{},d.failure(path,"Avro int does not match the checked numeric type")};return value.OfNumber(value.Integer(n)),nil
    case avro.Long:n,err:=d.cursor.long(path);if err!=nil{return value.Data{},err};if !jsonLanguageInteger(name)&&name!="Real"{return value.Data{},d.failure(path,"Avro long does not match the checked numeric type")};return value.OfNumber(value.Integer(n)),nil
    case avro.Float:if name!="Real"&&name!="Float32"{return value.Data{},d.failure(path,"Avro float does not match the checked numeric type")};raw,err:=d.cursor.take(4,path);if err!=nil{return value.Data{},err};return d.binaryFloat(float64(math.Float32frombits(binary.LittleEndian.Uint32(raw))),path)
    case avro.Double:if name!="Real"&&name!="Float64"{return value.Data{},d.failure(path,"Avro double does not match the checked numeric type")};raw,err:=d.cursor.take(8,path);if err!=nil{return value.Data{},err};return d.binaryFloat(math.Float64frombits(binary.LittleEndian.Uint64(raw)),path)
    case avro.String:if name!="String"&&name!="Timestamp"{return value.Data{},d.failure(path,"Avro string does not match the checked type")};text,err:=d.cursor.text(path);if err!=nil{return value.Data{},err};scalar,err:=value.TextFromUTF8(text);if err!=nil{return value.Data{},d.failure(path,"Avro string is not Unicode scalar text")};return value.OfText(scalar),nil
    }
    return value.Data{},d.failure(path,"Avro schema primitive does not match the checked type")
}

func (d *avroValueDecoder) binaryFloat(number float64,path string)(value.Data,error){if math.IsNaN(number)||math.IsInf(number,0){return value.Data{},d.failure(path,"non-finite Avro floating-point value has no exact Refine Data representation")};exact:=new(big.Rat).SetFloat64(number);parsed,err:=value.ParseNumber(exact.RatString());if err!=nil{return value.Data{},d.failure(path,"finite Avro floating-point value is not representable")};return value.OfNumber(parsed),nil}

func (d *avroValueDecoder) list(element *language.Type,schema avro.Schema,bindings map[string]*language.Type,path string,depth int)(value.Data,error){
    if err:=d.charge(path,depth);err!=nil{return value.Data{},err};switch schema.Type(){
    case avro.Array:return d.array(element,schema.(*avro.ArraySchema).Items(),bindings,path,depth)
    case avro.Bytes:raw,err:=d.cursor.bytes(path);if err!=nil{return value.Data{},err};return d.byteList(raw,path)
    case avro.Fixed:raw,err:=d.cursor.take(schema.(*avro.FixedSchema).Size(),path);if err!=nil{return value.Data{},err};return d.byteList(raw,path)
    };return value.Data{},d.failure(path,"checked list does not match an Avro array, bytes, or fixed schema")
}

func (d *avroValueDecoder) byteList(raw []byte,path string)(value.Data,error){if len(raw)>d.cursor.limits.Values-d.cursor.nodes{return value.Data{},d.cursor.limit(path,"decoded byte list exceeds payload value count limit")};d.cursor.nodes+=len(raw);items:=make([]value.Data,len(raw));for i,item:=range raw{items[i]=value.OfNumber(value.Integer(int64(item)))};return value.List(items),nil}

func (d *avroValueDecoder) array(element *language.Type,itemSchema avro.Schema,bindings map[string]*language.Type,path string,depth int)(value.Data,error){items:=[]value.Data{}
    for block:=0;;block++{count,err:=d.cursor.long(path);if err!=nil{return value.Data{},err};if count==0{return value.List(items),nil};blockBytes:=int64(-1);if count<0{if count==math.MinInt64{return value.Data{},d.failure(path,"Avro array block count overflows")};count=-count;blockBytes,err=d.cursor.long(path);if err!=nil{return value.Data{},err};if blockBytes<0||blockBytes>int64(len(d.cursor.input)-d.cursor.offset){return value.Data{},d.failure(path,"invalid Avro array block byte size")}}
        if count>int64(d.cursor.limits.Values-d.cursor.nodes){return value.Data{},d.cursor.limit(path,"payload value count exceeds limit")};start:=d.cursor.offset
        for i:=int64(0);i<count;i++{decoded,decodeErr:=d.decode(element,itemSchema,bindings,fmt.Sprintf("%s[%d]",path,len(items)),depth+1,"");if decodeErr!=nil{return value.Data{},decodeErr};items=append(items,decoded)}
        if blockBytes>=0&&int64(d.cursor.offset-start)!=blockBytes{return value.Data{},d.failure(path,"Avro array block byte size does not match its contents")}
    }
}

func (d *avroValueDecoder) record(nominal string,fields []language.Field,schema avro.Schema,bindings map[string]*language.Type,path string,depth int)(value.Data,error){if schema.Type()!=avro.Record{return value.Data{},d.failure(path,"checked record does not match an Avro record")};if err:=d.charge(path,depth);err!=nil{return value.Data{},err};nativeFields:=schema.(*avro.RecordSchema).Fields();if len(fields)!=len(nativeFields){return value.Data{},d.failure(path,"edited checked record fields do not match the native Avro writer schema")};checkedFields:=make(map[string]language.Field,len(fields));for _,field:=range fields{checkedFields[field.Name]=field};out:=make([]value.DataField,len(nativeFields));for i,nativeField:=range nativeFields{field,ok:=checkedFields[nativeField.Name()];if !ok{return value.Data{},d.failure(path,"edited checked record fields do not match the native Avro writer schema")};decoded,err:=d.decode(field.Type,nativeField.Type(),bindings,path+"."+field.Name,depth+1,"");if err!=nil{return value.Data{},err};out[i]=value.DataField{Name:field.Name,Value:decoded}};result,err:=value.Record(out);if err!=nil{return value.Data{},d.failure(path,"Avro record is not representable")};return result,nil}

func (d *avroValueDecoder) nullable(inner *language.Type,schema avro.Schema,bindings map[string]*language.Type,path string,depth int)(value.Data,error){if schema.Type()!=avro.Union{return value.Data{},d.failure(path,"Nullable checked type does not match an Avro union")};if err:=d.charge(path,depth);err!=nil{return value.Data{},err};branches:=schema.(*avro.UnionSchema).Types();if len(branches)!=2{return value.Data{},d.failure(path,"Nullable checked type requires a two-branch Avro union")};nullIndex:=-1;for i,branch:=range branches{if avroDereference(branch).Type()==avro.Null{nullIndex=i}};if nullIndex<0{return value.Data{},d.failure(path,"Nullable checked type requires one Avro null branch")};index,err:=d.cursor.long(path);if err!=nil{return value.Data{},err};if index<0||index>=2{return value.Data{},d.failure(path,"Avro union branch index is out of range")};if int(index)==nullIndex{return value.Variant("Null",nil)};decoded,err:=d.decode(inner,branches[index],bindings,path+"<non-null>",depth+1,"");if err!=nil{return value.Data{},err};return value.Variant("NonNull",[]value.Data{decoded})}

func (d *avroValueDecoder) union(name string,variants []language.Variant,bindings map[string]*language.Type,schema avro.Schema,path string,depth int)(value.Data,error){switch schema.Type(){
    case avro.Enum:if err:=d.charge(path,depth);err!=nil{return value.Data{},err};symbols:=schema.(*avro.EnumSchema).Symbols();if len(symbols)!=len(variants){return value.Data{},d.failure(path,"edited checked constructors do not match the native Avro enum")};for i,symbol:=range symbols{if len(variants[i].Arguments)!=0||variants[i].Name!=safeTypeName(symbol){return value.Data{},d.failure(path,"edited checked constructors do not match the native Avro enum")}};index,err:=d.cursor.long(path);if err!=nil{return value.Data{},err};if index<0||index>=int64(len(variants)){return value.Data{},d.failure(path,"Avro enum symbol index is out of range")};return value.Variant(variants[index].Name,nil)
    case avro.Union:if err:=d.charge(path,depth);err!=nil{return value.Data{},err};branches:=schema.(*avro.UnionSchema).Types();if len(branches)!=len(variants){return value.Data{},d.failure(path,"edited checked constructors do not match the native Avro union")};index,err:=d.cursor.long(path);if err!=nil{return value.Data{},err};if index<0||index>=int64(len(variants)){return value.Data{},d.failure(path,"Avro union branch index is out of range")};selected:=variants[index];if len(selected.Arguments)!=1{return value.Data{},d.failure(path,"native Avro union branches require exactly one checked constructor argument")};typ:=selected.Arguments[0];if bindings!=nil{closed,subErr:=language.SubstituteType(typ,bindings);if subErr!=nil{return value.Data{},d.failure(path,"generic Avro union argument cannot be closed")};typ=closed};decoded,decodeErr:=d.decode(typ,branches[index],nil,path+"<"+selected.Name+">",depth+1,"");if decodeErr!=nil{return value.Data{},decodeErr};return value.Variant(selected.Name,[]value.Data{decoded})
    };return value.Data{},d.failure(path,"checked union does not match an Avro enum or union")}

func (d *avroValueDecoder) scalar(name string,encoding ScalarEncoding,schema avro.Schema,path string,depth int)(value.Data,error){if err:=d.charge(path,depth);err!=nil{return value.Data{},err};switch encoding.Kind{
    case JSONNumber:return value.Data{},d.failure(path,"json-number encoding cannot be decoded from Avro")
    case DecimalString:if schema.Type()!=avro.String{return value.Data{},d.failure(path,"decimal-string scalar requires an Avro string")};text,err:=d.cursor.text(path);if err!=nil{return value.Data{},err};if !jsonIntegerToken(text,true){return value.Data{},d.failure(path,"integer string must use canonical base-10 spelling")};number,err:=value.ParseNumber(text);if err!=nil{return value.Data{},d.failure(path,"invalid exact integer string")};return value.OfNumber(number),nil
    case TimestampString:if schema.Type()!=avro.String{return value.Data{},d.failure(path,"timestamp-string scalar requires an Avro string")};text,err:=d.cursor.text(path);if err!=nil{return value.Data{},err};scalar,err:=value.TextFromUTF8(text);if err!=nil{return value.Data{},d.failure(path,"timestamp string is not Unicode scalar text")};return value.OfText(scalar),nil
    case RationalRecord:return d.rationalRecord(schema,path)
    case AvroBytesDecimal:return d.decimal(encoding,schema,path)
    };return value.Data{},d.failure(path,"unsupported Avro scalar encoding for "+name)}

func (d *avroValueDecoder) rationalRecord(schema avro.Schema,path string)(value.Data,error){if schema.Type()!=avro.Record{return value.Data{},d.failure(path,"rational-record scalar requires an Avro record")};fields:=schema.(*avro.RecordSchema).Fields();if len(fields)!=2||fields[0].Name()!="numerator"||fields[1].Name()!="denominator"||avroDereference(fields[0].Type()).Type()!=avro.Bytes||avroDereference(fields[1].Type()).Type()!=avro.Bytes{return value.Data{},d.failure(path,"rational-record Avro schema has an incompatible shape")};numerator,err:=d.cursor.bytes(path+".numerator");if err!=nil{return value.Data{},err};denominator,err:=d.cursor.bytes(path+".denominator");if err!=nil{return value.Data{},err};if !minimalSignedAvroInteger(numerator)||!minimalSignedAvroInteger(denominator){return value.Data{},d.failure(path,"rational-record integers must use minimal signed two's-complement encoding")};if err:=d.numericBytes(path,numerator,denominator);err!=nil{return value.Data{},err};n:=signedAvroInteger(numerator);den:=signedAvroInteger(denominator);if den.Sign()<=0{return value.Data{},d.failure(path+".denominator","rational-record denominator must be positive")};if new(big.Int).GCD(nil,nil,new(big.Int).Abs(new(big.Int).Set(n)),den).Cmp(big.NewInt(1))!=0{return value.Data{},d.failure(path,"rational-record numerator and denominator must be reduced")};number,err:=value.ParseNumber(n.String()+"/"+den.String());if err!=nil{return value.Data{},d.failure(path,"invalid exact rational-record value")};return value.OfNumber(number),nil}

func (d *avroValueDecoder) decimal(encoding ScalarEncoding,schema avro.Schema,path string)(value.Data,error){if schema.Type()!=avro.Bytes&&schema.Type()!=avro.Fixed{return value.Data{},d.failure(path,"avro-bytes-decimal scalar requires Avro bytes or fixed")};logical,ok:=schema.(avro.LogicalTypeSchema);if !ok{return value.Data{},d.failure(path,"avro-bytes-decimal scalar requires the Avro decimal logical type")};decimal,ok:=logical.Logical().(*avro.DecimalLogicalSchema);if !ok||decimal.Precision()!=encoding.Precision||decimal.Scale()!=encoding.Scale{return value.Data{},d.failure(path,"Avro decimal precision or scale differs from checked wire metadata")};var raw []byte;var err error;if schema.Type()==avro.Bytes{raw,err=d.cursor.bytes(path)}else{raw,err=d.cursor.take(schema.(*avro.FixedSchema).Size(),path)};if err!=nil{return value.Data{},err};if err:=d.numericBytes(path,raw);err!=nil{return value.Data{},err};if err:=d.numericCharge(path,encoding.Scale+1);err!=nil{return value.Data{},err};integer:=signedAvroInteger(raw);denominator:=new(big.Int).Exp(big.NewInt(10),big.NewInt(int64(encoding.Scale)),nil);number,err:=value.ParseNumber(integer.String()+"/"+denominator.String());if err!=nil{return value.Data{},d.failure(path,"invalid exact Avro decimal")};return value.OfNumber(number),nil}

func (d *avroValueDecoder) numericCharge(path string,amount int)error{limit:=d.metadata.NumericExpansionLimit();if amount<0||amount>limit-d.numericUsed{return &avroPayloadLimitError{offset:d.cursor.offset,path:path,message:"Avro exact number exceeds numeric expansion limit"}};d.numericUsed+=amount;return nil}
func (d *avroValueDecoder) numericBytes(path string,values ...[]byte)error{for _,raw:=range values{if len(raw)>math.MaxInt/8{return &avroPayloadLimitError{offset:d.cursor.offset,path:path,message:"Avro exact number exceeds numeric expansion limit"}};digits:=(len(raw)*8*30103)/100000+1;if err:=d.numericCharge(path,digits);err!=nil{return err}};return nil}
func signedAvroInteger(raw []byte)*big.Int{result:=new(big.Int).SetBytes(raw);if len(raw)>0&&raw[0]&0x80!=0{result.Sub(result,new(big.Int).Lsh(big.NewInt(1),uint(len(raw)*8)))};return result}
func minimalSignedAvroInteger(raw []byte)bool{if len(raw)==0{return false};if len(raw)==1{return true};return !(raw[0]==0&&raw[1]&0x80==0||raw[0]==0xff&&raw[1]&0x80!=0)}
