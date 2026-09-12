package native

import (
    "errors"
    "fmt"
    "math"
    "math/big"
    "regexp"
    "unicode/utf8"

    avro "github.com/hamba/avro/v2"
    "goforge.dev/refine/schemajson"
)

// AvroPayloadLimits bound native Avro binary validation. Zero selects the
// documented defaults. Values counts schema values, including record fields
// and collection elements; it is independent of refinement evaluation steps.
type AvroPayloadLimits struct { Bytes int; Depth int; Values int; StringBytes int }

func normalizeAvroPayloadLimits(in AvroPayloadLimits)(AvroPayloadLimits,error){
    if in.Bytes<0||in.Depth<0||in.Values<0||in.StringBytes<0{return in,fmt.Errorf("Avro payload limits must be nonnegative")}
    if in.Bytes==0{in.Bytes=schemajson.DefaultBytes};if in.Depth==0{in.Depth=schemajson.DefaultDepth};if in.Values==0{in.Values=schemajson.DefaultNodes};if in.StringBytes==0{in.StringBytes=1<<20};return in,nil
}

// ValidateAvroBinary validates exactly one datum against the selected writer
// schema and every explicitly supplied dependency. This is native-only: callers
// must separately decode to the checked PayloadType and run its refinements.
func (p *Project) ValidateAvroBinary(input []byte,limits AvroPayloadLimits)error{
    if p==nil||p.document==nil{return &Error{Code:"native.project",Message:"a project is required"}}
    if p.Format()!=Avro{return &Error{Code:"native.enforcement",Format:p.Format(),Message:"Avro binary validation requires an Avro project"}}
    bounded,err:=normalizeAvroPayloadLimits(limits);if err!=nil{return wrap(Avro,"native.limit","",err)};if len(input)>bounded.Bytes{return &Error{Code:"native.limit",Format:Avro,Message:"Avro payload byte limit exceeded"}}
    schema,err:=p.avroWriterSchema();if err!=nil{return err};if err:=avroSchemaEnforceable(schema,map[avro.Schema]bool{});err!=nil{return &Error{Code:"native.enforcement",Format:Avro,Message:err.Error(),Cause:err}}
    cursor:=avroBinaryCursor{input:input,limits:bounded};if err:=cursor.value(schema,0,"$");err!=nil{var exhausted *avroPayloadLimitError;if errors.As(err,&exhausted){return wrap(Avro,"native.limit","",err)};return wrap(Avro,"native.payload","",err)};if cursor.offset!=len(input){return &Error{Code:"native.payload",Format:Avro,Message:fmt.Sprintf("trailing bytes after one Avro datum at byte %d",cursor.offset)}};return nil
}

func (p *Project) avroWriterSchema()(avro.Schema,error){cache:=&avro.SchemaCache{};var selected avro.Schema
    for _,resource:=range p.resources{schema,err:=parseAvroStructure([]byte(resource.Source),cache);if err!=nil{return nil,wrap(Avro,"native.structure",resource.URI,err)};if resource.URI==p.root.Resource{selected=schema}}
    if selected==nil{return nil,&Error{Code:"native.root",Format:Avro,Pointer:p.root.Resource,Message:"root writer schema is absent"}};return selected,nil
}

// Avro 1.12 requires unknown or invalid logical types to be read as their
// underlying type. Known logical types are enforced at their physical carrier.
func avroSchemaEnforceable(schema avro.Schema,seen map[avro.Schema]bool)error{
    if seen[schema]{return nil};seen[schema]=true
    switch schema.Type(){
    case avro.Ref:return avroSchemaEnforceable(schema.(*avro.RefSchema).Schema(),seen)
    case avro.Record:for _,field:=range schema.(*avro.RecordSchema).Fields(){if err:=avroSchemaEnforceable(field.Type(),seen);err!=nil{return err}}
    case avro.Array:return avroSchemaEnforceable(schema.(*avro.ArraySchema).Items(),seen)
    case avro.Map:return avroSchemaEnforceable(schema.(*avro.MapSchema).Values(),seen)
    case avro.Union:for _,branch:=range schema.(*avro.UnionSchema).Types(){if err:=avroSchemaEnforceable(branch,seen);err!=nil{return err}}
    };return nil
}

type avroBinaryCursor struct { input []byte; offset int; nodes int; limits AvroPayloadLimits }
type avroPayloadLimitError struct { offset int; path string; message string }
func (e *avroPayloadLimitError)Error()string{return fmt.Sprintf("byte %d at %s: %s",e.offset,e.path,e.message)}

