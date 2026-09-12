package java

import (
    "fmt"
    "strings"

    "goforge.dev/refine/language"
)

// Nodes are emitted in dependency order. Each class has bounded initializer
// bytecode/constant-pool pressure, and loaders initialize classes sequentially
// before their dependents. Initialization therefore does not recurse over the
// expression/type graph on the JVM stack.
type initializerNode struct { typ string; source string }
type initializer struct { prefix string; nodes []initializerNode; checked *language.CheckedModule }
const initializerChunk = 32
const initializerLoader = 128

func (e *initializer) node(typ,source string)string {
    index:=len(e.nodes);e.nodes=append(e.nodes,initializerNode{typ,source})
    return fmt.Sprintf("%sChunk%d.n%d",e.prefix,index/initializerChunk,index)
}
func (e *initializer) literal(text string)string {
    // 8192 UTF-8 bytes imply at most 12288 modified-UTF-8 bytes, below the
    // JVM's per-constant limit even for supplementary characters and NUL.
    if len(text)<=8192{return javaQuote(text)}
    pieces:=[]string{};start:=0
    for offset:=range text{if offset-start>=8192{pieces=append(pieces,e.node("String",javaQuote(text[start:offset])));start=offset}}
    pieces=append(pieces,e.node("String",javaQuote(text[start:])))
    return e.node("String","String.join(\"\","+e.list("String",pieces)+")")
}
func (e *initializer) strings(items []string)string {
    values:=make([]string,len(items));for i,item:=range items{values[i]=e.literal(item)}
    return e.list("String",values)
}
func (e *initializer) list(typ string,items []string)string {
    if len(items)<=initializerChunk{return e.node("java.util.List<"+typ+">",javaList(items))}
    parts:=[]string{}
    for start:=0;start<len(items);start+=initializerChunk{end:=start+initializerChunk;if end>len(items){end=len(items)};parts=append(parts,e.list(typ,items[start:end]))}
    groups:=e.list("java.util.List<"+typ+">",parts)
    return e.node("java.util.List<"+typ+">",e.prefix+"Support.concat("+groups+")")
}
func (e *initializer) source(root string)string {
    chunks:=(len(e.nodes)+initializerChunk-1)/initializerChunk
    loaders:=(chunks+initializerLoader-1)/initializerLoader
    var out strings.Builder
    out.WriteString("    private static java.util.Map<String, ContractRuntime.Definition> definitions() {\n")
    for i:=0;i<loaders;i++{fmt.Fprintf(&out,"        %sLoad%d.load();\n",e.prefix,i)}
    fmt.Fprintf(&out,"        return %s;\n    }\n}\n",root)
    for start:=0;start<len(e.nodes);start+=initializerChunk{
        fmt.Fprintf(&out,"final class %sChunk%d {\n    private %sChunk%d() {}\n    static void init() {}\n",e.prefix,start/initializerChunk,e.prefix,start/initializerChunk)
        end:=start+initializerChunk;if end>len(e.nodes){end=len(e.nodes)}
        for i:=start;i<end;i++{node:=e.nodes[i];fmt.Fprintf(&out,"    static final %s n%d = %s;\n",node.typ,i,node.source)}
        out.WriteString("}\n")
    }
    for start:=0;start<chunks;start+=initializerLoader{
        fmt.Fprintf(&out,"final class %sLoad%d {\n    private %sLoad%d() {}\n    static void load() {\n",e.prefix,start/initializerLoader,e.prefix,start/initializerLoader)
        end:=start+initializerLoader;if end>chunks{end=chunks}
        for i:=start;i<end;i++{fmt.Fprintf(&out,"        %sChunk%d.init();\n",e.prefix,i)}
        out.WriteString("    }\n}\n")
    }
    fmt.Fprintf(&out,`final class %sSupport {
    private %sSupport() {}
    static <T> java.util.List<T> concat(java.util.List<java.util.List<T>> parts) {
        var result = new java.util.ArrayList<T>();
        for (var part : parts) result.addAll(part);
        return java.util.List.copyOf(result);
    }
    static <T> java.util.Map<String, T> dictionary(java.util.List<java.util.Map.Entry<String, T>> entries) {
        var result = new java.util.LinkedHashMap<String, T>();
        for (var entry : entries) if (result.putIfAbsent(entry.getKey(), entry.getValue()) != null) throw new AssertionError("duplicate checked type");
        return java.util.Map.copyOf(result);
    }
}
`,e.prefix,e.prefix)
    return out.String()
}
