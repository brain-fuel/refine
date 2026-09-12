package value

import (
    "errors"
    "testing"
)

func mapText(t *testing.T,raw string)Text{t.Helper();value,err:=ReadText(raw);if err!=nil{t.Fatal(err)};return value}

func TestMapDataIsImmutableExactAndOrderIndependent(t *testing.T){
    decomposed:=mapText(t,`"e\u0301"`);composed:=mapText(t,`"\u00e9"`);unpaired:=mapText(t,`"\ud800"`);input:=[]MapEntry{{composed,OfNumber(Integer(2))},{decomposed,OfNumber(Integer(1))},{unpaired,OfBool(true)}};left,err:=Map(input);if err!=nil{t.Fatal(err)};input[0].Value=OfBool(false);entries:=left.Entries();if len(entries)!=3||!entries[0].Key.Equal(decomposed)||!entries[1].Key.Equal(composed)||!entries[2].Key.Equal(unpaired){t.Fatalf("map was normalized or not UTF-16 sorted: %v",entries)};entries[0].Value=OfBool(false);found,ok:=left.LookupKey(decomposed);number,isNumber:=found.Number();if !ok||!isNumber||number.Show()!="1"{t.Fatal("map constructor or accessor leaked mutable storage")}
    right,err:=Map([]MapEntry{{unpaired,OfBool(true)},{decomposed,OfNumber(Integer(1))},{composed,OfNumber(Integer(2))}});if err!=nil||!equalData(left,right){t.Fatal("map entry order affected equality")};if equalData(left,recordData(t,DataField{"e",OfNumber(Integer(1))})){t.Fatal("map collapsed into a record")}
    sameA:=mapText(t,`"a"`);sameEscape:=mapText(t,`"\u0061"`);if _,err:=Map([]MapEntry{{sameA,OfBool(true)},{sameEscape,OfBool(false)}});err==nil{t.Fatal("decoded duplicate map key accepted")}
    stop:=errors.New("stop");if _,err:=left.EqualWith(right,func(uint64)error{return stop});err!=stop{t.Fatal("map equality budget failure lost")}
}
