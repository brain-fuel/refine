package java

const contractRuntimeJava = `
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

/** Execution support for statically generated contracts. No schema loading or I/O. */
public final class ContractRuntime {
    private ContractRuntime() {}
    public record Type(String kind, String name, List<Type> arguments, List<Member> fields, List<Rule> rules) {
        public Type { arguments = List.copyOf(arguments); fields = List.copyOf(fields); rules = List.copyOf(rules); }
    }
    public record Member(String name, Type type) {}
    public record Alternative(String name, List<Type> arguments) { public Alternative { arguments = List.copyOf(arguments); } }
    public record Definition(List<String> parameters, Type body, List<Alternative> alternatives) {
        public Definition { parameters = List.copyOf(parameters); alternatives = List.copyOf(alternatives); }
    }
    public record Rule(String code, int offset, String predicate, Expr expression, Expr message, BigInteger steps) {}
    public record Expr(String kind, String text, boolean flag, List<Expr> arguments, List<String> names) {
        public Expr { arguments = List.copyOf(arguments); names = List.copyOf(names); }
    }
    private record Binding(Type type, Map<String, Binding> environment) {}
    private record Checked(Data data, boolean shape) {}
    private static final class Failure extends RuntimeException {
        private static final long serialVersionUID = 1L;
        final String code;
        Failure(String code, String message) { super(message); this.code = code; }
    }
    private static Failure fail(String code, String message) { return new Failure(code, message); }
    private static String pointer(String path, String name) { return path + "/" + name.replace("~", "~0").replace("/", "~1"); }
    private static int utf8Size(String text) { return text.getBytes(StandardCharsets.UTF_8).length; }
    private static boolean numericPrimitive(String name) {
        if (name.equals("Int") || name.equals("Real")) return true;
        if (!name.matches("U?Int[0-9]+")) return false;
        String digits = name.replace("UInt", "").replace("Int", "");
        BigInteger width = new BigInteger(digits);
        return width.signum() > 0 && width.bitLength() <= 32 && width.toString().equals(digits);
    }
    private static final class Eval {
        final Budget.Meter meter;
        int depth;
        Eval(Budget.Meter meter) { this.meter = meter; }
        void step(long cost) { step(BigInteger.valueOf(cost)); }
        void step(BigInteger cost) {
            try { meter.step(cost); } catch (Budget.Exceeded e) { throw fail("evaluation.budget", "validation step budget exhausted"); }
        }
        <T> T node(Supplier<T> action) {
            step(1);
            if (depth >= 512) throw fail("evaluation.depth", "evaluation nesting limit exceeded");
            depth++;
            try { return action.get(); } finally { depth--; }
        }
        Data transfer(Data value) {
            return node(() -> switch (value) {
                case Data.Number n -> { step(n.value().show().length()); yield new Data.Number(n.value()); }
                case Data.Text t -> t;
                case Data.Bool b -> b;
                case Data.Sequence list -> {
                    step(list.values().size()); var result = new ArrayList<Data>();
                    for (Data item : list.values()) result.add(transfer(item)); yield new Data.Sequence(result);
                }
                case Data.Struct record -> {
                    step(record.fields().size()); var result = new ArrayList<Data.Field>();
                    for (Data.Field field : record.fields()) { step(utf8Size(field.name())); result.add(new Data.Field(field.name(), transfer(field.value()))); }
                    yield new Data.Struct(result);
                }
                case Data.Variant variant -> {
                    step((long)variant.values().size() + utf8Size(variant.name())); var result = new ArrayList<Data>();
                    for (Data item : variant.values()) result.add(transfer(item)); yield new Data.Variant(variant.name(), result);
                }
            });
        }
        Data expression(Expr expression, Map<String, Data> environment) {
            return node(() -> {
                List<Expr> args = expression.arguments(); String text = expression.text();
                return switch (expression.kind()) {
                    case "number" -> {
                        BigInteger cost = BigInteger.valueOf(text.length()); int at = Math.max(text.indexOf('e'), text.indexOf('E'));
                        if (at >= 0) {
                            cost = cost.add(new BigInteger(text.substring(at + 1)).abs());
                            if (cost.compareTo(Budget.MAX) > 0) throw fail("evaluation.budget", "numeric literal expansion exceeds evaluation resources");
                        }
                        step(cost);
                        yield new Data.Number(Rational.parse(text), text.indexOf('.') >= 0 || at >= 0 ? "Real" : "Int");
                    }
                    case "text" -> { step(utf8Size(text)); yield new Data.Text(TextCodec.read(text)); }
                    case "bool" -> new Data.Bool(expression.flag());
                    case "variable" -> environment.get(text);
                    case "project" -> {
                        Data.Struct record = (Data.Struct)expression(args.getFirst(), environment); Data found = null;
                        for (Data.Field field : record.fields()) { step(1); if (field.name().equals(text)) { found = field.value(); break; } }
                        if (found == null) throw fail("evaluation.field", "record field is missing"); yield found;
                    }
                    case "unary" -> {
                        Data.Number n = (Data.Number)expression(args.getFirst(), environment); step(n.value().show().length());
                        yield checkedNumber(n.value().negate(), n.numericType());
                    }
                    case "binary" -> {
                        Data left = expression(args.get(0), environment);
                        if (text.equals("&&") && !((Data.Bool)left).value()) yield new Data.Bool(false);
                        if (text.equals("||") && ((Data.Bool)left).value()) yield new Data.Bool(true);
                        yield binary(text, left, expression(args.get(1), environment));
                    }
                    case "if" -> expression(args.get(((Data.Bool)expression(args.get(0), environment)).value() ? 1 : 2), environment);
                    case "let" -> {
                        Data value = expression(args.get(0), environment); var local = new HashMap<>(environment); local.put(text, value);
                        yield expression(args.get(1), local);
                    }
                    case "list" -> {
                        step(args.size()); var values = new ArrayList<Data>(); for (Expr arg : args) values.add(expression(arg, environment));
                        yield new Data.Sequence(values);
                    }
                    case "record" -> {
                        step(args.size()); var fields = new ArrayList<Data.Field>();
                        for (int i = 0; i < args.size(); i++) fields.add(new Data.Field(expression.names().get(i), expression(args.get(i), environment)));
                        yield new Data.Struct(fields);
                    }
                    default -> throw new AssertionError("unhandled generated expression");
                };
            });
        }
        Data.Number checkedNumber(Rational number, String type) {
            if (!type.equals("Int") && !type.equals("Real")) {
                int width = Integer.parseInt(type.replace("UInt", "").replace("Int", "")); step(width);
                try { number.fixedWidth(width, !type.startsWith("UInt")); }
                catch (ArithmeticException e) { throw fail("evaluation.overflow", "fixed-width result is not representable"); }
            }
            return new Data.Number(number, type);
        }
        boolean equal(Data a, Data b) {
            return node(() -> switch (a) {
                case Data.Number n -> { Rational r = ((Data.Number)b).value(); step((long)n.value().show().length() + r.show().length()); yield n.value().equals(r); }
                case Data.Text t -> { String r = ((Data.Text)b).value(); step((long)t.value().length() + r.length()); yield t.value().equals(r); }
                case Data.Bool v -> v.value() == ((Data.Bool)b).value();
                case Data.Sequence list -> equalItems(list.values(), ((Data.Sequence)b).values());
                case Data.Variant v -> v.name().equals(((Data.Variant)b).name()) && equalItems(v.values(), ((Data.Variant)b).values());
                case Data.Struct record -> {
                    var other = ((Data.Struct)b).fields(); boolean same = record.fields().size() == other.size();
                    if (same) for (Data.Field field : record.fields()) {
                        boolean found = false;
                        for (Data.Field candidate : other) { step(1); if (candidate.name().equals(field.name())) { found = equal(field.value(), candidate.value()); break; } }
                        if (!found) { same = false; break; }
                    }
                    yield same;
                }
            });
        }
        boolean equalItems(List<Data> a, List<Data> b) {
            if (a.size() != b.size()) return false;
            for (int i = 0; i < a.size(); i++) if (!equal(a.get(i), b.get(i))) return false;
            return true;
        }
        Data binary(String op, Data a, Data b) {
            switch (op) {
                case "&&": return new Data.Bool(((Data.Bool)a).value() && ((Data.Bool)b).value());
                case "||": return new Data.Bool(((Data.Bool)a).value() || ((Data.Bool)b).value());
                case "==": return new Data.Bool(equal(a, b));
                case "/=": return new Data.Bool(!equal(a, b));
                case ":": { var values = ((Data.Sequence)b).values(); step((long)values.size() + 1); var result = new ArrayList<Data>(); result.add(a); result.addAll(values); return new Data.Sequence(result); }
                case "++": {
                    if (a instanceof Data.Text t) { String r = ((Data.Text)b).value(); step((long)t.value().length() + r.length()); return new Data.Text(t.value() + r); }
                    var left = ((Data.Sequence)a).values(); var right = ((Data.Sequence)b).values(); step((long)left.size() + right.size());
                    var result = new ArrayList<>(left); result.addAll(right); return new Data.Sequence(result);
                }
            }
            if (List.of("<", "<=", ">", ">=").contains(op)) {
                int compared;
                if (a instanceof Data.Text t) { String r = ((Data.Text)b).value(); step((long)t.value().length() + r.length()); compared = t.value().compareTo(r); }
                else { Data.Number n = (Data.Number)a, r = (Data.Number)b; numericTypes(n, r); numericCost(n.value(), r.value()); compared = n.value().compareTo(r.value()); }
                return new Data.Bool(switch (op) { case "<" -> compared < 0; case "<=" -> compared <= 0; case ">" -> compared > 0; default -> compared >= 0; });
            }
            Data.Number left = (Data.Number)a, right = (Data.Number)b; numericTypes(left, right);
            Rational n = left.value(), r = right.value(); numericCost(n, r);
            if (op.equals("/")) { if (r.signum() == 0) throw fail("evaluation.divide", "division by zero"); return new Data.Number(n.divide(r), "Real"); }
            if (op.equals("%") && r.signum() == 0) throw fail("evaluation.remainder", "integer remainder is undefined");
            return checkedNumber(switch (op) { case "+" -> n.add(r); case "-" -> n.subtract(r); case "*" -> n.multiply(r); case "%" -> n.remainder(r); default -> throw new AssertionError("unhandled operator"); }, left.numericType());
        }
        void numericTypes(Data.Number a, Data.Number b) { if (!a.numericType().equals(b.numericType())) throw fail("evaluation.type", "numeric operands need an explicit conversion"); }
        void numericCost(Rational a, Rational b) { step(BigInteger.valueOf(a.show().length()).multiply(BigInteger.valueOf(b.show().length())).add(BigInteger.ONE)); }
    }

    public static Validation.Outcome validate(Map<String, Definition> definitions, String root, Data input, Budget.Limits caller) {
        Definition definition = definitions.get(root);
        if (definition == null || !definition.parameters().isEmpty()) return new Validation.Invalid(List.of(
            new Validation.Diagnostic("validation.root", List.of(""), "", "Choose a declared root type with no unbound type parameters.")), false);
        return new Validator(definitions, caller).run(root, input);
    }
    private static final class Validator {
        final Map<String, Definition> definitions;
        final Budget budget;
        final Eval structure;
        final List<Validation.Check> checks = new ArrayList<>();
        String currentPath = "";
        Validator(Map<String, Definition> definitions, Budget.Limits caller) {
            this.definitions = definitions; budget = new Budget(Budget.Limits.defaults(), caller); structure = new Eval(budget.beginStructure());
        }
        Validation.Outcome run(String root, Data input) {
            try { check(new Type("named", root, List.of(), List.of(), List.of()), structure.transfer(input), Map.of(), ""); }
            catch (Failure e) { checks.add(new Validation.Undecided(new Validation.Diagnostic(e.code, List.of(currentPath), "", e.getMessage()))); }
            return Validation.collect(checks);
        }
        Checked wrong(String path, String message) {
            checks.add(new Validation.Violated(new Validation.Diagnostic("validation.structure", List.of(path), "", message)));
            return new Checked(null, false);
        }
        Checked check(Type type, Data input, Map<String, Binding> env, String path) {
            currentPath = path;
            return structure.node(() -> {
                switch (type.kind()) {
                    case "refined": {
                        Checked result = check(type.arguments().getFirst(), input, env, path);
                        if (result.shape()) for (Rule rule : type.rules()) rule(rule, result.data(), path);
                        return result;
                    }
                    case "named": {
                        Binding binding = env.get(type.name());
                        return binding == null ? named(type, input, env, path) : check(binding.type(), input, binding.environment(), path);
                    }
                    case "list": {
                        if (!(input instanceof Data.Sequence list)) return wrong(path, "Expected a list.");
                        structure.step(list.values().size()); var items = new ArrayList<Data>(); boolean all = true;
                        for (int i = 0; i < list.values().size(); i++) { Checked result = check(type.arguments().getFirst(), list.values().get(i), env, pointer(path, Integer.toString(i))); all &= result.shape(); if (result.shape()) items.add(result.data()); }
                        return new Checked(all ? new Data.Sequence(items) : null, all);
                    }
                    case "record": {
                        if (!(input instanceof Data.Struct record)) return wrong(path, "Expected a record.");
                        structure.step((long)record.fields().size() + type.fields().size()); var actual = new HashMap<String, Data>();
                        for (Data.Field field : record.fields()) actual.put(field.name(), field.value());
                        var result = new ArrayList<Data.Field>(); boolean all = true;
                        for (Member field : type.fields()) {
                            Data value = actual.get(field.name()); String childPath = pointer(path, field.name());
                            if (value == null) {
                                if (optional(field.type(), env, 0)) value = new Data.Variant("Nothing", List.of());
                                else { wrong(childPath, "Required field is absent."); all = false; continue; }
                            }
                            Checked checked = check(field.type(), value, env, childPath); all &= checked.shape();
                            if (checked.shape()) result.add(new Data.Field(field.name(), checked.data()));
                        }
                        return new Checked(all ? new Data.Struct(result) : null, all);
                    }
                    default: throw new AssertionError("unhandled generated type");
                }
            });
        }
        Checked named(Type type, Data input, Map<String, Binding> env, String path) {
            String name = type.name(); var args = type.arguments();
            switch (name) {
                case "Bool": return input instanceof Data.Bool ? new Checked(input, true) : wrong(path, "Expected a Boolean.");
                case "String": return input instanceof Data.Text ? new Checked(input, true) : wrong(path, "Expected text.");
                case "Maybe", "Nullable", "Result": {
                    if (!(input instanceof Data.Variant v)) return wrong(path, "Expected an explicit optional, nullable, or result constructor.");
                    String none = name.equals("Maybe") ? "Nothing" : name.equals("Nullable") ? "Null" : "Err";
                    String some = name.equals("Maybe") ? "Just" : name.equals("Nullable") ? "NonNull" : "Ok";
                    if (!name.equals("Result") && v.name().equals(none) && v.values().isEmpty()) return new Checked(input, true);
                    if ((v.name().equals(some) || name.equals("Result") && v.name().equals(none)) && v.values().size() == 1) {
                        int index = name.equals("Result") && v.name().equals("Ok") ? 1 : 0;
                        Checked checked = check(args.get(index), v.values().getFirst(), env, path);
                        return new Checked(checked.shape() ? new Data.Variant(v.name(), List.of(checked.data())) : null, checked.shape());
                    }
                    return wrong(path, "Constructor does not match the declared optional, nullable, or result type.");
                }
            }
            if (numericPrimitive(name)) {
                if (!(input instanceof Data.Number n)) return wrong(path, "Expected an exact number.");
                structure.step(n.value().show().length());
                if (!name.equals("Real") && !n.value().isInteger()) return wrong(path, "Expected an integer without fractional coercion.");
                if (!name.equals("Real") && !name.equals("Int")) {
                    long width = Long.parseLong(name.replace("UInt", "").replace("Int", "")); structure.step(width);
                    if (width > 65536) throw fail("evaluation.unsupported", "integer width exceeds the current numeric backend limit");
                    try { n.value().fixedWidth((int)width, !name.startsWith("UInt")); }
                    catch (ArithmeticException e) { return wrong(path, "Integer is outside its declared fixed-width range."); }
                }
                return new Checked(new Data.Number(n.value(), name), true);
            }
            Definition definition = definitions.get(name); var bindings = bindings(definition, args, env);
            if (definition.body() != null) return check(definition.body(), input, bindings, path);
            if (!(input instanceof Data.Variant value)) return wrong(path, "Expected a tagged data alternative.");
            for (Alternative alternative : definition.alternatives()) {
                structure.step(1); if (!alternative.name().equals(value.name())) continue;
                if (alternative.arguments().size() != value.values().size()) return wrong(path, "Constructor has the wrong number of arguments.");
                var result = new ArrayList<Data>(); boolean all = true;
                for (int i = 0; i < value.values().size(); i++) {
                    Checked checked = check(alternative.arguments().get(i), value.values().get(i), bindings, pointer(path, Integer.toString(i)));
                    all &= checked.shape(); if (checked.shape()) result.add(checked.data());
                }
                return new Checked(all ? new Data.Variant(value.name(), result) : null, all);
            }
            return wrong(path, "Constructor does not belong to the declared data type.");
        }
        Map<String, Binding> bindings(Definition definition, List<Type> arguments, Map<String, Binding> environment) {
            var result = new HashMap<String, Binding>();
            for (int i = 0; i < arguments.size(); i++) result.put(definition.parameters().get(i), new Binding(arguments.get(i), environment));
            return result;
        }
        boolean optional(Type type, Map<String, Binding> env, int depth) {
            structure.step(1); if (depth >= 512) throw fail("evaluation.depth", "optional type expansion nesting limit exceeded");
            if (type.kind().equals("refined")) return optional(type.arguments().getFirst(), env, depth + 1);
            if (!type.kind().equals("named")) return false;
            Binding binding = env.get(type.name()); if (binding != null) return optional(binding.type(), binding.environment(), depth + 1);
            if (type.name().equals("Maybe") && type.arguments().size() == 1) return true;
            Definition definition = definitions.get(type.name());
            return definition != null && definition.body() != null && optional(definition.body(), bindings(definition, type.arguments(), env), depth + 1);
        }
        void rule(Rule rule, Data input, String path) {
            String code = rule.code();
            if (code.isEmpty()) {
                try {
                    byte[] digest = MessageDigest.getInstance("SHA-256").digest((path + ":" + rule.offset() + ":" + rule.predicate()).getBytes(StandardCharsets.UTF_8));
                    code = "refine." + HexFormat.of().formatHex(digest, 0, 8);
                } catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
            }
            String message = "Value must satisfy the declared condition: " + rule.predicate() + ".";
            Eval evaluator = new Eval(budget.beginClause(rule.steps())); var env = Map.of("it", input);
            boolean satisfied;
            try { satisfied = ((Data.Bool)evaluator.expression(rule.expression(), env)).value(); }
            catch (Failure e) {
                checks.add(new Validation.Undecided(new Validation.Diagnostic(code, List.of(path), rule.predicate(), "Could not determine whether the condition holds: " + e.code + ": " + e.getMessage() + "."))); return;
            }
            if (satisfied) { checks.add(new Validation.Satisfied()); return; }
            if (rule.message() != null) {
                try { String custom = ((Data.Text)evaluator.expression(rule.message(), env)).value(); TextCodec.utf8(custom); message = custom; }
                catch (Failure | IllegalArgumentException ignored) { /* The violation remains conclusive. */ }
            }
            checks.add(new Validation.Violated(new Validation.Diagnostic(code, List.of(path), rule.predicate(), message)));
        }
    }
}
`
