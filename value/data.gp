package value

import (
    "errors"
    "sort"
)

// Data is an immutable, function-free payload tree. It does not assert that a
// schema's structure or refinements have been validated. Nominal type identity
// belongs to the checked contract; wrappers do not change this raw payload.
// Its zero value is the explicit Null constructor, never an absent field.
type Data struct { node *dataNode }
type DataKind enum { NumberData; TextData; BoolData; ListData; RecordData; VariantData; MapData }
type dataNode struct {
    kind DataKind
    number Number
    text Text
    boolean bool
    items []Data
    fields []DataField
    entries []MapEntry
    name string
}
type DataField struct { Name string; Value Data }
type MapEntry struct { Key Text; Value Data }

func OfNumber(n Number) Data { return Data{node:&dataNode{kind:NumberData(),number:n}} }
func OfText(t Text) Data { return Data{node:&dataNode{kind:TextData(),text:t}} }
func OfBool(b bool) Data { return Data{node:&dataNode{kind:BoolData(),boolean:b}} }
func List(items []Data) Data { return Data{node:&dataNode{kind:ListData(),items:append([]Data(nil),items...)}} }

// Map constructs an immutable string-keyed map. Entry order has no semantic
// meaning: construction sorts by exact UTF-16 code units. Escape spelling is
// already decoded by Text, while case and Unicode normalization remain exact.
func Map(entries []MapEntry)(Data,error) {
    copied:=append([]MapEntry(nil),entries...)
    sort.Slice(copied,func(i,j int)bool{return compareTextUnits(copied[i].Key,copied[j].Key)<0})
    for i:=1;i<len(copied);i++{if copied[i-1].Key.Equal(copied[i].Key){return Data{},errors.New("duplicate map key")}}
    return Data{node:&dataNode{kind:MapData(),entries:copied}},nil
}

func compareTextUnits(a,b Text)int{left,right:=a.units,b.units;limit:=len(left);if len(right)<limit{limit=len(right)};for i:=0;i<limit;i++{if left[i]<right[i]{return -1};if left[i]>right[i]{return 1}};if len(left)<len(right){return -1};if len(left)>len(right){return 1};return 0}

// Record field order is retained. Duplicate names are an error, even if their
// values agree. Native escaped UTF-16 object keys remain in schemajson.Node;
// these are checked-language field identifiers, not a native JSON AST.
func Record(fields []DataField) (Data, error) {
    seen := make(map[string]bool)
    for _, field := range fields {
        if field.Name == "" || seen[field.Name] { return Data{}, errors.New("empty or duplicate record field") }
        seen[field.Name] = true
    }
    return Data{node:&dataNode{kind:RecordData(),fields:append([]DataField(nil),fields...)}},nil
}

// Variant distinguishes Nothing/Just, Null/NonNull, Err/Ok, and user-defined
// alternatives. Constructor names/arity are checked against the contract later.
func Variant(name string, args []Data) (Data,error) {
    if name == "" { return Data{},errors.New("empty constructor name") }
    return Data{node:&dataNode{kind:VariantData(),name:name,items:append([]Data(nil),args...)}},nil
}
func (d Data) Kind() DataKind { if d.node == nil { return VariantData() }; return d.node.kind }
func (d Data) Number() (Number,bool) { match d.Kind() { case NumberData(): return d.node.number,true; case _: return Number{},false } }
func (d Data) Text() (Text,bool) { match d.Kind() { case TextData(): return d.node.text,true; case _: return Text{},false } }
func (d Data) Boolean() (bool,bool) { match d.Kind() { case BoolData(): return d.node.boolean,true; case _: return false,false } }
func (d Data) Elements() []Data { if d.node == nil { return nil }; return append([]Data(nil),d.node.items...) }
func (d Data) Fields() []DataField { if d.node == nil { return nil }; return append([]DataField(nil),d.node.fields...) }
func (d Data) Entries() []MapEntry { if d.node==nil{return nil};return append([]MapEntry(nil),d.node.entries...) }
// Size returns the immediate element/argument/field count without allocating.
func (d Data) Size() int { if d.node==nil{return 0};match d.Kind(){case RecordData():return len(d.node.fields);case ListData():return len(d.node.items);case VariantData():return len(d.node.items);case MapData():return len(d.node.entries);case _:return 0} }
func (d Data) Constructor() (string,bool) {
    if d.node == nil { return "Null",true }
    match d.Kind() { case VariantData(): return d.node.name,true; case _: return "",false }
}
func (d Data) Lookup(name string) (Data,bool) {
    if d.node != nil { for _, field := range d.node.fields { if field.Name == name { return field.Value,true } } }
    return Data{},false
}
func (d Data) LookupKey(key Text)(Data,bool){if d.node!=nil{match d.Kind(){case MapData():low,high:=0,len(d.node.entries);for low<high{middle:=low+(high-low)/2;if compareTextUnits(d.node.entries[middle].Key,key)<0{low=middle+1}else{high=middle}};if low<len(d.node.entries)&&d.node.entries[low].Key.Equal(key){return d.node.entries[low].Value,true};case _:}};return Data{},false}