func (c *avroBinaryCursor) fail(path,message string)error{return fmt.Errorf("byte %d at %s: %s",c.offset,path,message)}
func (c *avroBinaryCursor) limit(path,message string)error{return &avroPayloadLimitError{offset:c.offset,path:path,message:message}}
func (c *avroBinaryCursor) charge(depth int,path string)error{if depth>c.limits.Depth{return c.limit(path,"payload nesting exceeds limit")};if c.nodes>=c.limits.Values{return c.limit(path,"payload value count exceeds limit")};c.nodes++;return nil}
func (c *avroBinaryCursor) take(size int,path string)([]byte,error){if size<0||size>len(c.input)-c.offset{return nil,c.fail(path,"unexpected end of Avro datum")};start:=c.offset;c.offset+=size;return c.input[start:c.offset],nil}

func (c *avroBinaryCursor) signed(path string,width int)(int64,error){var encoded uint64
    for i:=0;i<width;i++{part,err:=c.take(1,path);if err!=nil{return 0,err};b:=part[0];if i==width-1&&((width==10&&b>1)||(width==5&&b>15)){return 0,c.fail(path,"Avro integer varint overflows its declared width")};encoded|=uint64(b&0x7f)<<uint(7*i);if b&0x80==0{return int64(encoded>>1)^-int64(encoded&1),nil}}
    return 0,c.fail(path,"unterminated Avro integer varint")
}
func (c *avroBinaryCursor) long(path string)(int64,error){return c.signed(path,10)}

func (c *avroBinaryCursor) length(path string)(int,error){n,err:=c.long(path);if err!=nil{return 0,err};if n<0||uint64(n)>uint64(len(c.input)-c.offset){return 0,c.fail(path,"invalid or truncated Avro byte length")};if n>int64(c.limits.StringBytes){return 0,c.limit(path,"Avro string/bytes value exceeds limit")};return int(n),nil}
func (c *avroBinaryCursor) bytes(path string)([]byte,error){size,err:=c.length(path);if err!=nil{return nil,err};return c.take(size,path)}
func (c *avroBinaryCursor) text(path string)(string,error){raw,err:=c.bytes(path);if err!=nil{return "",err};if !utf8.Valid(raw){return "",c.fail(path,"Avro string is not valid UTF-8")};return string(raw),nil}

var avroUUID=regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func (c *avroBinaryCursor) value(schema avro.Schema,depth int,path string)error{
    if schema.Type()==avro.Ref{return c.value(schema.(*avro.RefSchema).Schema(),depth,path)}
    if err:=c.charge(depth,path);err!=nil{return err};logical,recognized:=avroLogicalType(schema)
    switch schema.Type(){
    case avro.Null:return nil
    case avro.Boolean:raw,err:=c.take(1,path);if err!=nil{return err};if raw[0]!=0&&raw[0]!=1{return c.fail(path,"Avro boolean must be encoded as 0 or 1")};return nil
    case avro.Int:n,err:=c.signed(path,5);if err!=nil{return err};if n<math.MinInt32||n>math.MaxInt32{return c.fail(path,"Avro int is outside signed 32-bit range")};if recognized&&logical=="time-millis"&&(n<0||n>=86400000){return c.fail(path,"time-millis is outside one day")};return nil
    case avro.Long:n,err:=c.long(path);if err!=nil{return err};if recognized&&logical=="time-micros"&&(n<0||n>=86400000000){return c.fail(path,"time-micros is outside one day")};return nil
    case avro.Float:_,err:=c.take(4,path);return err
    case avro.Double:_,err:=c.take(8,path);return err
    case avro.String:text,err:=c.text(path);if err!=nil{return err};if recognized&&logical=="uuid"&&!avroUUID.MatchString(text){return c.fail(path,"uuid string does not conform to the RFC-4122 textual layout")};return nil
    case avro.Bytes:raw,err:=c.bytes(path);if err!=nil{return err};if recognized&&logical=="decimal"{return validateAvroDecimal(schema,raw,path,c)};if named,ok:=rawLogicalType(schema);ok&&named=="big-decimal"{return validateAvroBigDecimal(raw,path,c)};return nil
    case avro.Fixed:fixed:=schema.(*avro.FixedSchema);raw,err:=c.take(fixed.Size(),path);if err!=nil{return err};if recognized&&logical=="decimal"{return validateAvroDecimal(schema,raw,path,c)};return nil
    case avro.Enum:index,err:=c.long(path);if err!=nil{return err};if index<0||index>=int64(len(schema.(*avro.EnumSchema).Symbols())){return c.fail(path,"Avro enum symbol index is out of range")};return nil
    case avro.Record:for _,field:=range schema.(*avro.RecordSchema).Fields(){if err:=c.value(field.Type(),depth+1,path+"."+field.Name());err!=nil{return err}};return nil
    case avro.Array:return c.collection(schema.(*avro.ArraySchema).Items(),depth,path,false)
    case avro.Map:return c.collection(schema.(*avro.MapSchema).Values(),depth,path,true)
    case avro.Union:index,err:=c.long(path);if err!=nil{return err};branches:=schema.(*avro.UnionSchema).Types();if index<0||index>=int64(len(branches)){return c.fail(path,"Avro union branch index is out of range")};return c.value(branches[index],depth+1,path+"<union>")
    };return c.fail(path,"unsupported compiled Avro schema type "+string(schema.Type()))
}

