package java

// Read parses the same expression grammar as Go before interpreting only its
// literal subset. Even syntactically valid function calls are never executed.
// Parser continuations are independent of evaluator continuations and never
// consume the host stack. Depth and token limits match language/parser.gp.
const codecParserJava = `
    private record ReadToken(String kind, String text) {}
    private record ReadNode(String kind, String text, List<ReadNode> args, List<String> names, int height) {
        ReadNode { args = List.copyOf(args); names = List.copyOf(names); }
    }
    private static ReadNode readNode(String kind, String text, List<ReadNode> args, List<String> names) {
        int height = 0; for (ReadNode child : args) height = Math.max(height, child.height() + 1);
        return new ReadNode(kind, text, args, names, height);
    }
    private static ReadNode readNode(String kind, String text, ReadNode... args) { return readNode(kind, text, List.of(args), List.of()); }
    private static Failure readSyntax() { return fail("read.syntax", "input is not a value in the canonical text grammar"); }
    private static Failure readLimit() { return fail("evaluation.budget", "read syntax exceeds parser resources"); }
    private static final class ValueParser {
        final List<ReadToken> tokens; int index;
        final Work work = new Work();
        ValueParser(String source) { tokens = lex(source); }
        static List<ReadToken> lex(String source) {
            if (utf8Size(source) > 16 * 1024 * 1024) throw readLimit();
            var tokens = new ArrayList<ReadToken>(); int i = 0;
            while (i < source.length()) {
                int start = i, c = source.codePointAt(i); String kind;
                if (c == ' ' || c == '\t' || c == '\r') { i++; continue; }
                if (source.startsWith("--", i)) { while (i < source.length() && source.charAt(i) != '\n') i++; continue; }
                if (source.startsWith("{-", i)) {
                    i += 2; int depth = 1;
                    while (i < source.length() && depth > 0) {
                        if (source.startsWith("{-", i)) { depth++; i += 2; }
                        else if (source.startsWith("-}", i)) { depth--; i += 2; }
                        else { if (source.charAt(i) == '\n') token(tokens, "newline", "\n"); i += Character.charCount(source.codePointAt(i)); }
                    }
                    if (depth != 0) throw readSyntax(); continue;
                }
                if (c == '\n') { i++; kind = "newline"; }
                else if (CodecUnicode.letter(c) || c == '_') {
                    i += Character.charCount(c);
                    while (i < source.length()) {
                        int next = source.codePointAt(i);
                        if (!CodecUnicode.letter(next) && !CodecUnicode.digit(next) && next != '_' && next != '\'') break;
                        i += Character.charCount(next);
                    }
                    kind = "name";
                } else if (c >= '0' && c <= '9') {
                    i++; while (asciiDigit(source, i)) i++;
                    if (i + 1 < source.length() && source.charAt(i) == '.' && asciiDigit(source, i + 1)) { i++; while (asciiDigit(source, i)) i++; }
                    if (i < source.length() && (source.charAt(i) == 'e' || source.charAt(i) == 'E')) {
                        i++; if (i < source.length() && (source.charAt(i) == '+' || source.charAt(i) == '-')) i++;
                        int exponent = i; while (asciiDigit(source, i)) i++; if (i == exponent) throw readSyntax();
                    }
                    if (i - start > 1 && c == '0' && asciiDigit(source, start + 1)) throw readSyntax();
                    kind = "number";
                } else if (c == '"') {
                    i++; boolean closed = false;
                    while (i < source.length()) {
                        char next = source.charAt(i++);
                        if (next == '\\') { if (i < source.length()) i += Character.charCount(source.codePointAt(i)); continue; }
                        if (next == '"') { closed = true; break; }
                        if (next == '\n') throw readSyntax();
                    }
                    if (!closed) throw readSyntax();
                    try { TextCodec.read(source.substring(start, i)); } catch (IllegalArgumentException failure) { throw readSyntax(); }
                    kind = "text";
                } else {
                    kind = null;
                    for (String operator : List.of("::", "->", ">=", "<=", "==", "/=", "&&", "||", "++")) if (source.startsWith(operator, i)) { kind = operator; i += 2; break; }
                    if (kind == null) {
                        if (c > 127 || "{}[](),;=|:.+-*/%<>@".indexOf(c) < 0) throw readSyntax();
                        kind = Character.toString(c); i++;
                    }
                }
                token(tokens, kind, source.substring(start, i));
            }
            tokens.add(new ReadToken("eof", "")); return tokens;
        }
        static boolean asciiDigit(String source, int i) { return i < source.length() && source.charAt(i) >= '0' && source.charAt(i) <= '9'; }
        static void token(List<ReadToken> tokens, String kind, String text) { if (tokens.size() >= 1000000) throw readLimit(); tokens.add(new ReadToken(kind, text)); }
        ReadToken peek() { return tokens.get(index); }
        ReadToken take() { ReadToken result = peek(); if (!result.kind().equals("eof")) index++; return result; }
        boolean is(String text) {
            return switch (text) {
                case "name", "number", "text", "newline", "eof" -> peek().kind().equals(text);
                default -> peek().kind().equals(text) || peek().kind().equals("name") && peek().text().equals(text);
            };
        }
        boolean accept(String text) { if (!is(text)) return false; take(); return true; }
        ReadToken need(String text) { if (!is(text)) throw readSyntax(); return take(); }
        String name() { String name = need("name").text(); if (codecReserved(name)) throw readSyntax(); return name; }
        String lowerName() { String name = name(); if (name.equals("_") || CodecUnicode.upper(name.codePointAt(0))) throw readSyntax(); return name; }
        void lines() { while (accept("newline")) {} }
        void enter(int level) { if (level >= 512) throw readLimit(); }
        boolean atomStart() { return is("number") || is("text") || is("(") || is("[") || is("{") || is("name") && !codecReserved(peek().text()); }
        boolean typeStart() { return is("(") || is("[") || is("{") || is("name") && !codecReserved(peek().text()); }
        boolean patternStart() { return is("[") || is("(") || is("number") || is("text") || is("-") || is("name") && !codecReserved(peek().text()); }
        static int precedence(String kind) {
            return switch (kind) { case "||" -> 1; case "&&" -> 2; case "==", "/=", "<", "<=", ">", ">=" -> 3; case ":", "++" -> 4; case "+", "-" -> 5; case "*", "/", "%" -> 6; default -> -1; };
        }
        ReadNode parse() {
            ReadNode[] result = new ReadNode[1]; lines();
            expression(0, 0, node -> { lines(); need("eof"); if (node.height() > 512) throw readLimit(); result[0] = node; });
            work.run(); return result[0];
        }
        void expression(int minimum, int level, Consumer<ReadNode> done) {
            work.later(() -> { enter(level); prefix(level + 1, left -> tail(left, minimum, level + 1, done)); });
        }
        void tail(ReadNode left, int minimum, int level, Consumer<ReadNode> done) {
            work.later(() -> {
                if (is("newline")) {
                    int mark = index; lines();
                    if (precedence(peek().kind()) < minimum) { index = mark; work.complete(done, left); return; }
                }
                if (is(".") && minimum <= 9) { take(); tail(readNode("project", name(), left), minimum, level, done); return; }
                if (atomStart() && minimum <= 8) { expression(9, level, right -> tail(readNode("apply", "", left, right), minimum, level, done)); return; }
                int rank = precedence(peek().kind()); if (rank < minimum) { work.complete(done, left); return; }
                String operator = take().text(); lines(); int next = operator.equals(":") || operator.equals("++") ? rank : rank + 1;
                expression(next, level, right -> tail(readNode("binary", operator, left, right), minimum, level, done));
            });
        }
        void prefix(int level, Consumer<ReadNode> done) {
            if (accept("-")) { expression(7, level, value -> work.complete(done, readNode("unary", "-", value))); return; }
            if (accept("if")) {
                lines(); expression(0, level, condition -> { lines(); need("then"); lines(); expression(0, level, yes -> {
                    lines(); need("else"); lines(); expression(0, level, no -> work.complete(done, readNode("if", "", condition, yes, no)));
                }); }); return;
            }
            if (accept("let")) {
                String name = lowerName();
                Consumer<ReadNode> bound = annotation -> { need("="); lines(); expression(0, level, value -> {
                    lines(); need("in"); lines(); expression(0, level, body -> work.complete(done, annotation == null ? readNode("let", name, value, body) : readNode("let", name, annotation, value, body)));
                }); };
                if (accept("::")) type(level, bound); else work.complete(bound, null); return;
            }
            if (accept("case")) {
                expression(0, level, subject -> { lines(); need("of"); lines(); need("{"); lines();
                    var parts = new ArrayList<ReadNode>(); parts.add(subject);
                    work.later(new Runnable() {
                        @Override public void run() {
                            if (accept("}")) { if (parts.size() == 1) throw readSyntax(); work.complete(done, readNode("case", "", parts, List.of())); return; }
                            pattern(level, p -> { need("->"); lines(); expression(0, level, body -> {
                                parts.add(p); parts.add(body); lines();
                                if (!accept(";")) { need("}"); work.complete(done, readNode("case", "", parts, List.of())); }
                                else { lines(); work.later(this); }
                            }); });
                        }
                    });
                }); return;
            }
            if (accept("(")) { lines(); expression(0, level, inner -> { lines(); need(")"); work.complete(done, inner); }); return; }
            if (accept("[")) { collection("list", "]", level, false, false, done); return; }
            if (accept("{")) { collection("record", "}", level, true, false, done); return; }
            if (is("number") || is("text")) { ReadToken token = take(); work.complete(done, readNode(token.kind(), token.text())); return; }
            if (accept("True")) { work.complete(done, readNode("bool", "True")); return; }
            if (accept("False")) { work.complete(done, readNode("bool", "False")); return; }
            work.complete(done, readNode("variable", name()));
        }
        void collection(String kind, String close, int level, boolean record, boolean type, Consumer<ReadNode> done) {
            lines(); var values = new ArrayList<ReadNode>(); var names = new ArrayList<String>(); var seen = new java.util.HashSet<String>();
            work.later(new Runnable() {
                @Override public void run() {
                    if (accept(close)) { work.complete(done, readNode(kind, "", values, names)); return; }
                    if (record) { String name = name(); if (!seen.add(name)) throw readSyntax(); names.add(name); need(type ? "::" : "="); lines(); }
                    Consumer<ReadNode> item = value -> {
                        values.add(value); lines();
                        if (!accept(",")) { need(close); work.complete(done, readNode(kind, "", values, names)); }
                        else { lines(); work.later(this); }
                    };
                    if (type) type(level, item); else expression(0, level, item);
                }
            });
        }
        void type(int level, Consumer<ReadNode> done) {
            work.later(() -> { enter(level); typeAtom(level + 1, head -> typeTail(head, level + 1, done)); });
        }
        void typeTail(ReadNode head, int level, Consumer<ReadNode> done) {
            work.later(() -> {
                if (typeStart()) { typeAtom(level, arg -> typeTail(readNode("type-apply", "", head, arg), level, done)); return; }
                if (accept("->")) { lines(); type(level, result -> rules(readNode("type-arrow", "", head, result), level, done)); }
                else rules(head, level, done);
            });
        }
        void typeAtom(int level, Consumer<ReadNode> done) {
            work.later(() -> {
                enter(level);
                if (accept("[")) { lines(); type(level + 1, element -> { lines(); need("]"); work.complete(done, readNode("type-list", "", element)); }); return; }
                if (accept("(")) { lines(); type(level + 1, inner -> { lines(); need(")"); work.complete(done, inner); }); return; }
                if (accept("{")) { collection("type-record", "}", level + 1, true, true, done); return; }
                work.complete(done, readNode("type-name", name()));
            });
        }
        void rules(ReadNode parent, int level, Consumer<ReadNode> done) {
            var parts = new ArrayList<ReadNode>(); parts.add(parent);
            work.later(new Runnable() {
                @Override public void run() {
                    int mark = index; lines();
                    if (!accept("where")) { index = mark; work.complete(done, parts.size() == 1 ? parent : readNode("type-refined", "", parts, List.of())); return; }
                    lines(); expression(0, level, predicate -> { parts.add(predicate); annotations(parts, level, new java.util.HashSet<>(), () -> work.later(this)); });
                }
            });
        }
        void annotations(List<ReadNode> parts, int level, java.util.Set<String> seen, Runnable done) {
            work.later(() -> {
                int mark = index; lines(); if (!accept("@")) { index = mark; work.later(done); return; }
                String key = name(); if (!seen.add(key)) throw readSyntax();
                switch (key) {
                    case "code" -> { String code = TextCodec.read(need("text").text()); if (code.isEmpty()) throw readSyntax(); try { TextCodec.utf8(code); } catch (IllegalArgumentException failure) { throw readSyntax(); } }
                    case "steps" -> { String text = need("number").text(); if (text.length() > 20 || !text.matches("[0-9]+")) throw readSyntax(); BigInteger steps = new BigInteger(text); if (steps.signum() <= 0 || steps.compareTo(Budget.MAX) > 0) throw readSyntax(); }
                    case "message" -> { expression(0, level, message -> { parts.add(message); annotations(parts, level, seen, done); }); return; }
                    default -> throw readSyntax();
                }
                annotations(parts, level, seen, done);
            });
        }
        void pattern(int level, Consumer<ReadNode> done) {
            work.later(() -> { enter(level); patternAtom(level + 1, head -> patternTail(head, level + 1, done)); });
        }
        void patternTail(ReadNode head, int level, Consumer<ReadNode> done) {
            var arguments = new ArrayList<>(head.args());
            work.later(new Runnable() {
                @Override public void run() {
                    if (head.kind().equals("pattern-constructor") && patternStart()) {
                        patternAtom(level, arg -> { arguments.add(arg); work.later(this); }); return;
                    }
                    ReadNode result = head.kind().equals("pattern-constructor") ? readNode(head.kind(), head.text(), arguments, List.of()) : head;
                    if (accept(":")) pattern(level, tail -> work.complete(done, readNode("pattern-cons", "", result, tail)));
                    else work.complete(done, result);
                }
            });
        }
        void patternAtom(int level, Consumer<ReadNode> done) {
            work.later(() -> {
                enter(level);
                if (accept("_")) { work.complete(done, readNode("pattern-wild", "")); return; }
                if (accept("(")) { lines(); pattern(level + 1, inner -> { lines(); need(")"); work.complete(done, inner); }); return; }
                if (accept("[")) {
                    lines(); var items = new ArrayList<ReadNode>();
                    work.later(new Runnable() {
                        @Override public void run() {
                            if (accept("]")) { work.complete(done, readNode("pattern-list", "", items, List.of())); return; }
                            pattern(level + 1, item -> { items.add(item); lines();
                                if (!accept(",")) { need("]"); work.complete(done, readNode("pattern-list", "", items, List.of())); }
                                else { lines(); work.later(this); }
                            });
                        }
                    }); return;
                }
                if (accept("-")) { work.complete(done, readNode("pattern-literal", "", readNode("number", "-" + need("number").text()))); return; }
                if (is("number") || is("text") || is("True") || is("False")) { prefix(level + 1, literal -> work.complete(done, readNode("pattern-literal", "", literal))); return; }
                String name = name(); work.complete(done, readNode(CodecUnicode.upper(name.codePointAt(0)) ? "pattern-constructor" : "pattern-bind", name));
            });
        }
    }
`