// ReplaceFields applies all changes to an existing record in one immutable
// transformation. It does not validate refinements: the validating update layer
// must validate the completed candidate once, never intermediate field states.
// Missing targets and duplicate edits fail without modifying any input.
func (d Data) ReplaceFields(changes []DataField) (Data,error) {
    match d.Kind() {
    case RecordData():
    case _: return Data{},errors.New("field update requires a record")
    }
    edits := make(map[string]Data)
    for _, field := range changes {
        if _,found := edits[field.Name]; found { return Data{},errors.New("duplicate field update") }
        if _,found := d.Lookup(field.Name); !found { return Data{},errors.New("field update target does not exist") }
        edits[field.Name] = field.Value
    }
    fields := d.Fields()
    for i := range fields { if updated,found := edits[fields[i].Name]; found { fields[i].Value = updated } }
    return Record(fields)
}

// EqualWith is structural equality, with explicit work charging. Record order
// does not affect equality; list/constructor argument order does. The callback
// is called before each compared node and each scalar code unit/digit. The
// iterative traversal is safe for trees deeper than the Go call stack.
func (d Data) EqualWith(other Data, step func(uint64) error) (bool,error) {
    type pair struct { left Data; right Data }
    pending := []pair{{d,other}}
    for len(pending) > 0 {
        if err := step(1); err != nil { return false,err }
        current := pending[len(pending)-1]; pending = pending[:len(pending)-1]
        a,b := current.left,current.right
        match a.Kind() {
        case NumberData():
            x,_ := a.Number(); y,ok := b.Number(); if !ok { return false,nil }
            if err := step(uint64(len(x.Show())+len(y.Show()))); err != nil { return false,err }
            if x.Show() != y.Show() { return false,nil }
        case TextData():
            x,_ := a.Text(); y,ok := b.Text(); if !ok { return false,nil }
            if err := step(uint64(x.Length()+y.Length())); err != nil { return false,err }
            if !x.Equal(y) { return false,nil }
        case BoolData():
            x,_ := a.Boolean(); y,ok := b.Boolean(); if !ok || x != y { return false,nil }
        case ListData():
            match b.Kind() { case ListData(): case _: return false,nil }
            if a.Size()!=b.Size(){return false,nil};if err:=step(uint64(a.Size()));err!=nil{return false,err}
            x,y := a.node.items,b.node.items
            for i := range x { pending = append(pending,pair{x[i],y[i]}) }
        case VariantData():
            name,_ := a.Constructor(); otherName,ok := b.Constructor(); if !ok || name != otherName { return false,nil }
            if a.Size()!=b.Size(){return false,nil};if err:=step(uint64(a.Size()+len(name)));err!=nil{return false,err}
            var x,y []Data
            if a.node!=nil{x=a.node.items};if b.node!=nil{y=b.node.items}
            for i := range x { pending = append(pending,pair{x[i],y[i]}) }
        case RecordData():
            match b.Kind() { case RecordData(): case _: return false,nil }
            if a.Size()!=b.Size(){return false,nil}
            // Sorting copied fields avoids quadratic lookups. Charge the
            // deterministic upper bound before sorting, independent of order.
            cost := uint64(1); for n := a.Size(); n > 1; n >>= 1 { cost++ }
            names:=uint64(0);for _,field:=range a.node.fields{names+=uint64(len(field.Name))};for _,field:=range b.node.fields{names+=uint64(len(field.Name))}
            if err := step((uint64(a.Size())*2+names)*cost); err != nil { return false,err }
            x,y := a.Fields(),b.Fields()
            sort.Slice(x,func(i,j int) bool { return x[i].Name < x[j].Name })
            sort.Slice(y,func(i,j int) bool { return y[i].Name < y[j].Name })
            for i := range x { if x[i].Name != y[i].Name { return false,nil }; pending = append(pending,pair{x[i].Value,y[i].Value}) }
        case MapData():
            match b.Kind(){case MapData():case _:return false,nil}
            if a.Size()!=b.Size(){return false,nil};x,y:=a.node.entries,b.node.entries
            keys:=uint64(0);for i:=range x{keys+=uint64(x[i].Key.Length()+y[i].Key.Length())};if err:=step(uint64(a.Size())*2+keys);err!=nil{return false,err}
            for i:=range x{if !x[i].Key.Equal(y[i].Key){return false,nil};pending=append(pending,pair{x[i].Value,y[i].Value})}
        }
    }
    return true,nil
}
