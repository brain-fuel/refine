package java

const contractRuntimeJava = `
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.ArrayDeque;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import java.util.function.Consumer;
import java.util.function.Function;

/** Execution support for statically generated contracts. No schema loading or I/O. */
public final class ContractRuntime {
    private ContractRuntime() {}
    // @CODEC_UNICODE@
    ` + codecNamesJava + `
    ` + codecParserJava + `
    ` + codecBoundaryJava + `
    ` + modelRefinementJava + `
    /** Canonical text only: never asserts a payload's refinements. */
    public static String showWithoutValidation(Data input, Budget.Limits caller) {
        if (input == null) throw new ValidationException(new Validation.Invalid(List.of(new Validation.Diagnostic(
            "validation.structure", List.of(""), "", "Java null is not a language value; use an explicit optional or nullable constructor.")), false));
        Eval evaluator = new Eval(new Budget(Budget.Limits.defaults(), caller).beginStructure(), Map.of(), Map.of());
        try {
            Val value = evaluator.transfer(input); Work work = new Work(); String[] result = new String[1];
            evaluator.new Engine(work).show(value, 0, shown -> { evaluator.step(utf8Size(shown)); result[0] = shown; });
            work.run(); return result[0];
        } catch (Failure failure) {
            throw new ValidationException(new Validation.Indeterminate(List.of(new Validation.Diagnostic(failure.code, List.of(""), "", failure.getMessage()))));
        }
    }
    public record Type(String kind, String name, List<Type> arguments, List<Member> fields, List<Rule> rules) {
        public Type { arguments = List.copyOf(arguments); fields = List.copyOf(fields); rules = List.copyOf(rules); }
    }
    public record Member(String name, Type type) {}
    public record Alternative(String name, List<Type> arguments) { public Alternative { arguments = List.copyOf(arguments); } }
    public record Scope(String parameter, String symbol) {}
    public record Definition(List<String> parameters, Type body, List<Alternative> alternatives, List<Scope> scopes) {
        public Definition { parameters = List.copyOf(parameters); alternatives = List.copyOf(alternatives); scopes = List.copyOf(scopes); }
        public Definition(List<String> parameters, Type body, List<Alternative> alternatives) { this(parameters, body, alternatives, List.of()); }
    }
    public record Pattern(String kind, String name, List<Pattern> arguments, Expr literal) { public Pattern { arguments = List.copyOf(arguments); } }
    public record Arm(Pattern pattern, Expr body) {}
    public record Equation(List<Pattern> patterns, Expr body) { public Equation { patterns = List.copyOf(patterns); } }
    public record FunctionDef(Type signature, List<Equation> equations, List<Scope> scopes) { public FunctionDef { equations = List.copyOf(equations); scopes = List.copyOf(scopes); } }
    public record Rule(String code, int offset, String predicate, Expr expression, Expr message, BigInteger steps) {}
    public record Expr(String kind, String text, boolean flag, List<Expr> arguments, List<String> names, Supplier<Type> inferred, List<Arm> arms, Type annotation) {
        public Expr { arguments = List.copyOf(arguments); names = List.copyOf(names); arms = List.copyOf(arms); }
        public Expr(String kind, String text, boolean flag, List<Expr> arguments, List<String> names) { this(kind, text, flag, arguments, names, null, List.of(), null); }
        public Expr(String kind, String text, boolean flag, List<Expr> arguments, List<String> names, Type signature, List<Arm> arms) { this(kind, text, flag, arguments, names, () -> signature, arms, null); }
        public Type signature() { return inferred == null ? null : inferred.get(); }
    }
    // Private execution values carry partial applications without
    // putting functions into the public payload Data hierarchy.
    private sealed interface Val {}
    private record NumberValue(Rational value, String numericType) implements Val {
        NumberValue(Rational value) { this(value, value.isInteger() ? "Int" : "Real"); }
    }
    private record TextValue(String value) implements Val {}
    private record TimestampValue(Timestamp value) implements Val {}
    private record BoolValue(boolean value) implements Val {}
    private record ListValue(List<Val> values) implements Val { ListValue { values = List.copyOf(values); } }
    private record MapValue(Map<String, Val> entries) implements Val {
        MapValue {
            var ordered = new ArrayList<>(entries.entrySet()); ordered.sort(Map.Entry.comparingByKey());
            var copy = new java.util.LinkedHashMap<String, Val>(); for (var entry : ordered) copy.put(entry.getKey(), entry.getValue());
            entries = java.util.Collections.unmodifiableMap(copy);
        }
    }
    private record FieldValue(String name, Val value) {}
    private record RecordValue(List<FieldValue> fields) implements Val { RecordValue { fields = List.copyOf(fields); } }
    private record VariantValue(String name, List<Val> values) implements Val { VariantValue { values = List.copyOf(values); } }
    private record FunctionValue(String name, int arity, List<Val> arguments, Type signature) implements Val { FunctionValue { arguments = List.copyOf(arguments); } }
    private record GuardedFunction(Val function, Type argument, Type result, Map<String, Binding> types) implements Val { GuardedFunction { types = Map.copyOf(types); } }
    private record Binding(Type type, Map<String, Binding> environment) {}
    private record Checked(Val data, boolean shape) {}
    private static final class Failure extends RuntimeException {
        private static final long serialVersionUID = 1L;
        final String code;
        Failure(String code, String message) { super(message); this.code = code; }
    }
    private static Failure fail(String code, String message) { return new Failure(code, message); }
    private static String pointer(String path, String name) { return path + "/" + name.replace("~", "~0").replace("/", "~1"); }
    private static int utf8Size(String text) { return text.getBytes(StandardCharsets.UTF_8).length; }
    private static Type flatten(Type type) {
        var arguments = new ArrayList<Type>();
        while (type.kind().equals("applied")) { arguments.addFirst(type.arguments().get(1)); type = type.arguments().getFirst(); }
        return new Type("named", type.name(), arguments, List.of(), List.of());
    }
    private static boolean numericPrimitive(String name) {
        if (name.equals("Int") || name.equals("Real") || name.equals("Float32") || name.equals("Float64")) return true;
        if (!name.matches("U?Int[0-9]+")) return false;
        String digits = name.replace("UInt", "").replace("Int", "");
        BigInteger width = new BigInteger(digits);
        return width.signum() > 0 && width.bitLength() <= 32 && width.toString().equals(digits);
    }
    /** Continuations are queued, never recursively invoked on the host stack. */
    private static final class Work {
        final ArrayDeque<Runnable> tasks = new ArrayDeque<>();
        private record Trap(int remaining, Consumer<Failure> handler) {}
        final ArrayDeque<Trap> traps = new ArrayDeque<>();
        void later(Runnable task) { tasks.push(task); }
        <T> void complete(Consumer<T> receiver, T value) { later(() -> receiver.accept(value)); }
        <T> void attempt(Consumer<Consumer<T>> start, Consumer<T> done, Consumer<Failure> failed) {
            traps.push(new Trap(tasks.size(), failed));
            start.accept(value -> { traps.pop(); complete(done, value); });
        }
        void run() {
            while (!tasks.isEmpty()) {
                try { tasks.pop().run(); }
                catch (Failure failure) {
                    if (traps.isEmpty()) throw failure;
                    Trap trap = traps.pop(); while (tasks.size() > trap.remaining()) tasks.pop();
                    complete(trap.handler(), failure);
                }
            }
        }
    }
    private static final class Eval {
        final Budget.Meter meter;
        final Map<String, Definition> definitions;
        final Map<String, FunctionDef> functions;
        final Map<String, Integer> constructors = new HashMap<>(Map.ofEntries(Map.entry("Nothing",0),Map.entry("Just",1),Map.entry("Null",0),Map.entry("NonNull",1),Map.entry("Err",1),Map.entry("Ok",1),Map.entry("JSONNull",0),Map.entry("JSONBoolean",1),Map.entry("JSONNumber",1),Map.entry("JSONString",1),Map.entry("JSONArray",1),Map.entry("JSONObject",1)));
        int depth;
        Eval(Budget.Meter meter, Map<String, Definition> definitions, Map<String, FunctionDef> functions) {
            this.meter = meter; this.definitions = definitions; this.functions = functions;
            for (Definition definition : definitions.values()) for (Alternative alternative : definition.alternatives()) constructors.put(alternative.name(), alternative.arguments().size());
        }
        void step(long cost) { step(BigInteger.valueOf(cost)); }
        void step(BigInteger cost) {
            try { meter.step(cost); } catch (Budget.Exceeded e) { throw fail("evaluation.budget", "validation step budget exhausted"); }
        }
        <T> T atDepth(int logicalDepth, Supplier<T> action) {
            int previous = depth; depth = logicalDepth;
            try { return action.get(); } finally { depth = previous; }
        }
        void enterDepth(int logicalDepth) {
            step(1);
            if (logicalDepth >= 512) throw fail("evaluation.depth", "evaluation nesting limit exceeded");
        }
        MapValue mapValue(Map<String, Val> entries) {
            long levels = 1, maximum = 0; for (int n = entries.size(); n > 1; n >>= 1) levels++;
            for (String key : entries.keySet()) maximum = Math.max(maximum,key.length());
            BigInteger count=BigInteger.valueOf(entries.size()), per=BigInteger.valueOf(maximum).multiply(BigInteger.TWO).add(BigInteger.ONE);
            step(count.multiply(BigInteger.valueOf(levels)).multiply(per).add(count));
            return new MapValue(entries);
        }
        Val transfer(Data value) {
            Work work = new Work(); Val[] result = new Val[1];
            class Transfer {
                void visit(Data input, int logicalDepth, Consumer<Val> done) {
                    work.later(() -> {
                        enterDepth(logicalDepth);
                        switch (input) {
                            case Data.Number n -> { step(n.value().show().length()); work.complete(done, new NumberValue(n.value())); }
                            case Data.Text t -> work.complete(done, new TextValue(t.value()));
                            case Data.Bool b -> work.complete(done, new BoolValue(b.value()));
                            case Data.Sequence list -> { step(list.values().size()); items(list.values(), logicalDepth, values -> new ListValue(values), done); }
                            case Data.Mapping map -> {
                                step(map.entries().size()); var entries = new ArrayList<>(map.entries().entrySet());
                                work.later(new Runnable() {
                                    int index; final Map<String, Val> values = new java.util.LinkedHashMap<>();
                                    @Override public void run() {
                                        if (index == entries.size()) { work.complete(done, mapValue(values)); return; }
                                        var entry = entries.get(index++); step(entry.getKey().length());
                                        visit(entry.getValue(), logicalDepth + 1, item -> { values.put(entry.getKey(), item); work.later(this); });
                                    }
                                });
                            }
                            case Data.Variant v -> { step((long)v.values().size() + utf8Size(v.name())); items(v.values(), logicalDepth, values -> new VariantValue(v.name(), values), done); }
                            case Data.Struct record -> {
                                step(record.fields().size());
                                work.later(new Runnable() {
                                    int index; final List<FieldValue> fields = new ArrayList<>();
                                    @Override public void run() {
                                        if (index == record.fields().size()) { work.complete(done, new RecordValue(fields)); return; }
                                        Data.Field field = record.fields().get(index++); step(utf8Size(field.name()));
                                        visit(field.value(), logicalDepth + 1, item -> { fields.add(new FieldValue(field.name(), item)); work.later(this); });
                                    }
                                });
                            }
                        }
                    });
                }
                void items(List<Data> inputs, int logicalDepth, Function<List<Val>, Val> finish, Consumer<Val> done) {
                    work.later(new Runnable() {
                        int index; final List<Val> values = new ArrayList<>();
                        @Override public void run() {
                            if (index == inputs.size()) { work.complete(done, finish.apply(values)); return; }
                            visit(inputs.get(index++), logicalDepth + 1, item -> { values.add(item); work.later(this); });
                        }
                    });
                }
            }
            new Transfer().visit(value, depth, data -> result[0] = data); work.run(); return result[0];
        }
        Val expression(Expr expression, Map<String, Val> environment, Map<String, Binding> typeEnvironment) {
            Work work = new Work(); Val[] result = new Val[1];
            new Engine(work).visit(expression, environment, typeEnvironment, depth, data -> result[0] = data); work.run(); return result[0];
        }
        private final class Engine {
                final Work work;
                Engine(Work work) { this.work = work; }
                void visit(Expr expr, Map<String, Val> env, Map<String, Binding> types, int logicalDepth, Consumer<Val> done) {
                    work.later(() -> {
                        enterDepth(logicalDepth);
                        List<Expr> args = expr.arguments(); String text = expr.text();
                        switch (expr.kind()) {
                    case "number" -> work.complete(done, literalNumber(text));
                    case "text" -> { step(utf8Size(text)); work.complete(done, new TextValue(TextCodec.read(text))); }
                    case "bool" -> work.complete(done, new BoolValue(expr.flag()));
                    case "variable" -> work.complete(done, env.get(text));
                    case "global" -> resolve(text, instantiate(expr.signature(), types), types, logicalDepth + 1, done);
                    case "apply" -> visit(args.get(0), env, types, logicalDepth + 1, fn ->
                        visit(args.get(1), env, types, logicalDepth + 1, arg -> apply(fn, arg, types, logicalDepth + 1, done)));
                    case "case" -> visit(args.getFirst(), env, types, logicalDepth + 1, value -> {
                        work.later(new Runnable() {
                            int index;
                            @Override public void run() {
                                if (index == expr.arms().size()) throw fail("evaluation.pattern", "no pattern matched the value");
                                Arm arm = expr.arms().get(index++); var local = new HashMap<>(env);
                                pattern(arm.pattern(), value, local, types, logicalDepth + 1, matched -> {
                                    if (matched) visit(arm.body(), local, types, logicalDepth + 1, done); else work.later(this);
                                });
                            }
                        });
                    });
                    case "project" -> visit(args.getFirst(), env, types, logicalDepth + 1, input -> {
                        RecordValue record = (RecordValue)input; Val found = null;
                        for (FieldValue field : record.fields()) { step(1); if (field.name().equals(text)) { found = field.value(); break; } }
                        if (found == null) throw fail("evaluation.field", "record field is missing"); work.complete(done, found);
                    });
                    case "unary" -> visit(args.getFirst(), env, types, logicalDepth + 1, input -> {
                        NumberValue n = (NumberValue)input; step(n.value().show().length());
                        work.complete(done, checkedNumber(n.value().negate(), n.numericType()));
                    });
                    case "binary" -> visit(args.get(0), env, types, logicalDepth + 1, left -> {
                        if (text.equals("&&") && !((BoolValue)left).value()) { work.complete(done, new BoolValue(false)); return; }
                        if (text.equals("||") && ((BoolValue)left).value()) { work.complete(done, new BoolValue(true)); return; }
                        visit(args.get(1), env, types, logicalDepth + 1, right -> work.complete(done,
                            atDepth(logicalDepth + 1, () -> binary(text, left, right))));
                    });
                    case "if" -> visit(args.get(0), env, types, logicalDepth + 1, condition ->
                        visit(args.get(((BoolValue)condition).value() ? 1 : 2), env, types, logicalDepth + 1, done));
                    case "let" -> visit(args.get(0), env, types, logicalDepth + 1, value -> {
                        Consumer<Val> bind = checked -> { var local = new HashMap<>(env); local.put(text, checked); visit(args.get(1), local, types, logicalDepth + 1, done); };
                        if (expr.annotation() == null) work.complete(bind, value); else assertInline(expr.annotation(), value, types, logicalDepth + 1, bind);
                    });
                    case "list", "record", "map" -> {
                        step(args.size());
                        work.later(new Runnable() {
                            int index; final List<Val> values = new ArrayList<>();
                            @Override public void run() {
                                if (index == args.size()) {
                                    if (expr.kind().equals("list")) work.complete(done, new ListValue(values));
                                    else if (expr.kind().equals("map")) {
                                        var entries = new java.util.LinkedHashMap<String, Val>();
                                        for (int i = 0; i < values.size(); i++) {
                                            String key = TextCodec.read(expr.names().get(i));
                                            if (entries.putIfAbsent(key, values.get(i)) != null) throw fail("evaluation.map", "duplicate decoded map key");
                                        }
                                        work.complete(done, mapValue(entries));
                                    }
                                    else {
                                        var fields = new ArrayList<FieldValue>();
                                        for (int i = 0; i < values.size(); i++) fields.add(new FieldValue(expr.names().get(i), values.get(i)));
                                        work.complete(done, new RecordValue(fields));
                                    }
                                    return;
                                }
                                visit(args.get(index++), env, types, logicalDepth + 1, value -> { values.add(value); work.later(this); });
                            }
                        });
                    }
                    default -> throw new AssertionError("unhandled generated expression");
                        }
                    });
                }
                ` + functionExecutionJava + `
                ` + inlineAssertionJava + `
                ` + codecExecutionJava + `
                ` + codecReadJava + `
        }
        ` + functionTypesJava + `
        NumberValue checkedNumber(Rational number, String type) {
            if (type.equals("Float32") || type.equals("Float64")) {
                try { if (type.equals("Float32")) number.exactFloat32(); else number.exactFloat64(); }
                catch (ArithmeticException failure) { throw fail("evaluation.precision", "fixed-precision result is not exactly representable"); }
                return new NumberValue(number, type);
            }
            if (!type.equals("Int") && !type.equals("Real")) {
                int width = Integer.parseInt(type.replace("UInt", "").replace("Int", "")); step(width);
                try { number.fixedWidth(width, !type.startsWith("UInt")); }
                catch (ArithmeticException e) { throw fail("evaluation.overflow", "fixed-width result is not representable"); }
            }
            return new NumberValue(number, type);
        }
        boolean equal(Val a, Val b) {
            Work work = new Work(); boolean[] same = { true };
            class Equality {
                void visit(Val left, Val right, int logicalDepth) {
                    work.later(() -> {
                        enterDepth(logicalDepth);
                        switch (left) {
                            case FunctionValue ignored -> throw fail("evaluation.type", "functions do not support value equality");
                            case GuardedFunction ignored -> throw fail("evaluation.type", "functions do not support value equality");
                            case NumberValue n -> { Rational r = ((NumberValue)right).value(); step((long)n.value().show().length() + r.show().length()); same[0] = n.value().equals(r); }
                            case TextValue t -> { String r = ((TextValue)right).value(); step((long)t.value().length() + r.length()); same[0] = t.value().equals(r); }
                            case TimestampValue t -> same[0] = compareTimestamps(t, (TimestampValue)right) == 0;
                            case BoolValue v -> same[0] = v.value() == ((BoolValue)right).value();
                            case ListValue list -> items(list.values(), ((ListValue)right).values(), logicalDepth);
                            case MapValue map -> {
                                var other = ((MapValue)right).entries(); same[0] = map.entries().size() == other.size();
                                if (same[0]) work.later(new Runnable() {
                                    final java.util.Iterator<Map.Entry<String, Val>> entries = map.entries().entrySet().iterator();
                                    @Override public void run() {
                                        if (!entries.hasNext()) return; var entry = entries.next(); step((long)entry.getKey().length() * 2);
                                        Val candidate = other.get(entry.getKey()); if (candidate == null) { same[0] = false; return; }
                                        work.later(this); visit(entry.getValue(), candidate, logicalDepth + 1);
                                    }
                                });
                            }
                            case VariantValue v -> {
                                var other = (VariantValue)right; same[0] = v.name().equals(other.name());
                                if (same[0]) items(v.values(), other.values(), logicalDepth);
                            }
                            case RecordValue record -> {
                                var other = ((RecordValue)right).fields(); same[0] = record.fields().size() == other.size();
                                if (same[0]) work.later(new Runnable() {
                                    int index;
                                    @Override public void run() {
                                        if (index == record.fields().size()) return;
                                        FieldValue field = record.fields().get(index++);
                                        for (FieldValue candidate : other) {
                                            step(1);
                                            if (candidate.name().equals(field.name())) { work.later(this); visit(field.value(), candidate.value(), logicalDepth + 1); return; }
                                        }
                                        same[0] = false;
                                    }
                                });
                            }
                        }
                    });
                }
                void items(List<Val> left, List<Val> right, int logicalDepth) {
                    same[0] = left.size() == right.size();
                    if (same[0]) work.later(new Runnable() {
                        int index;
                        @Override public void run() {
                            if (index == left.size()) return;
                            int i = index++; work.later(this); visit(left.get(i), right.get(i), logicalDepth + 1);
                        }
                    });
                }
            }
            new Equality().visit(a, b, depth);
            while (same[0] && !work.tasks.isEmpty()) work.tasks.pop().run();
            return same[0];
        }
        Val binary(String op, Val a, Val b) {
            switch (op) {
                case "&&": return new BoolValue(((BoolValue)a).value() && ((BoolValue)b).value());
                case "||": return new BoolValue(((BoolValue)a).value() || ((BoolValue)b).value());
                case "==": return new BoolValue(equal(a, b));
                case "/=": return new BoolValue(!equal(a, b));
                case ":": { var values = ((ListValue)b).values(); step((long)values.size() + 1); var result = new ArrayList<Val>(); result.add(a); result.addAll(values); return new ListValue(result); }
                case "++": {
                    if (a instanceof TextValue t) { String r = ((TextValue)b).value(); step((long)t.value().length() + r.length()); return new TextValue(t.value() + r); }
                    var left = ((ListValue)a).values(); var right = ((ListValue)b).values(); step((long)left.size() + right.size());
                    var result = new ArrayList<>(left); result.addAll(right); return new ListValue(result);
                }
            }
            if (List.of("<", "<=", ">", ">=").contains(op)) {
                int compared;
                if (a instanceof TextValue t) { String r = ((TextValue)b).value(); step((long)t.value().length() + r.length()); compared = t.value().compareTo(r); }
                else if (a instanceof TimestampValue t) compared = compareTimestamps(t, (TimestampValue)b);
                else { NumberValue n = (NumberValue)a, r = (NumberValue)b; numericTypes(n, r); numericCost(n.value(), r.value()); compared = n.value().compareTo(r.value()); }
                return new BoolValue(switch (op) { case "<" -> compared < 0; case "<=" -> compared <= 0; case ">" -> compared > 0; default -> compared >= 0; });
            }
            NumberValue left = (NumberValue)a, right = (NumberValue)b; numericTypes(left, right);
            Rational n = left.value(), r = right.value(); numericCost(n, r);
            if (op.equals("/")) { if (r.signum() == 0) throw fail("evaluation.divide", "division by zero"); return new NumberValue(n.divide(r), "Real"); }
            if (op.equals("%") && r.signum() == 0) throw fail("evaluation.remainder", "integer remainder is undefined");
            return checkedNumber(switch (op) { case "+" -> n.add(r); case "-" -> n.subtract(r); case "*" -> n.multiply(r); case "%" -> n.remainder(r); default -> throw new AssertionError("unhandled operator"); }, left.numericType());
        }
        void numericTypes(NumberValue a, NumberValue b) { if (!a.numericType().equals(b.numericType())) throw fail("evaluation.type", "numeric operands need an explicit conversion"); }
        int compareTimestamps(TimestampValue a, TimestampValue b) { numericCost(a.value().fraction(), b.value().fraction()); return a.value().compareTo(b.value()); }
        void numericCost(Rational a, Rational b) { step(BigInteger.valueOf(a.show().length()).multiply(BigInteger.valueOf(b.show().length())).add(BigInteger.ONE)); }
    }

    public static Validation.Outcome validate(Map<String, Definition> definitions, String root, Data input, Budget.Limits caller) {
        return validate(definitions, Map.of(), root, input, caller, true);
    }
    public static Validation.Outcome validateStructure(Map<String, Definition> definitions, String root, Data input, Budget.Limits caller) {
        return validate(definitions, Map.of(), root, input, caller, false);
    }
    public static Validation.Outcome validate(Map<String, Definition> definitions, Map<String, FunctionDef> functions, String root, Data input, Budget.Limits caller) {
        return validate(definitions, functions, root, input, caller, true);
    }
    public static Validation.Outcome validateStructure(Map<String, Definition> definitions, Map<String, FunctionDef> functions, String root, Data input, Budget.Limits caller) {
        return validate(definitions, functions, root, input, caller, false);
    }
    private static Validation.Outcome validate(Map<String, Definition> definitions, Map<String, FunctionDef> functions, String root, Data input, Budget.Limits caller, boolean refinements) {
        Definition definition = root == null ? null : definitions.get(root);
        if (definition == null || !definition.parameters().isEmpty()) return new Validation.Invalid(List.of(
            new Validation.Diagnostic("validation.root", List.of(""), "", "Choose a declared root type with no unbound type parameters.")), false);
        return validateType(definitions,functions,new Type("named",root,List.of(),List.of(),List.of()),input,caller,refinements);
    }
    // Package-private execution of statically checked emitted type metadata.
    // The generated contract exposes immutable handles, not an AST ingestion API.
    static Validation.Outcome validateType(Map<String, Definition> definitions, Map<String, FunctionDef> functions, Type target, Data input, Budget.Limits caller, boolean refinements) {
        if (target == null) return new Validation.Invalid(List.of(new Validation.Diagnostic("validation.root", List.of(""), "", "Choose a checked payload type.")), false);
        if (input == null) return new Validation.Invalid(List.of(new Validation.Diagnostic("validation.structure", List.of(""), "", "Java null is not a language value; use an explicit optional or nullable constructor.")), false);
        return new Validator(definitions, functions, caller, refinements).run(target, input);
    }
    private static final class Validator {
        final Map<String, Definition> definitions;
        final Map<String, FunctionDef> functions;
        final Budget budget;
        final Eval structure;
        final List<Validation.Check> checks = new ArrayList<>();
        final boolean refinements;
        final Eval enclosing;
        final Work work;
        String currentPath = "";
        Validator(Map<String, Definition> definitions, Map<String, FunctionDef> functions, Budget.Limits caller, boolean refinements) {
            this.definitions = definitions; this.functions = functions; this.refinements = refinements; budget = new Budget(Budget.Limits.defaults(), caller); structure = new Eval(budget.beginStructure(), definitions, functions); enclosing = null; work = new Work();
        }
        Validator(Eval enclosing, Work work) {
            this.enclosing = enclosing; this.structure = enclosing; this.work = work;
            definitions = enclosing.definitions; functions = enclosing.functions; refinements = true; budget = null;
        }
        Validation.Outcome run(Type root, Data input) {
            try {
                schedule(root, structure.transfer(input), Map.of(), "", 0, ignored -> {});
                work.run();
            }
            catch (Failure e) { checks.add(new Validation.Undecided(new Validation.Diagnostic(e.code, List.of(currentPath), "", e.getMessage()))); }
            return Validation.collect(checks);
        }
        Checked wrong(String path, String message) {
            checks.add(new Validation.Violated(new Validation.Diagnostic("validation.structure", List.of(path), "", message)));
            return new Checked(null, false);
        }
        void schedule(Type type, Val input, Map<String, Binding> env, String path, int depth, Consumer<Checked> done) {
            work.later(() -> {
                currentPath = path;
                structure.enterDepth(depth);
                switch (type.kind()) {
                    case "refined": {
                        schedule(type.arguments().getFirst(), input, env, path, depth + 1, result -> {
                            if (!result.shape() || !refinements) { work.complete(done, result); return; }
                            work.later(new Runnable() {
                                int index;
                                @Override public void run() {
                                    if (index == type.rules().size()) { work.complete(done, result); return; }
                                    rule(type.rules().get(index++), result.data(), path, env, depth + 1, () -> work.later(this));
                                }
                            });
                        });
                        return;
                    }
                    case "named": {
                        Binding binding = env.get(type.name());
                        if (binding == null) named(type, input, env, path, depth, done);
                        else schedule(binding.type(), input, binding.environment(), path, depth + 1, done);
                        return;
                    }
                    case "applied": { named(flatten(type), input, env, path, depth, done); return; }
                    case "list": {
                        if (!(input instanceof ListValue list)) { work.complete(done, wrong(path, "Expected a list.")); return; }
                        structure.step(list.values().size());
                        items(list.values(), ignored -> type.arguments().getFirst(), env, path, depth, values -> new ListValue(values), done);
                        return;
                    }
                    case "record": {
                        if (!(input instanceof RecordValue record)) { work.complete(done, wrong(path, "Expected a record.")); return; }
                        structure.step((long)record.fields().size() + type.fields().size()); var actual = new HashMap<String, Val>();
                        for (FieldValue field : record.fields()) actual.put(field.name(), field.value());
                        work.later(new Runnable() {
                            int index; boolean all = true; final List<FieldValue> result = new ArrayList<>();
                            @Override public void run() {
                                if (index == type.fields().size()) { work.complete(done, new Checked(all ? new RecordValue(result) : null, all)); return; }
                                Member field = type.fields().get(index++);
                                Val value = actual.get(field.name()); String childPath = pointer(path, field.name());
                                if (value == null) {
                                    if (optional(field.type(), env, 0)) value = new VariantValue("Nothing", List.of());
                                    else { wrong(childPath, "Required field is absent."); all = false; work.later(this); return; }
                                }
                                schedule(field.type(), value, env, childPath, depth + 1, checked -> {
                                    all &= checked.shape(); if (checked.shape()) result.add(new FieldValue(field.name(), checked.data())); work.later(this);
                                });
                            }
                        });
                        return;
                    }
                    default: throw new AssertionError("unhandled generated type");
                }
            });
        }
        void items(List<Val> inputs, Function<Integer, Type> type, Map<String, Binding> env, String path, int depth, Function<List<Val>, Val> finish, Consumer<Checked> done) {
            work.later(new Runnable() {
                int index; boolean all = true; final List<Val> values = new ArrayList<>();
                @Override public void run() {
                    if (index == inputs.size()) { work.complete(done, new Checked(all ? finish.apply(values) : null, all)); return; }
                    int i = index++;
                    schedule(type.apply(i), inputs.get(i), env, pointer(path, Integer.toString(i)), depth + 1, checked -> {
                        all &= checked.shape(); if (checked.shape()) values.add(checked.data()); work.later(this);
                    });
                }
            });
        }
        void named(Type type, Val input, Map<String, Binding> env, String path, int depth, Consumer<Checked> done) {
            String name = type.name(); var args = type.arguments();
            switch (name) {
                case "Bool": work.complete(done, input instanceof BoolValue ? new Checked(input, true) : wrong(path, "Expected a Boolean.")); return;
                case "String": work.complete(done, input instanceof TextValue ? new Checked(input, true) : wrong(path, "Expected text.")); return;
                case "Timestamp": {
                    if (input instanceof TimestampValue) { work.complete(done, new Checked(input, true)); return; }
                    if (!(input instanceof TextValue text)) { work.complete(done, wrong(path, "Expected an RFC 3339 timestamp.")); return; }
                    long size = text.value().length(); structure.step(size * size + 1);
                    try { TextCodec.utf8(text.value()); }
                    catch (IllegalArgumentException failure) { work.complete(done, wrong(path, "Expected an RFC 3339 timestamp.")); return; }
                    try { work.complete(done, new Checked(new TimestampValue(Timestamp.parse(text.value())), true)); }
                    catch (Timestamp.Error failure) {
                        var detail = new Validation.Diagnostic(failure.code(), List.of(path), "", failure.getMessage());
                        checks.add(failure.code().equals("timestamp.unknown_leap") ? new Validation.Undecided(detail) : new Validation.Violated(detail));
                        work.complete(done, new Checked(null, false));
                    }
                    return;
                }
                case "Maybe", "Nullable", "Result": {
                    if (!(input instanceof VariantValue v)) { work.complete(done, wrong(path, "Expected an explicit optional, nullable, or result constructor.")); return; }
                    String none = name.equals("Maybe") ? "Nothing" : name.equals("Nullable") ? "Null" : "Err";
                    String some = name.equals("Maybe") ? "Just" : name.equals("Nullable") ? "NonNull" : "Ok";
                    if (!name.equals("Result") && v.name().equals(none) && v.values().isEmpty()) { work.complete(done, new Checked(input, true)); return; }
                    if ((v.name().equals(some) || name.equals("Result") && v.name().equals(none)) && v.values().size() == 1) {
                        int index = name.equals("Result") && v.name().equals("Ok") ? 1 : 0;
                        schedule(args.get(index), v.values().getFirst(), env, path, depth + 1, checked -> work.complete(done,
                            new Checked(checked.shape() ? new VariantValue(v.name(), List.of(checked.data())) : null, checked.shape())));
                        return;
                    }
                    work.complete(done, wrong(path, "Constructor does not match the declared optional, nullable, or result type.")); return;
                }
                case "Map": {
                    if (args.size() != 2 || !args.getFirst().kind().equals("named") || !args.getFirst().name().equals("String") || !(input instanceof MapValue map)) {
                        work.complete(done, wrong(path, "Expected a string-keyed map.")); return;
                    }
                    structure.step(map.entries().size()); var entries = new ArrayList<>(map.entries().entrySet());
                    work.later(new Runnable() {
                        int index; boolean all = true; final Map<String, Val> result = new java.util.LinkedHashMap<>();
                        @Override public void run() {
                            if (index == entries.size()) { MapValue mapped=structure.mapValue(result);work.complete(done, new Checked(all ? mapped : null, all)); return; }
                            int item = index++; var entry = entries.get(item);
                            schedule(args.get(1), entry.getValue(), env, pointer(path, Integer.toString(item)), depth + 1, checked -> {
                                all &= checked.shape(); result.put(entry.getKey(),checked.shape()?checked.data():entry.getValue()); work.later(this);
                            });
                        }
                    });
                    return;
                }
                case "JSON": {
                    if (!args.isEmpty() || !(input instanceof VariantValue value)) { work.complete(done, wrong(path, "Expected an explicit JSON constructor.")); return; }
                    Type argument = switch (value.name()) {
                        case "JSONNull" -> null;
                        case "JSONBoolean" -> namedType("Bool");
                        case "JSONNumber" -> namedType("Real");
                        case "JSONString" -> namedType("String");
                        case "JSONArray" -> new Type("list", "", List.of(namedType("JSON")), List.of(), List.of());
                        case "JSONObject" -> appliedType(appliedType(namedType("Map"),namedType("String")),namedType("JSON"));
                        default -> { work.complete(done, wrong(path, "Constructor does not belong to JSON.")); yield null; }
                    };
                    if (argument == null) { if (value.name().equals("JSONNull") && value.values().isEmpty()) work.complete(done,new Checked(value,true)); else if (!value.name().equals("JSONNull")) {} else work.complete(done,wrong(path,"JSON constructor has the wrong number of arguments.")); return; }
                    if (value.values().size()!=1) { work.complete(done,wrong(path,"JSON constructor has the wrong number of arguments.")); return; }
                    schedule(argument,value.values().getFirst(),env,pointer(path,"0"),depth+1,checked -> work.complete(done,new Checked(checked.shape()?new VariantValue(value.name(),List.of(checked.data())):null,checked.shape())));return;
                }
            }
            if (numericPrimitive(name)) {
                if (!(input instanceof NumberValue n)) { work.complete(done, wrong(path, "Expected an exact number.")); return; }
                structure.step(n.value().show().length());
                if (name.equals("Float32") || name.equals("Float64")) {
                    structure.step(64);
                    try { if (name.equals("Float32")) n.value().exactFloat32(); else n.value().exactFloat64(); }
                    catch (ArithmeticException e) { work.complete(done, wrong(path, "Number is not exactly representable as finite " + name + ".")); return; }
                    work.complete(done, new Checked(new NumberValue(n.value(), name), true)); return;
                }
                if (!name.equals("Real") && !n.value().isInteger()) { work.complete(done, wrong(path, "Expected an integer without fractional coercion.")); return; }
                if (!name.equals("Real") && !name.equals("Int")) {
                    long width = Long.parseLong(name.replace("UInt", "").replace("Int", "")); structure.step(width);
                    if (width > 65536) throw fail("evaluation.unsupported", "integer width exceeds the current numeric backend limit");
                    try { n.value().fixedWidth((int)width, !name.startsWith("UInt")); }
                    catch (ArithmeticException e) { work.complete(done, wrong(path, "Integer is outside its declared fixed-width range.")); return; }
                }
                work.complete(done, new Checked(new NumberValue(n.value(), name), true)); return;
            }
            Definition definition = definitions.get(name); var bindings = bindings(definition, args, env);
            if (definition.body() != null) { schedule(definition.body(), input, bindings, path, depth + 1, done); return; }
            if (!(input instanceof VariantValue value)) { work.complete(done, wrong(path, "Expected a tagged data alternative.")); return; }
            for (Alternative alternative : definition.alternatives()) {
                structure.step(1); if (!alternative.name().equals(value.name())) continue;
                if (alternative.arguments().size() != value.values().size()) { work.complete(done, wrong(path, "Constructor has the wrong number of arguments.")); return; }
                items(value.values(), i -> alternative.arguments().get(i), bindings, path, depth, values -> new VariantValue(value.name(), values), done);
                return;
            }
            work.complete(done, wrong(path, "Constructor does not belong to the declared data type."));
        }
        Map<String, Binding> bindings(Definition definition, List<Type> arguments, Map<String, Binding> environment) {
            var result = new HashMap<String, Binding>();
            for (int i = 0; i < arguments.size(); i++) result.put(definition.parameters().get(i), new Binding(arguments.get(i), environment));
            for (Scope scope : definition.scopes()) if (result.containsKey(scope.parameter())) result.put(scope.symbol(), result.get(scope.parameter()));
            return result;
        }
        private static Type namedType(String name){return new Type("named",name,List.of(),List.of(),List.of());}
        private static Type appliedType(Type function,Type argument){return new Type("applied","",List.of(function,argument),List.of(),List.of());}
        boolean optional(Type type, Map<String, Binding> env, int depth) {
            while (true) {
                structure.step(1); if (depth++ >= 512) throw fail("evaluation.depth", "optional type expansion nesting limit exceeded");
                if (type.kind().equals("refined")) { type = type.arguments().getFirst(); continue; }
                if (type.kind().equals("applied")) type = flatten(type);
                if (!type.kind().equals("named")) return false;
                Binding binding = env.get(type.name()); if (binding != null) { type = binding.type(); env = binding.environment(); continue; }
                if (type.name().equals("Maybe") && type.arguments().size() == 1) return true;
                Definition definition = definitions.get(type.name());
                if (definition == null || definition.body() == null) return false;
                env = bindings(definition, type.arguments(), env); type = definition.body();
            }
        }
        void rule(Rule rule, Val input, String path, Map<String, Binding> types, int level, Runnable done) {
            String code = rule.code();
            if (code.isEmpty()) {
                try {
                    byte[] digest = MessageDigest.getInstance("SHA-256").digest((path + ":" + rule.offset() + ":" + rule.predicate()).getBytes(StandardCharsets.UTF_8));
                    code = "refine." + HexFormat.of().formatHex(digest, 0, 8);
                } catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
            }
            String defaultMessage = "Value must satisfy the declared condition: " + rule.predicate() + ".", diagnosticCode = code;
            Eval evaluator = new Eval(enclosing == null ? budget.beginClause(rule.steps()) : enclosing.meter.nested(rule.steps()), definitions, functions);
            int start = enclosing == null ? 0 : level; evaluator.depth = start; var env = Map.of("it", input); Eval.Engine engine = evaluator.new Engine(work);
            Consumer<String> violated = message -> { checks.add(new Validation.Violated(new Validation.Diagnostic(diagnosticCode, List.of(path), rule.predicate(), message))); work.later(done); };
            work.<Val>attempt(receiver -> engine.visit(rule.expression(), env, types, start, receiver), result -> {
                if (((BoolValue)result).value()) { checks.add(new Validation.Satisfied()); work.later(done); return; }
                if (rule.message() == null) { work.complete(violated, defaultMessage); return; }
                work.<Val>attempt(receiver -> engine.visit(rule.message(), env, types, start, receiver), custom -> {
                    String message = ((TextValue)custom).value();
                    try { TextCodec.utf8(message); } catch (IllegalArgumentException failure) { message = defaultMessage; }
                    work.complete(violated, message);
                }, failure -> work.complete(violated, defaultMessage));
            }, failure -> {
                checks.add(new Validation.Undecided(new Validation.Diagnostic(diagnosticCode, List.of(path), rule.predicate(), "Could not determine whether the condition holds: " + failure.code + ": " + failure.getMessage() + "."))); work.later(done);
            });
        }
    }
}
`
