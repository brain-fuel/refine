package provenance

import (
    "math/big"
    "strings"
    "unicode/utf8"

    yaml "github.com/oasdiff/yaml3"
    "goforge.dev/refine/schemajson"
)

// yamlExactScalar converts the parser's character-based columns back to byte
// offsets and verifies the source slice against the unescaped plain value.
// Tagged, quoted, anchored and multiline values are deliberately not guessed.
func yamlExactScalar(doc *openAPIProvenanceDoc,node *yaml.Node)(string,bool){if doc==nil||node==nil||node.Line<1||node.EndLine!=node.Line||node.Line>len(doc.lineStarts)||node.Column<1||node.EndColumn<node.Column{return "",false};lineStart:=doc.lineStarts[node.Line-1];lineEnd:=len(doc.resource.Source);if node.Line<len(doc.lineStarts){lineEnd=doc.lineStarts[node.Line]-1};line:=doc.resource.Source[lineStart:lineEnd];start,ok:=unicodeColumnByte(line,node.Column);if !ok{return "",false};end,ok:=unicodeColumnByte(line,node.EndColumn);if !ok||end<start{return "",false};raw:=string(line[start:end]);return raw,raw==node.Value}
func unicodeColumnByte(line []byte,column int)(int,bool){if column<1{return 0,false};wanted:=column-1;offset:=0;for count:=0;count<wanted;count++{if offset>=len(line){return 0,false};_,size:=utf8.DecodeRune(line[offset:]);if size==0{return 0,false};offset+=size};return offset,true}

func normalizeYAMLInteger(raw string)(string,bool){if len(raw)>maxJSONNumericExpansion{return "",false};text:=strings.ReplaceAll(raw,"_","");negative:=false;if strings.HasPrefix(text,"+"){text=text[1:]}else if strings.HasPrefix(text,"-"){negative=true;text=text[1:]};base:=10;if len(text)>2&&text[0]=='0'{switch text[1]{case 'b','B':base=2;text=text[2:];case 'o','O':base=8;text=text[2:];case 'x','X':base=16;text=text[2:]}};integer,ok:=new(big.Int).SetString(text,base);if !ok{return "",false};if negative{integer.Neg(integer)};result:=integer.String();if _,err:=jsonNumberExpansion(result,maxJSONNumericExpansion);err!=nil{return "",false};return result,true}
func normalizeYAMLFloat(raw string)(string,bool){if len(raw)>maxJSONNumericExpansion{return "",false};text:=strings.ReplaceAll(strings.ToLower(raw),"_","");if strings.Contains(text,"inf")||strings.Contains(text,"nan"){return "",false};sign:="";if strings.HasPrefix(text,"+"){text=text[1:]}else if strings.HasPrefix(text,"-"){sign="-";text=text[1:]};parts:=strings.SplitN(text,"e",2);mantissa:=parts[0];if strings.HasPrefix(mantissa,"."){mantissa="0"+mantissa};if strings.HasSuffix(mantissa,"."){mantissa+="0"};candidate:=sign+mantissa;if len(parts)==2{exponent:=parts[1];if strings.HasPrefix(exponent,"+"){exponent=exponent[1:]};if _,ok:=new(big.Int).SetString(exponent,10);!ok{return "",false};candidate+="e"+exponent};if _,err:=jsonNumberExpansion(candidate,maxJSONNumericExpansion);err!=nil{return "",false};doc,err:=schemajson.Parse([]byte(candidate),schemajson.Limits{Bytes:maxJSONNumericExpansion,Depth:2,Nodes:2});if err!=nil||schemajson.KindName(doc.Root().Kind())!="number"{return "",false};return candidate,true}