func (c *avroBinaryCursor) collection(item avro.Schema,depth int,path string,isMap bool)error{seenKeys:=map[string]bool{}
    for block:=0;;block++{count,err:=c.long(path);if err!=nil{return err};if count==0{return nil};blockBytes:=int64(-1);if count<0{if count==math.MinInt64{return c.fail(path,"Avro collection block count overflows")};count=-count;blockBytes,err=c.long(path);if err!=nil{return err};if blockBytes<0||blockBytes>int64(len(c.input)-c.offset){return c.fail(path,"invalid Avro collection block byte size")}}
        if count>int64(c.limits.Values-c.nodes){return c.limit(path,"payload value count exceeds limit")};start:=c.offset
        for i:=int64(0);i<count;i++{if isMap{key,err:=c.text(path+"{key}");if err!=nil{return err};if seenKeys[key]{return c.fail(path,"duplicate Avro map key")};seenKeys[key]=true};if err:=c.value(item,depth+1,path+"[]");err!=nil{return err}}
        if blockBytes>=0&&int64(c.offset-start)!=blockBytes{return c.fail(path,fmt.Sprintf("Avro collection block declared %d bytes but contained %d",blockBytes,c.offset-start))}
    }
}

func rawLogicalType(schema avro.Schema)(string,bool){properties,ok:=schema.(avro.PropertySchema);if !ok{return "",false};value,ok:=properties.Prop("logicalType").(string);return value,ok}
func avroLogicalType(schema avro.Schema)(string,bool){if carrier,ok:=schema.(avro.LogicalTypeSchema);ok{if logical:=carrier.Logical();logical!=nil{return string(logical.Type()),true}}
    raw,ok:=rawLogicalType(schema);if !ok{return "",false};switch raw{case "timestamp-nanos","local-timestamp-nanos":return raw,schema.Type()==avro.Long;case "uuid":if fixed,ok:=schema.(*avro.FixedSchema);ok&&fixed.Size()==16{return raw,true}};return "",false
}

func validateAvroDecimal(schema avro.Schema,raw []byte,path string,c *avroBinaryCursor)error{carrier,ok:=schema.(avro.LogicalTypeSchema);if !ok{return nil};logical,ok:=carrier.Logical().(*avro.DecimalLogicalSchema);if !ok{return nil};integer:=new(big.Int).SetBytes(raw);if len(raw)>0&&raw[0]&0x80!=0{integer.Sub(integer,new(big.Int).Lsh(big.NewInt(1),uint(len(raw)*8)))};digits:=len(new(big.Int).Abs(integer).String());if digits>logical.Precision(){return c.fail(path,fmt.Sprintf("decimal value has %d digits, exceeding precision %d",digits,logical.Precision()))};return nil}

// Avro 1.12 big-decimal stores an Avro bytes value containing a second Avro
// bytes value (the signed big-endian two's-complement unscaled integer)
// followed by an Avro int scale. Scale is any signed 32-bit value. Redundant
// sign-extension bytes are legal and are not canonicalized or rejected.
func validateAvroBigDecimal(raw []byte,path string,parent *avroBinaryCursor)error{inner:=avroBinaryCursor{input:raw,limits:parent.limits};unscaled,err:=inner.bytes(path+"<unscaled>");if err!=nil{return err};if len(unscaled)==0{return parent.fail(path,"big-decimal unscaled integer is empty")};if _,err:=inner.signed(path+"<scale>",5);err!=nil{return err};if inner.offset!=len(raw){return parent.fail(path,fmt.Sprintf("big-decimal contains %d trailing bytes",len(raw)-inner.offset))};return nil}
