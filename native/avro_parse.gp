package native

import (
    "bytes"
    "encoding/json"
    "errors"
    "io"

    avro "github.com/hamba/avro/v2"
    "goforge.dev/refine/schemajson"
)

// hamba v2.31 validates a union field default against branch zero only. Avro
// 1.12 instead selects the first branch that matches. Parse an internal copy
// without record-field defaults and leave default authority to the exact
// schemajson audit. Union order and every other schema member remain intact.
// The caller-owned/original source is never replaced by this oracle input.
func parseAvroStructure(input []byte,cache *avro.SchemaCache)(avro.Schema,error){oracle,err:=avroStructureInput(input);if err!=nil{return nil,err};return avro.ParseBytesWithCache(oracle,"",cache)}

func avroStructureInput(input []byte)([]byte,error){decoder:=json.NewDecoder(bytes.NewReader(input));decoder.UseNumber();var root any;if err:=decoder.Decode(&root);err!=nil{return nil,err};var extra any;if err:=decoder.Decode(&extra);!errors.Is(err,io.EOF){return nil,errors.New("Avro schema input must contain exactly one JSON value")};if err:=removeAvroFieldDefaults(root,0);err!=nil{return nil,err};return json.Marshal(root)}

func removeAvroFieldDefaults(value any,depth int)error{if depth>schemajson.DefaultDepth{return errors.New("Avro schema nesting exceeds limit")};switch schema:=value.(type){
    case []any:for _,branch:=range schema{if err:=removeAvroFieldDefaults(branch,depth+1);err!=nil{return err}}
    case map[string]any:
        rawType,present:=schema["type"];if !present{return nil};if err:=removeAvroFieldDefaults(rawType,depth+1);err!=nil{return err};name,ok:=rawType.(string);if !ok{return nil}
        switch name{
        case "record","error":fields,ok:=schema["fields"].([]any);if !ok{return nil};for _,rawField:=range fields{field,ok:=rawField.(map[string]any);if !ok{continue};delete(field,"default");if fieldType,present:=field["type"];present{if err:=removeAvroFieldDefaults(fieldType,depth+1);err!=nil{return err}}}
        case "array":if items,present:=schema["items"];present{return removeAvroFieldDefaults(items,depth+1)}
        case "map":if values,present:=schema["values"];present{return removeAvroFieldDefaults(values,depth+1)}
        }
    };return nil
}
