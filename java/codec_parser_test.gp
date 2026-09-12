package java

import (
    "crypto/sha256"
    "fmt"
    "math/rand"
    "strings"
    "testing"
    "goforge.dev/refine/language"
)

// Hash the parser's structural tree, not formatting or inferred types. The
// reader deliberately discards source positions and where annotation metadata,
// but must preserve every expression/type/pattern edge and field order.
type readShape struct{kind string;text string;names []string;children []readShape}
func shapeExpr(e *language.Expr)readShape{
    s:=readShape{}
    match e.Form{
    case language.NumberLiteral(raw):s.kind,s.text="number",raw
    case language.TextLiteral(raw):s.kind,s.text="text",raw
    case language.BoolLiteral(b):s.kind,s.text="bool","False";if b{s.text="True"}
    case language.Variable(n):s.kind,s.text="variable",n
    case language.Apply(a,b):s.kind="apply";s.children=[]readShape{shapeExpr(a),shapeExpr(b)}
    case language.Project(a,n):s.kind,s.text="project",n;s.children=[]readShape{shapeExpr(a)}
    case language.Unary(op,a):s.kind,s.text="unary",op;s.children=[]readShape{shapeExpr(a)}
    case language.Binary(op,a,b):s.kind,s.text="binary",op;s.children=[]readShape{shapeExpr(a),shapeExpr(b)}
    case language.Conditional(a,b,c):s.kind="if";s.children=[]readShape{shapeExpr(a),shapeExpr(b),shapeExpr(c)}
    case language.Let(n,annotation,a,b):s.kind,s.text="let",n;if annotation!=nil{s.children=append(s.children,shapeType(annotation))};s.children=append(s.children,shapeExpr(a),shapeExpr(b))
    case language.ListLiteral(items):s.kind="list";for _,item:=range items{s.children=append(s.children,shapeExpr(item))}
    case language.RecordLiteral(fields):s.kind="record";for _,field:=range fields{s.names=append(s.names,field.Name);s.children=append(s.children,shapeExpr(field.Value))}
    case language.MapLiteral(entries):s.kind="map";for _,entry:=range entries{s.names=append(s.names,entry.Key);s.children=append(s.children,shapeExpr(entry.Value))}
    case language.Case(subject,arms):s.kind="case";s.children=append(s.children,shapeExpr(subject));for _,arm:=range arms{s.children=append(s.children,shapePattern(arm.Pattern),shapeExpr(arm.Body))}
    }
    return s
}
func shapeType(t *language.Type)readShape{
    s:=readShape{}
    match t.Form{
    case language.NamedType(n):s.kind,s.text="type-name",n
    case language.ListType(a):s.kind="type-list";s.children=[]readShape{shapeType(a)}
    case language.AppliedType(a,b):s.kind="type-apply";s.children=[]readShape{shapeType(a),shapeType(b)}
    case language.ArrowType(a,b):s.kind="type-arrow";s.children=[]readShape{shapeType(a),shapeType(b)}
    case language.RecordType(fields):s.kind="type-record";for _,field:=range fields{s.names=append(s.names,field.Name);s.children=append(s.children,shapeType(field.Type))}
    case language.RefinedType(base,rules):s.kind="type-refined";s.children=append(s.children,shapeType(base));for _,rule:=range rules{s.children=append(s.children,shapeExpr(rule.Predicate));if rule.Message!=nil{s.children=append(s.children,shapeExpr(rule.Message))}}
    }
    return s
}
func shapePattern(p *language.Pattern)readShape{
    s:=readShape{}
    match p.Form{
    case language.BindPattern(n):s.kind,s.text="pattern-bind",n
    case language.WildPattern():s.kind="pattern-wild"
    case language.LiteralPattern(e):s.kind="pattern-literal";s.children=[]readShape{shapeExpr(e)}
    case language.ConstructorPattern(n,children):s.kind,s.text="pattern-constructor",n;for _,child:=range children{s.children=append(s.children,shapePattern(child))}
    case language.ListPattern(items):s.kind="pattern-list";for _,item:=range items{s.children=append(s.children,shapePattern(item))}
    case language.ConsPattern(a,b):s.kind="pattern-cons";s.children=[]readShape{shapePattern(a),shapePattern(b)}
    }
    return s
}
func parserShape(source string)string{
    parsed,err:=language.ParseExpression(source)
    if err!=nil{if e,ok:=err.(*language.Error);ok&&e.Code=="language.limit"{return "parse:evaluation.budget"};return "parse:read.syntax"}
    digest:=sha256.New();stack:=[]readShape{shapeExpr(parsed)}
    for len(stack)>0{last:=len(stack)-1;node:=stack[last];stack=stack[:last]
        fmt.Fprintf(digest,"%s\x00%s\x00%d\x00",node.kind,node.text,len(node.names));for _,name:=range node.names{fmt.Fprintf(digest,"%s\x00",name)};fmt.Fprintf(digest,"%d\x00",len(node.children))
        for i:=len(node.children)-1;i>=0;i--{stack=append(stack,node.children[i])}
    }
    return fmt.Sprintf("parse:%x",digest.Sum(nil))
}
func readerSyntaxCorpus(t *testing.T)[]string{
    t.Helper()
    values:=[]string{"1", "-2/3", "True", `"😀\ud800"`, "x", "𐐀", "Ᲊ", "[1,2]", "{x=1,y=False}", "(Just (-1))", "1 + 2 * 3", "a : b ++ c", "a.b x.y", "type", "then", "text", "number", "eof"}
    result:=append([]string{},values...)
    for _,a:=range values{for _,b:=range values{
        result=append(result,"if "+a+" then "+b+" else x", "let x = "+a+" in "+b, "case "+a+" of { C x -> "+b+"; _ -> 0 }", "["+a+", "+b+"]", "("+a+") "+b)
    }}
    for _,typ:=range []string{"Int","[Int]","Maybe Int","a -> b -> c","(a -> b) -> c","{x :: Int where it > 0, y :: Maybe String}","Int where True @steps 1 @code \"x\" @message \"ok\"","Int where True @steps 18446744073709551615","Int where True @steps 18446744073709551616","Int where True @steps 1.0","Int where True @code \"\"","Int where True @message (show it) where False","Int where True @steps 1 @steps 2"}{
        result=append(result,"let x :: "+typ+" = 1 in x")
    }
    for _,pattern:=range []string{"_","x","C x y","C (D x) [a,b]","x : y : []","-1","True",`"a"`,"[x,]","(C x) : xs","{x=1}","if","C {x=1}"}{result=append(result,"case x of { "+pattern+" -> 1; _ -> 0 }")}
    tokens:=[]string{"1","-","/","(",")","[","]","{","}",",",";","=","::","->","where","@","steps","message","code","if","then","else","case","of","let","in","x","C","True","text","eof","𐐀","ﬀ",`"a"`,"\n","{-\n-}","--comment\n"}
    rng:=rand.New(rand.NewSource(908172))
    for i:=0;i<10000;i++{var source strings.Builder;for count:=rng.Intn(35)+1;count>0;count--{source.WriteString(tokens[rng.Intn(len(tokens))]);source.WriteByte(' ')};result=append(result,source.String())}
    // Limits are checked both on parser recursion and on completed AST height.
    for _,depth:=range []int{250,254,255,256,257,510,511,512,513,600}{
        result=append(result,strings.Repeat("(",depth)+"1"+strings.Repeat(")",depth),strings.Repeat("1+",depth)+"1",strings.Repeat("1+",depth)+"1)","let x :: "+strings.Repeat("[",depth)+"Int"+strings.Repeat("]",depth)+" = 1 in x","case x of { "+strings.Repeat("(",depth)+"C"+strings.Repeat(")",depth)+" -> 1 }")
    }
    return result
}

