package java

import (
    "fmt"
    "regexp/syntax"
    "sort"
    "strings"
    "unicode"
)

// Freeze the source parser's Unicode vocabulary, including category aliases.
// Values are canonical inclusive ranges, not JDK-dependent character queries.
func buildRegexClassesJava()string {
    names:=map[string]bool{"Any":true,"Assigned":true,"ASCII":true}
    for name:=range unicode.Categories{names[name]=true};for name:=range unicode.Scripts{names[name]=true};for name:=range unicode.CategoryAliases{names[name]=true}
    ordered:=[]string{};for name:=range names{ordered=append(ordered,name)};sort.Strings(ordered)
    var data strings.Builder
    for _,name:=range ordered{
        canonical:="";for _,r:=range name{if r=='_'||r=='-'||r==' '{continue};if r>='A'&&r<='Z'{r+=32};canonical+=string(r)}
        for _,fold:=range []bool{false,true}{
            source:=`\p{`+name+`}`;if fold{source="(?i)"+source};node,err:=syntax.Parse(source,syntax.Perl)
            // A Unicode table key is not necessarily accepted by Go's regex
            // lookup (notably underscore-bearing script names). Keep that
            // rejection; do not invent extra syntax by exposing every table.
            if err!=nil{continue}
            // Singleton categories and the universal category normalize to
            // literal/any nodes. Recover their ranges explicitly.
            if node.Op==syntax.OpLiteral&&len(node.Rune)==1{
                point:=node.Rune[0];points:=[]int{int(point)};if node.Flags&syntax.FoldCase!=0{for f:=unicode.SimpleFold(point);f!=point;f=unicode.SimpleFold(f){points=append(points,int(f))}};sort.Ints(points);node.Rune=nil;for _,r:=range points{node.Rune=append(node.Rune,rune(r),rune(r))}
            }else if node.Op==syntax.OpAnyChar{node.Rune=[]rune{0,unicode.MaxRune}}else if node.Op==syntax.OpAnyCharNotNL{node.Rune=[]rune{0,9,11,unicode.MaxRune}}else if node.Op!=syntax.OpCharClass{panic(fmt.Sprintf("Unicode class %s has op %v",source,node.Op))}
            fmt.Fprintf(&data,"%s:%t:",canonical,fold);for i,r:=range node.Rune{if i>0{data.WriteByte(',')};fmt.Fprint(&data,r)};data.WriteByte(';')
        }
    }
    raw:=data.String();chunks:=[]string{}
    for len(raw)>8000{chunks=append(chunks,javaQuote(raw[:8000]));raw=raw[8000:]};chunks=append(chunks,javaQuote(raw))
    return "    private static final class UnicodeClasses {\n        static final java.util.Map<String,List<Integer>> VALUES = load();\n        static java.util.Map<String,List<Integer>> load() {\n            var result = new java.util.HashMap<String,List<Integer>>();\n            for (String entry : String.join(\"\", List.of("+strings.Join(chunks,",")+" )).split(\";\")) {\n                String[] parts = entry.split(\":\", -1); var runes = new ArrayList<Integer>();\n                if (!parts[2].isEmpty()) for (String point : parts[2].split(\",\")) runes.add(Integer.valueOf(point));\n                result.put(parts[0]+\":\"+parts[1], List.copyOf(runes));\n            }\n            return java.util.Map.copyOf(result);\n        }\n    }\n"
}

var regexClassesSource = buildRegexClassesJava()