const readerParserHarnessJava = `
    static String parseShape(String text) throws Exception {
        Class<?> parser = Class.forName("example.read.ContractRuntime$ValueParser");
        var constructor = parser.getDeclaredConstructor(String.class); constructor.setAccessible(true);
        var parse = parser.getDeclaredMethod("parse"); parse.setAccessible(true);
        Object root;
        try { root = parse.invoke(constructor.newInstance(text)); }
        catch (java.lang.reflect.InvocationTargetException error) { var failure = error.getCause(); var code = failure.getClass().getDeclaredField("code"); code.setAccessible(true); return "parse:" + code.get(failure); }
        Class<?> node = root.getClass();
        var kind = node.getDeclaredMethod("kind"); kind.setAccessible(true);
        var content = node.getDeclaredMethod("text"); content.setAccessible(true);
        var args = node.getDeclaredMethod("args"); args.setAccessible(true);
        var names = node.getDeclaredMethod("names"); names.setAccessible(true);
        var digest = java.security.MessageDigest.getInstance("SHA-256");
        var pending = new java.util.ArrayDeque<Object>(); pending.push(root);
        while (!pending.isEmpty()) {
            Object current = pending.pop(); var fields = (List<?>)names.invoke(current); var children = (List<?>)args.invoke(current);
            StringBuilder header = new StringBuilder().append(kind.invoke(current)).append('\0').append(content.invoke(current)).append('\0').append(fields.size()).append('\0');
            for (Object field : fields) header.append(field).append('\0'); header.append(children.size()).append('\0');
            digest.update(header.toString().getBytes(StandardCharsets.UTF_8));
            for (int i = children.size() - 1; i >= 0; i--) pending.push(children.get(i));
        }
        return "parse:" + HexFormat.of().formatHex(digest.digest());
    }
`