// Adapted from Go regexp/syntax parse.go. The full Go BSD notice is emitted
// with RegexProgram. Parser state and mutable nodes never escape an invocation.
const regexParseJava = `
    private static Error syntaxError(String message) { return new Error("regex.syntax", message); }
    private static Error parserLimit(boolean depth) { return new Error("regex.limit", depth ? "expression nests too deeply" : "expression too large"); }
    private static final class ParseNode {
        int op, flags, min, max, capture; String name = "";
        ArrayList<Integer> runes = new ArrayList<>(); ArrayList<ParseNode> children = new ArrayList<>();
        void reset(int next) { op=next; flags=min=max=capture=0; name=""; runes=new ArrayList<>(); children=new ArrayList<>(); }
    }
    private static final class PatternParser {
        static final int FAIL=1, EMPTY=2, LITERAL=3, CLASS=4, ANY_NOT_NL=5, ANY=6,
            BEGIN_LINE=7, END_LINE=8, BEGIN_TEXT=9, END_TEXT=10, WORD=11, NOT_WORD=12,
            CAPTURE=13, STAR=14, PLUS=15, QUEST=16, REPEAT=17, CONCAT=18, ALTERNATE=19, LPAREN=128, BAR=129;
        static final long MAX_SIZE=(128L<<20)/40, MAX_RUNES=(128L<<20)/4;
        final String source; final CompileQueue queue=new CompileQueue();
        final ArrayList<ParseNode> stack=new ArrayList<>(); final java.util.ArrayDeque<ParseNode> free=new java.util.ArrayDeque<>();
        java.util.IdentityHashMap<ParseNode,Long> sizes, heights;
        int position, flags=212, captures, allocated; long numRunes, repeats; boolean lastRepeat;
        ParseNode result;
        PatternParser(String source) { this.source=source; }
        ParseNode allocate(int op) { ParseNode node=free.poll(); if(node==null){node=new ParseNode();allocated++;} node.reset(op);return node; }
        void reuse(ParseNode node) { if(heights!=null)heights.remove(node);free.push(node); }
        int peek() { return position==source.length() ? -1 : source.charAt(position); }
        int next() { if(position==source.length())return -1;int point=source.codePointAt(position);position+=Character.charCount(point);return point; }
        boolean at(String value) { return source.startsWith(value,position); }
        static boolean alnum(int point) { return point>='0'&&point<='9'||point>='a'&&point<='z'||point>='A'&&point<='Z'; }
        static boolean digit(int point) { return point>='0'&&point<='9'; }
        static int hex(int point) { return digit(point)?point-'0':point>='a'&&point<='f'?point-'a'+10:point>='A'&&point<='F'?point-'A'+10:-1; }
        static int minFold(int point) { int min=point;for(int fold=simpleFold(point);fold!=point;fold=simpleFold(fold))min=Math.min(min,fold);return min; }
        static final class MeasureFrame { final ParseNode node;int index;MeasureFrame(ParseNode node){this.node=node;} }
        long measure(ParseNode root, boolean height) {
            var cache=height?heights:sizes;var work=new java.util.ArrayDeque<MeasureFrame>();work.push(new MeasureFrame(root));
            while(!work.isEmpty()){
                var frame=work.peek();var node=frame.node;
                if(frame.index<node.children.size()){var child=node.children.get(frame.index++);if(!cache.containsKey(child))work.push(new MeasureFrame(child));continue;}
                long value=0;
                if(height){value=1;for(var child:node.children)value=Math.max(value,1+cache.get(child));}
                else switch(node.op){
                    case LITERAL -> value=node.runes.size();
                    case CAPTURE,STAR -> value=2+cache.get(node.children.getFirst());
                    case PLUS,QUEST -> value=1+cache.get(node.children.getFirst());
                    case CONCAT,ALTERNATE -> {for(var child:node.children)value=Math.min(MAX_SIZE+1,value+cache.get(child));if(node.op==ALTERNATE&&node.children.size()>1)value+=node.children.size()-1;}
                    case REPEAT -> {long child=cache.get(node.children.getFirst());value=node.max==-1?(node.min==0?2+child:1+(long)node.min*child):(long)node.max*child+node.max-node.min;}
                    default -> { }
                }
                cache.put(node,Math.max(1,value));work.pop();
            }
            return cache.get(root);
        }
        void checkSize(ParseNode node) {
            if(sizes==null){
                if(repeats==0)repeats=1;
                if(node.op==REPEAT){int n=Math.max(1,node.max==-1?node.min:node.max);repeats=n>MAX_SIZE/repeats?MAX_SIZE:repeats*n;}
                if(allocated<MAX_SIZE/repeats)return;
                sizes=new java.util.IdentityHashMap<>();for(var old:stack)if(measure(old,false)>MAX_SIZE)throw parserLimit(false);
            }
            if(measure(node,false)>MAX_SIZE)throw parserLimit(false);
        }
        void checkHeight(ParseNode node) {
            if(allocated<1000)return;
            if(heights==null){heights=new java.util.IdentityHashMap<>();for(var old:stack)if(measure(old,true)>1000)throw parserLimit(true);}
            if(measure(node,true)>1000)throw parserLimit(true);
        }
        void checkLimits(ParseNode node) { if(numRunes>MAX_RUNES)throw parserLimit(false);checkSize(node);checkHeight(node); }
        boolean maybeConcat(int point,int nextFlags){
            int n=stack.size();if(n<2)return false;var first=stack.get(n-1);var second=stack.get(n-2);
            if(first.op!=LITERAL||second.op!=LITERAL||(first.flags&1)!=(second.flags&1))return false;
            second.runes.addAll(first.runes);
            if(point>=0){first.runes=new ArrayList<>(List.of(point));first.flags=nextFlags;return true;}
            stack.removeLast();reuse(first);return false;
        }
        ParseNode push(ParseNode node){
            numRunes+=node.runes.size();var r=node.runes;
            if(node.op==CLASS&&r.size()==2&&r.get(0).equals(r.get(1))){
                if(maybeConcat(r.getFirst(),flags&~1))return null;
                node.op=LITERAL;node.runes=new ArrayList<>(List.of(r.getFirst()));node.flags=flags&~1;
            }else if(node.op==CLASS&&(r.size()==4&&r.get(0).equals(r.get(1))&&r.get(2).equals(r.get(3))&&simpleFold(r.get(0))==r.get(2)&&simpleFold(r.get(2))==r.get(0)
                ||r.size()==2&&r.get(0)+1==r.get(1)&&simpleFold(r.get(0))==r.get(1)&&simpleFold(r.get(1))==r.get(0))){
                if(maybeConcat(r.getFirst(),flags|1))return null;
                node.op=LITERAL;node.runes=new ArrayList<>(List.of(r.getFirst()));node.flags=flags|1;
            }else maybeConcat(-1,0);
            stack.add(node);checkLimits(node);return node;
        }
        void literal(int point){var node=allocate(LITERAL);node.flags=flags;node.runes.add((flags&1)!=0?minFold(point):point);push(node);}
        ParseNode op(int op){var node=allocate(op);node.flags=flags;return push(node);}
        static void appendRange(ArrayList<Integer> ranges,int low,int high){
            int n=ranges.size();for(int i=2;i<=4;i+=2)if(n>=i){int oldLow=ranges.get(n-i),oldHigh=ranges.get(n-i+1);if(low<=oldHigh+1&&oldLow<=high+1){ranges.set(n-i,Math.min(low,oldLow));ranges.set(n-i+1,Math.max(high,oldHigh));return;}}
            ranges.add(low);ranges.add(high);
        }
        static ArrayList<Integer> clean(List<Integer> ranges){
            var pairs=new ArrayList<int[]>();for(int i=0;i<ranges.size();i+=2)pairs.add(new int[]{ranges.get(i),ranges.get(i+1)});
            pairs.sort((a,b)->a[0]!=b[0]?Integer.compare(a[0],b[0]):Integer.compare(b[1],a[1]));var out=new ArrayList<Integer>();
            for(var pair:pairs)appendRange(out,pair[0],pair[1]);return out;
        }
        static void appendClass(ArrayList<Integer> out,List<Integer> ranges){for(int i=0;i<ranges.size();i+=2)appendRange(out,ranges.get(i),ranges.get(i+1));}
        static ArrayList<Integer> negate(List<Integer> ranges){var out=new ArrayList<Integer>();int next=0;for(int i=0;i<ranges.size();i+=2){if(next<ranges.get(i))appendRange(out,next,ranges.get(i)-1);next=ranges.get(i+1)+1;}if(next<=0x10ffff)appendRange(out,next,0x10ffff);return out;}
        static void foldedRange(ArrayList<Integer> out,int low,int high){
            if(low<=0x41&&high>=0x1e943||high<0x41||low>0x1e943){appendRange(out,low,high);return;}
            if(low<0x41){appendRange(out,low,0x40);low=0x41;}if(high>0x1e943){appendRange(out,0x1e944,high);high=0x1e943;}
            for(int point=low;point<=high;point++){appendRange(out,point,point);for(int fold=simpleFold(point);fold!=point;fold=simpleFold(fold))appendRange(out,fold,fold);}
        }
        static void appendLiteral(ArrayList<Integer> out,int point,int flags){if((flags&1)==0)appendRange(out,point,point);else foldedRange(out,point,point);}
        static boolean isClass(ParseNode node){return node!=null&&(node.op==LITERAL&&node.runes.size()==1||node.op==CLASS||node.op==ANY_NOT_NL||node.op==ANY);}
        static boolean matchesRune(ParseNode node,int point){return switch(node.op){case LITERAL->node.runes.size()==1&&node.runes.getFirst()==point;case CLASS->{boolean found=false;for(int i=0;i<node.runes.size();i+=2)if(node.runes.get(i)<=point&&point<=node.runes.get(i+1)){found=true;break;}yield found;}case ANY_NOT_NL->point!='\n';case ANY->true;default->false;};}
        static void mergeClass(ParseNode dst,ParseNode src){
            switch(dst.op){
                case ANY -> { }
                case ANY_NOT_NL -> {if(matchesRune(src,'\n'))dst.op=ANY;}
                case CLASS -> {if(src.op==LITERAL)appendLiteral(dst.runes,src.runes.getFirst(),src.flags);else appendClass(dst.runes,src.runes);}
                case LITERAL -> {if(!src.runes.getFirst().equals(dst.runes.getFirst())||src.flags!=dst.flags){int point=dst.runes.getFirst();dst.op=CLASS;dst.runes=new ArrayList<>();appendLiteral(dst.runes,point,dst.flags);appendLiteral(dst.runes,src.runes.getFirst(),src.flags);}}
                default -> throw new AssertionError();
            }
        }
        static void cleanAlt(ParseNode node){if(node.op!=CLASS)return;node.runes=clean(node.runes);if(node.runes.equals(List.of(0,0x10ffff))){node.op=ANY;node.runes.clear();}else if(node.runes.equals(List.of(0,9,11,0x10ffff))){node.op=ANY_NOT_NL;node.runes.clear();}}
        boolean swapBar(){
            int n=stack.size();if(n>=3&&stack.get(n-2).op==BAR&&isClass(stack.get(n-1))&&isClass(stack.get(n-3))){
                var a=stack.get(n-1);var b=stack.get(n-3);if(a.op>b.op){var temp=a;a=b;b=temp;stack.set(n-3,b);}mergeClass(b,a);reuse(a);stack.removeLast();return true;
            }
            if(n>=2&&stack.get(n-2).op==BAR){if(n>=3)cleanAlt(stack.get(n-3));var a=stack.get(n-1);stack.set(n-1,stack.get(n-2));stack.set(n-2,a);return true;}return false;
        }
        ArrayList<ParseNode> popOperands(){int i=stack.size();while(i>0&&stack.get(i-1).op<LPAREN)i--;var operands=new ArrayList<>(stack.subList(i,stack.size()));stack.subList(i,stack.size()).clear();return operands;}
        ParseNode flatten(List<ParseNode> children,int op){if(children.size()==1)return children.getFirst();var node=allocate(op);for(var child:children){if(child.op==op){node.children.addAll(child.children);reuse(child);}else node.children.add(child);}return node;}
        void concat(){maybeConcat(-1,0);var children=popOperands();push(children.isEmpty()?allocate(EMPTY):flatten(children,CONCAT));}
        void alternate(Runnable done){var children=popOperands();if(!children.isEmpty())cleanAlt(children.getLast());if(children.isEmpty()){push(allocate(FAIL));queue.later(done);}else collapse(children,node->{push(node);queue.later(done);});}
        void collapse(List<ParseNode> children,java.util.function.Consumer<ParseNode> done){
            if(children.size()==1){queue.complete(done,children.getFirst());return;}
            var node=flatten(children,ALTERNATE);factor(node.children,children2->{node.children=children2;if(children2.size()==1){var result=children2.getFirst();reuse(node);queue.complete(done,result);}else queue.complete(done,node);});
        }
        static ParseNode leadingString(ParseNode node){if(node.op==CONCAT&&!node.children.isEmpty())node=node.children.getFirst();return node.op==LITERAL?node:null;}
        ParseNode removeString(ParseNode node,int count){
            if(node.op==CONCAT&&!node.children.isEmpty()){
                var child=node.children.getFirst();child=removeString(child,count);node.children.set(0,child);
                if(child.op==EMPTY){reuse(child);if(node.children.size()<=1){node.op=EMPTY;node.children.clear();}else if(node.children.size()==2){var old=node;node=node.children.get(1);reuse(old);}else node.children.removeFirst();}return node;
            }
            if(node.op==LITERAL){node.runes.subList(0,count).clear();if(node.runes.isEmpty())node.op=EMPTY;}return node;
        }
        static ParseNode leadingNode(ParseNode node){if(node.op==EMPTY)return null;if(node.op==CONCAT&&!node.children.isEmpty())node=node.children.getFirst();return node.op==EMPTY?null:node;}
        ParseNode removeNode(ParseNode node,boolean discard){
            if(node.op==CONCAT&&!node.children.isEmpty()){var child=node.children.removeFirst();if(discard)reuse(child);if(node.children.isEmpty())node.op=EMPTY;else if(node.children.size()==1){var old=node;node=node.children.getFirst();reuse(old);}return node;}
            if(discard)reuse(node);return allocate(EMPTY);
        }
        static boolean equal(ParseNode a,ParseNode b){
            if(a==null||b==null)return a==b;var left=new java.util.ArrayDeque<ParseNode>();var right=new java.util.ArrayDeque<ParseNode>();left.push(a);right.push(b);
            while(!left.isEmpty()){
                a=left.pop();b=right.pop();if(a.op!=b.op)return false;
                switch(a.op){
                    case END_TEXT -> {if((a.flags&256)!=(b.flags&256))return false;}
                    case LITERAL,CLASS -> {if((a.flags&1)!=(b.flags&1)||!a.runes.equals(b.runes))return false;}
                    case STAR,PLUS,QUEST,REPEAT -> {if((a.flags&32)!=(b.flags&32)||a.op==REPEAT&&(a.min!=b.min||a.max!=b.max))return false;}
                    case CAPTURE -> {if(a.capture!=b.capture||!a.name.equals(b.name))return false;}
                    default -> { }
                }
                if(a.children.size()!=b.children.size())return false;for(int i=0;i<a.children.size();i++){left.push(a.children.get(i));right.push(b.children.get(i));}
            }return true;
        }
        void factor(ArrayList<ParseNode> children,java.util.function.Consumer<ArrayList<ParseNode>> done){
            if(children.size()<2){queue.complete(done,children);return;}queue.later(new Factor(children,done));
        }
        final class Factor implements Runnable {
            ArrayList<ParseNode> children,out=new ArrayList<>();final java.util.function.Consumer<ArrayList<ParseNode>> done;
            int round=1,start,index,stringFlags;List<Integer> prefixString=List.of();ParseNode first;
            Factor(ArrayList<ParseNode> children,java.util.function.Consumer<ArrayList<ParseNode>> done){this.children=children;this.done=done;}
            @Override public void run(){
                while(round<=2){
                    if(index>children.size()){children=out;out=new ArrayList<>();round++;start=index=0;first=null;continue;}
                    List<Integer> nextString=List.of();int nextFlags=0;ParseNode nextFirst=null;
                    if(index<children.size()){
                        if(round==1){var node=leadingString(children.get(index));if(node!=null){nextString=node.runes;nextFlags=node.flags&1;}
                            if(nextFlags==stringFlags){int same=0;while(same<prefixString.size()&&same<nextString.size()&&prefixString.get(same).equals(nextString.get(same)))same++;if(same>0){prefixString=new ArrayList<>(prefixString.subList(0,same));index++;continue;}}
                        }else{nextFirst=leadingNode(children.get(index));if(first!=null&&equal(first,nextFirst)&&(isClass(first)||first.op==REPEAT&&first.min==first.max&&isClass(first.children.getFirst()))){index++;continue;}}
                    }
                    int end=index,begin=start;ParseNode prefix=null;
                    if(end==begin+1)out.add(children.get(begin));
                    else if(end>begin+1){
                        if(round==1){prefix=allocate(LITERAL);prefix.flags=stringFlags;prefix.runes=new ArrayList<>(prefixString);for(int j=begin;j<end;j++){children.set(j,removeString(children.get(j),prefixString.size()));checkLimits(children.get(j));}}
                        else{prefix=first;for(int j=begin;j<end;j++){children.set(j,removeNode(children.get(j),j!=begin));checkLimits(children.get(j));}}
                    }
                    start=index++;prefixString=new ArrayList<>(nextString);stringFlags=nextFlags;first=nextFirst;
                    if(prefix!=null){var saved=prefix;collapse(new ArrayList<>(children.subList(begin,end)),suffix->{var node=allocate(CONCAT);node.children.add(saved);node.children.add(suffix);out.add(node);queue.later(this);});return;}
                }
                // Merge runs of classes, selecting Go's most complex node as
                // destination so flags and rune accounting remain identical.
                out=new ArrayList<>();start=0;
                for(int i=0;i<=children.size();i++){
                    if(i<children.size()&&isClass(children.get(i)))continue;
                    if(i==start+1)out.add(children.get(start));
                    else if(i>start+1){int max=start;for(int j=start+1;j<i;j++){var a=children.get(max);var b=children.get(j);if(a.op<b.op||a.op==b.op&&a.runes.size()<b.runes.size())max=j;}
                        java.util.Collections.swap(children,start,max);var dst=children.get(start);for(int j=start+1;j<i;j++){mergeClass(dst,children.get(j));reuse(children.get(j));}cleanAlt(dst);out.add(dst);
                    }
                    if(i<children.size())out.add(children.get(i));start=i+1;
                }
                var finalChildren=new ArrayList<ParseNode>();for(int i=0;i<out.size();i++){if(i+1<out.size()&&out.get(i).op==EMPTY&&out.get(i+1).op==EMPTY)continue;finalChildren.add(out.get(i));}
                queue.complete(done,finalChildren);
            }
        }
        void repetition(int op,int min,int max){
            int nextFlags=flags;if(peek()=='?'){position++;nextFlags^=32;}
            if(lastRepeat)throw syntaxError("invalid nested repetition operator");
            if(stack.isEmpty()||stack.getLast().op>=LPAREN)throw syntaxError("missing argument to repetition operator");
            var node=allocate(op);node.flags=nextFlags;node.min=min;node.max=max;node.children.add(stack.getLast());stack.set(stack.size()-1,node);checkLimits(node);
            if(op==REPEAT&&(min>=2||max>=2)){
                record Limit(ParseNode node,int count){}var work=new java.util.ArrayDeque<Limit>();work.push(new Limit(node,1000));
                while(!work.isEmpty()){var item=work.pop();var sub=item.node();int count=item.count();if(sub.op==REPEAT){int m=sub.max;if(m==0)continue;if(m<0)m=sub.min;if(m>count)throw syntaxError("invalid repeat count");if(m>0)count/=m;}for(var child:sub.children)work.push(new Limit(child,count));}
            }
        }
        int parseInt(){if(!digit(peek()))return -2;int start=position;if(peek()=='0'&&position+1<source.length()&&digit(source.charAt(position+1)))return -2;while(digit(peek()))position++;int value=0;for(int i=start;i<position;i++){if(value>=100000000)return -1;value=value*10+source.charAt(i)-'0';}return value;}
        int[] repeatCounts(){int start=position++;int min=parseInt(),max=min;if(min==-2||peek()==-1){position=start;return null;}if(peek()==','){position++;if(peek()=='}')max=-1;else{max=parseInt();if(max==-2){position=start;return null;}if(max<0)min=-1;}}if(peek()!='}'){position=start;return null;}position++;return new int[]{min,max};}
        void perlFlags(){
            int start=position;position+=2;
            boolean python=source.length()-start>4&&at("P<"),named=source.length()-start>3&&peek()=='<';
            if(python||named){position+=python?2:1;int end=source.indexOf('>',position);if(end<0)throw syntaxError("invalid named capture");String name=source.substring(position,end);if(name.isEmpty())throw syntaxError("invalid named capture");for(int i=0;i<name.length();i++)if(name.charAt(i)!='_'&&!alnum(name.charAt(i)))throw syntaxError("invalid named capture");position=end+1;captures++;var node=op(LPAREN);node.capture=captures;node.name=name;return;}
            int nextFlags=flags,sign=1;boolean saw=false;
            while(position<source.length()){
                int point=next();switch(point){
                    case 'i' -> {nextFlags|=1;saw=true;}
                    case 'm' -> {nextFlags&=~16;saw=true;}
                    case 's' -> {nextFlags|=8;saw=true;}
                    case 'U' -> {nextFlags|=32;saw=true;}
                    case '-' -> {if(sign<0)throw syntaxError("invalid or unsupported Perl syntax");sign=-1;nextFlags=(~nextFlags)&0xffff;saw=false;}
                    case ':',')' -> {if(sign<0){if(!saw)throw syntaxError("invalid or unsupported Perl syntax");nextFlags=(~nextFlags)&0xffff;}if(point==':')op(LPAREN);flags=nextFlags;return;}
                    default -> throw syntaxError("invalid or unsupported Perl syntax");
                }
            }throw syntaxError("invalid or unsupported Perl syntax");
        }
        int escape(){
            position++;if(peek()==-1)throw syntaxError("trailing backslash at end of expression");int point=next();
            if(point>='0'&&point<='7'){
                if(point!='0'&&(peek()<'0'||peek()>'7'))throw syntaxError("invalid escape sequence");int value=point-'0';for(int i=1;i<3&&peek()>='0'&&peek()<='7';i++)value=value*8+next()-'0';return value;
            }
            if(point=='x'){
                if(peek()==-1)throw syntaxError("invalid escape sequence");int value=0;
                if(peek()=='{'){position++;int count=0;while(peek()!='}'){int h=hex(next());if(h<0)throw syntaxError("invalid escape sequence");value=value*16+h;if(value>0x10ffff)throw syntaxError("invalid escape sequence");count++;}position++;if(count==0)throw syntaxError("invalid escape sequence");return value;}
                int x=hex(next()),y=hex(next());if(x<0||y<0)throw syntaxError("invalid escape sequence");return x*16+y;
            }
            return switch(point){case 'a'->7;case 'f'->12;case 'n'->10;case 'r'->13;case 't'->9;case 'v'->11;default->{if(point<128&&!alnum(point))yield point;throw syntaxError("invalid escape sequence");}};
        }
        static List<Integer> group(String name){return switch(name){
            case "alnum"->List.of(48,57,65,90,97,122);case "alpha"->List.of(65,90,97,122);case "ascii"->List.of(0,127);
            case "blank"->List.of(9,9,32,32);case "cntrl"->List.of(0,31,127,127);case "digit"->List.of(48,57);
            case "graph"->List.of(33,126);case "lower"->List.of(97,122);case "print"->List.of(32,126);
            case "punct"->List.of(33,47,58,64,91,96,123,126);case "space"->List.of(9,13,32,32);case "upper"->List.of(65,90);
            case "word"->List.of(48,57,65,90,95,95,97,122);case "xdigit"->List.of(48,57,65,70,97,102);default->null;
        };}
        void appendGroup(ArrayList<Integer> out,List<Integer> ranges,boolean negative){
            if((flags&1)!=0){var folded=new ArrayList<Integer>();for(int i=0;i<ranges.size();i+=2)foldedRange(folded,ranges.get(i),ranges.get(i+1));ranges=clean(folded);}
            appendClass(out,negative?negate(ranges):ranges);
        }
        boolean perlClass(ArrayList<Integer> out){
            if(peek()!='\\'||position+1>=source.length())return false;char c=source.charAt(position+1);
            List<Integer> ranges=switch(c){case 'd','D'->group("digit");case 's','S'->List.of(9,10,12,13,32,32);case 'w','W'->group("word");default->null;};
            if(ranges==null)return false;position+=2;appendGroup(out,ranges,c>='A'&&c<='Z');return true;
        }
        boolean unicodeClass(ArrayList<Integer> out){
            if(!at("\\p")&&!at("\\P"))return false;boolean negative=source.charAt(position+1)=='P';position+=2;String name;
            if(peek()=='{'){position++;int end=source.indexOf('}',position);if(end<0)throw syntaxError("invalid character class range");name=source.substring(position,end);position=end+1;}
            else{int point=next();if(point<0)throw syntaxError("invalid character class range");name=new String(Character.toChars(point));}
            if(name.startsWith("^")){negative=!negative;name=name.substring(1);}
            var canonical=new StringBuilder();for(int i=0;i<name.length();i++){char c=name.charAt(i);if(c=='_'||c=='-'||c==' ')continue;canonical.append(c>='A'&&c<='Z'?(char)(c+32):c);}
            var ranges=UnicodeClasses.VALUES.get(canonical+":"+((flags&1)!=0));if(ranges==null)throw syntaxError("invalid character class range");appendClass(out,negative?negate(ranges):ranges);return true;
        }
        int classChar(){if(peek()==-1)throw syntaxError("missing closing ]");return peek()=='\\'?escape():next();}
        void parseClass(){
            position++;var node=allocate(CLASS);node.flags=flags;boolean negative=peek()=='^';if(negative)position++;boolean first=true;
            while(peek()!=']'||first){first=false;
                if(at("[:")){int end=source.indexOf(":]",position+2);if(end>=0){String name=source.substring(position+2,end);boolean neg=name.startsWith("^");if(neg)name=name.substring(1);var ranges=group(name);if(ranges==null)throw syntaxError("invalid character class range");appendGroup(node.runes,ranges,neg);position=end+2;continue;}}
                if(unicodeClass(node.runes)||perlClass(node.runes))continue;
                int low=classChar(),high=low;if(peek()=='-'&&position+1<source.length()&&source.charAt(position+1)!=']'){position++;high=classChar();if(high<low)throw syntaxError("invalid character class range");}
                if((flags&1)==0)appendRange(node.runes,low,high);else foldedRange(node.runes,low,high);
            }
            position++;node.runes=clean(node.runes);if(negative)node.runes=negate(node.runes);push(node);
        }
        void close(Runnable done){
            concat();if(swapBar())stack.removeLast();alternate(()->{
                if(stack.size()<2)throw syntaxError("unexpected )");var child=stack.removeLast();var paren=stack.removeLast();if(paren.op!=LPAREN)throw syntaxError("unexpected )");flags=paren.flags;
                if(paren.capture==0)push(child);else{paren.op=CAPTURE;paren.children.add(child);push(paren);}queue.later(done);
            });
        }
        void advance(){
            while(position<source.length()){
                boolean repeated=false;
                switch(peek()){
                    case '(' -> {if(at("(?"))perlFlags();else{position++;captures++;op(LPAREN).capture=captures;}}
                    case '|' -> {position++;concat();if(!swapBar())op(BAR);}
                    case ')' -> {position++;lastRepeat=false;close(this::advance);return;}
                    case '^' -> {position++;op((flags&16)!=0?BEGIN_TEXT:BEGIN_LINE);}
                    case '$' -> {position++;var node=op((flags&16)!=0?END_TEXT:END_LINE);if((flags&16)!=0)node.flags|=256;}
                    case '.' -> {position++;op((flags&8)!=0?ANY:ANY_NOT_NL);}
                    case '[' -> parseClass();
                    case '*','+','?' -> {int c=next();repetition(c=='*'?STAR:c=='+'?PLUS:QUEST,0,0);repeated=true;}
                    case '{' -> {var counts=repeatCounts();if(counts==null){position++;literal('{');}else{if(counts[0]<0||counts[0]>1000||counts[1]>1000||counts[1]>=0&&counts[0]>counts[1])throw syntaxError("invalid repeat count");repetition(REPEAT,counts[0],counts[1]);repeated=true;}}
                    case '\\' -> {
                        if(at("\\A")||at("\\b")||at("\\B")||at("\\z")){int c=source.charAt(position+1);position+=2;op(c=='A'?BEGIN_TEXT:c=='b'?WORD:c=='B'?NOT_WORD:END_TEXT);}
                        else if(at("\\C"))throw syntaxError("invalid escape sequence");
                        else if(at("\\Q")){position+=2;int end=source.indexOf("\\E",position);if(end<0)end=source.length();while(position<end)literal(next());if(position<source.length())position+=2;}
                        else{var node=allocate(CLASS);node.flags=flags;if(unicodeClass(node.runes)||perlClass(node.runes))push(node);else{reuse(node);literal(escape());}}
                    }
                    default -> literal(next());
                }
                lastRepeat=repeated;
            }
            concat();if(swapBar())stack.removeLast();alternate(()->{if(stack.size()!=1)throw syntaxError("missing closing )");result=stack.getFirst();});
        }
        Tree parse(){
            queue.later(this::advance);queue.run();
            var frozen=new java.util.IdentityHashMap<ParseNode,Tree>();var work=new java.util.ArrayDeque<MeasureFrame>();work.push(new MeasureFrame(result));
            while(!work.isEmpty()){
                var frame=work.peek();if(frame.index<frame.node.children.size()){var child=frame.node.children.get(frame.index++);if(!frozen.containsKey(child))work.push(new MeasureFrame(child));continue;}
                var node=frame.node;var children=new ArrayList<Tree>();for(var child:node.children)children.add(frozen.get(child));
                frozen.put(node,new Tree(TreeOp.values()[node.op-1],node.flags,node.runes,children,node.min,node.max,node.capture,node.name));work.pop();
            }return frozen.get(result);
        }
    }
    /** Parse and normalize the refinement Go/RE2 dialect. Charges source work
     * before parsing; diagnostics never embed potentially private pattern text.
     */
    public static Tree parseTree(String source,Budget.Meter meter){
        Objects.requireNonNull(source);Objects.requireNonNull(meter);long size=source.length();charge(meter,size*size+1);
        for(int i=0;i<source.length();i++){char c=source.charAt(i);if(Character.isHighSurrogate(c)){if(i+1<source.length()&&Character.isLowSurrogate(source.charAt(i+1))){i++;continue;}throw syntaxError("pattern requires Unicode scalar text; use a hexadecimal escape for a surrogate");}if(Character.isLowSurrogate(c))throw syntaxError("pattern requires Unicode scalar text; use a hexadecimal escape for a surrogate");}
        return new PatternParser(source).parse();
    }
    public static RegexProgram compile(String source,Budget.Meter meter){return compileTree(parseTree(source,meter),meter);}
`
