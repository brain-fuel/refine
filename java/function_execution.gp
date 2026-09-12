package java

const functionExecutionJava = `
                private String fixedConversionType(String name) {
                    String type=name.startsWith("from")||name.startsWith("wrap")?name.substring(4):name.startsWith("to")?name.substring(2):"";
                    String digits=type.startsWith("UInt")?type.substring(4):type.startsWith("Int")?type.substring(3):"";
                    try { int bits=Integer.parseInt(digits); return bits>0 && bits<=65536 && Integer.toString(bits).equals(digits) ? type : null; }
                    catch (NumberFormatException ignored) { return null; }
                }
                private String floatConversionType(String name) {
                    for (String prefix : List.of("roundTo", "to", "from")) if (name.startsWith(prefix)) {
                        String type = name.substring(prefix.length()); if (type.equals("Float32") || type.equals("Float64")) return type;
                    }
                    return null;
                }
                void resolve(String name, Type signature, Map<String, Binding> types, int level, Consumer<Val> done) {
                    FunctionDef function = functions.get(name);
                    if (function != null) {
                        int arity = function.equations().getFirst().patterns().size();
                        if (arity == 0) invoke(name, List.of(), signature, types, level, done);
                        else {
                            Val value = new FunctionValue(name, arity, List.of(), signature);
                            if (hasInline(function.signature())) assertInline(function.signature(), value, functionBindings(name, signature), level, done);
                            else work.complete(done, value);
                        }
                        return;
                    }
                    Integer arity = constructors.get(name);
                    if (arity != null) {
                        work.complete(done, arity == 0 ? new VariantValue(name, List.of()) : new FunctionValue(name, arity, List.of(), signature)); return;
                    }
                    arity = switch (name) {
                        case "not", "length", "reverse", "unique", "isInteger", "show", "read", "toReal", "toInteger", "truncate", "floor", "ceiling", "roundHalfEven" -> 1;
                        case "map", "filter", "all", "any", "oneOf", "elem", "satisfiesAll", "satisfiesOnlyOneOf", "satisfiesOneOf", "satisfiesAtLeastOneOf", "matches", "search" -> 2;
                        case "foldl" -> 3;
                        case "civilSecondsUntil", "siSecondsUntil" -> 2;
                        default -> fixedConversionType(name) == null && floatConversionType(name) == null ? null : 1;
                    };
                    if (arity == null) throw fail("evaluation.name", "unresolved function or variable");
                    work.complete(done, new FunctionValue(name, arity, List.of(), signature));
                }
                void apply(Val function, Val argument, Map<String, Binding> types, int level, Consumer<Val> done) {
                    work.later(() -> {
                        enterDepth(level);
                        if (function instanceof GuardedFunction guarded) {
                            assertInline(guarded.argument(), argument, guarded.types(), level + 1, checked ->
                                apply(guarded.function(), checked, types, level + 1, result ->
                                    assertInline(guarded.result(), result, guarded.types(), level + 1, done)));
                            return;
                        }
                        if (!(function instanceof FunctionValue fn)) throw fail("evaluation.type", "application requires a function");
                        step((long)fn.arguments().size() + 1); var arguments = new ArrayList<>(fn.arguments()); arguments.add(argument);
                        if (arguments.size() < fn.arity()) work.complete(done, new FunctionValue(fn.name(), fn.arity(), arguments, fn.signature()));
                        else invoke(fn.name(), arguments, fn.signature(), types, level + 1, done);
                    });
                }
                void invoke(String name, List<Val> args, Type signature, Map<String, Binding> callerTypes, int level, Consumer<Val> done) {
                    work.later(() -> {
                        enterDepth(level); FunctionDef function = functions.get(name);
                        if (function != null) {
                            var types = functionBindings(name, signature);
                            work.later(new Runnable() {
                                int index;
                                @Override public void run() {
                                    if (index == function.equations().size()) throw fail("evaluation.pattern", "no function equation matched");
                                    Equation equation = function.equations().get(index++); var env = new HashMap<String, Val>();
                                    patterns(equation.patterns(), args, env, types, level + 1, matched -> {
                                        // A named call is a new queued evaluator frame. Reset
                                        // expression-tree depth so recursion consumes budget,
                                        // not one logical/host nesting frame per call.
                                        if (matched) visit(equation.body(), env, types, 0, result -> {
                                            if (args.isEmpty() && hasInline(function.signature())) assertInline(function.signature(), result, types, level + 1, done);
                                            else work.complete(done, result);
                                        }); else work.later(this);
                                    });
                                }
                            });
                        } else if (constructors.containsKey(name)) work.complete(done, new VariantValue(name, args));
                        // Literal decoding inherits the enclosing structural
                        // frame, not ordinary expression-call syntax. Nested
                        // validating reads must still share the data-depth cap.
                        else if (name.equals("read")) typedRead(signature, args.getFirst(), callerTypes, Eval.this.depth, done);
                        else builtin(name, args, callerTypes, level + 1, done);
                    });
                }
                void patterns(List<Pattern> patterns, List<Val> values, Map<String, Val> env, Map<String, Binding> types, int level, Consumer<Boolean> done) {
                    work.later(new Runnable() {
                        int index;
                        @Override public void run() {
                            if (index == patterns.size()) { work.complete(done, true); return; }
                            int i = index++;
                            pattern(patterns.get(i), values.get(i), env, types, level, matched -> {
                                if (matched) work.later(this); else work.complete(done, false);
                            });
                        }
                    });
                }
                void pattern(Pattern pattern, Val value, Map<String, Val> env, Map<String, Binding> types, int level, Consumer<Boolean> done) {
                    work.later(() -> {
                        enterDepth(level);
                        switch (pattern.kind()) {
                            case "bind" -> { env.put(pattern.name(), value); work.complete(done, true); }
                            case "wild" -> work.complete(done, true);
                            case "literal" -> visit(pattern.literal(), Map.of(), types, level + 1, literal ->
                                work.complete(done, atDepth(level + 1, () -> equal(value, literal))));
                            case "constructor" -> {
                                if (!(value instanceof VariantValue variant) || !variant.name().equals(pattern.name()) || variant.values().size() != pattern.arguments().size()) { work.complete(done, false); return; }
                                patterns(pattern.arguments(), variant.values(), env, types, level + 1, done);
                            }
                            case "list" -> {
                                if (!(value instanceof ListValue list) || list.values().size() != pattern.arguments().size()) { work.complete(done, false); return; }
                                patterns(pattern.arguments(), list.values(), env, types, level + 1, done);
                            }
                            case "cons" -> {
                                if (!(value instanceof ListValue list) || list.values().isEmpty()) { work.complete(done, false); return; }
                                pattern(pattern.arguments().getFirst(), list.values().getFirst(), env, types, level + 1, matched -> {
                                    if (!matched) work.complete(done, false);
                                    else pattern(pattern.arguments().get(1), new ListValue(list.values().subList(1, list.values().size())), env, types, level + 1, done);
                                });
                            }
                            default -> throw new AssertionError("unhandled checked pattern");
                        }
                    });
                }
                void builtin(String name, List<Val> args, Map<String, Binding> types, int level, Consumer<Val> done) {
                    String fixed=fixedConversionType(name);
                    if (fixed != null) {
                        boolean signed=!fixed.startsWith("UInt"); int bits=Integer.parseInt(fixed.substring(signed?3:4));
                        Rational number=((NumberValue)args.getFirst()).value(); long size=number.show().length(); step(size*size+bits+1);
                        if (name.startsWith("from")) work.complete(done,new NumberValue(number,"Int"));
                        else if (name.startsWith("wrap")) work.complete(done,new NumberValue(number.wrap(bits,signed),fixed));
                        else {
                            try { work.complete(done,new VariantValue("Ok",List.of(new NumberValue(number.fixedWidth(bits,signed),fixed)))); }
                            catch (ArithmeticException failure) { work.complete(done,new VariantValue("Err",List.of(new TextValue("conversion.overflow: value is outside "+fixed+" range")))); }
                        }
                        return;
                    }
                    String floating=floatConversionType(name);
                    if (floating != null) {
                        Rational number=((NumberValue)args.getFirst()).value(); long size=number.show().length(); step(size*size+64);
                        if (name.startsWith("from")) { work.complete(done,new NumberValue(number,"Real")); return; }
                        try {
                            Rational converted=floating.equals("Float32")
                                ? (name.startsWith("roundTo") ? number.roundFloat32() : number.exactFloat32())
                                : (name.startsWith("roundTo") ? number.roundFloat64() : number.exactFloat64());
                            work.complete(done,new VariantValue("Ok",List.of(new NumberValue(converted,floating))));
                        } catch (ArithmeticException failure) {
                            String message=name.startsWith("roundTo")
                                ? "conversion.overflow: rounded value is outside finite "+floating+" range"
                                : "conversion.precision: value is not exactly representable as finite "+floating;
                            work.complete(done,new VariantValue("Err",List.of(new TextValue(message))));
                        }
                        return;
                    }
                    switch (name) {
                        case "toReal", "toInteger", "truncate", "floor", "ceiling", "roundHalfEven" -> {
                            Rational number = ((NumberValue)args.getFirst()).value(); long size = number.show().length(); step(size * size + 1);
                            if (name.equals("toReal")) work.complete(done, new NumberValue(number, "Real"));
                            else if (name.equals("toInteger")) work.complete(done, number.isInteger()
                                ? new VariantValue("Ok", List.of(new NumberValue(number, "Int")))
                                : new VariantValue("Err", List.of(new TextValue("conversion.fractional: exact integer conversion requires denominator one"))));
                            else {
                                Rational rounded = switch (name) {
                                    case "truncate" -> number.truncate(); case "floor" -> number.floor();
                                    case "ceiling" -> number.ceiling(); default -> number.roundHalfEven();
                                };
                                work.complete(done, new NumberValue(rounded, "Int"));
                            }
                        }
                        case "civilSecondsUntil", "siSecondsUntil" -> {
                            Timestamp start = ((TimestampValue)args.getFirst()).value(), end = ((TimestampValue)args.get(1)).value();
                            long size = (long)start.raw().length() + end.raw().length();
                            if (size != 0 && Long.compareUnsigned(size, Long.divideUnsigned(-33L, size)) > 0) throw fail("evaluation.budget", "timestamp duration cost exceeds evaluation resources");
                            step(size * size + 32);
                            try { Rational duration = name.equals("civilSecondsUntil") ? start.civilSecondsUntil(end) : start.siSecondsUntil(end); work.complete(done, new VariantValue("Ok", List.of(new NumberValue(duration, "Real")))); }
                            catch (Timestamp.Error error) { work.complete(done, new VariantValue("Err", List.of(new TextValue(error.code() + ": " + error.getMessage())))); }
                        }
                        case "matches", "search" -> {
                            try {
                                var program = RegexProgram.compile(((TextValue)args.getFirst()).value(), meter);
                                boolean matched = program.match(((TextValue)args.get(1)).value(), name.equals("search") ? RegexProgram.Mode.SEARCH : RegexProgram.Mode.FULL, meter);
                                work.complete(done, new BoolValue(matched));
                            } catch (RegexProgram.Error error) { throw fail(error.code(), error.getMessage()); }
                        }
                        case "show" -> show(args.getFirst(), level, shown -> { step(utf8Size(shown)); work.complete(done, new TextValue(shown)); });
                        case "not" -> work.complete(done, new BoolValue(!((BoolValue)args.getFirst()).value()));
                        case "isInteger" -> { Rational number = ((NumberValue)args.getFirst()).value(); step(number.show().length()); work.complete(done, new BoolValue(number.isInteger())); }
                        case "length" -> {
                            Val value = args.getFirst(); int length = value instanceof TextValue text ? text.value().length() : ((ListValue)value).values().size();
                            work.complete(done, new NumberValue(Rational.of(length), "Int"));
                        }
                        case "reverse" -> { var items = ((ListValue)args.getFirst()).values(); step(items.size()); work.complete(done, new ListValue(items.reversed())); }
                        case "map", "filter" -> {
                            var items = ((ListValue)args.get(1)).values(); step(items.size());
                            work.later(new Runnable() {
                                int index; final List<Val> result = new ArrayList<>();
                                @Override public void run() {
                                    if (index == items.size()) { work.complete(done, new ListValue(result)); return; }
                                    Val item = items.get(index++);
                                    apply(args.getFirst(), item, types, level, value -> {
                                        if (name.equals("map")) result.add(value); else if (((BoolValue)value).value()) result.add(item); work.later(this);
                                    });
                                }
                            });
                        }
                        case "foldl" -> {
                            var items = ((ListValue)args.get(2)).values();
                            work.later(new Runnable() {
                                int index; Val result = args.get(1);
                                @Override public void run() {
                                    if (index == items.size()) { work.complete(done, result); return; }
                                    Val item = items.get(index++); step(1);
                                    apply(args.getFirst(), result, types, level, fn -> apply(fn, item, types, level, value -> { result = value; work.later(this); }));
                                }
                            });
                        }
                        case "oneOf", "elem" -> {
                            boolean found = false;
                            for (Val item : ((ListValue)args.get(1)).values()) if (atDepth(level, () -> equal(args.getFirst(), item))) { found = true; break; }
                            work.complete(done, new BoolValue(found));
                        }
                        case "unique" -> {
                            var items = ((ListValue)args.getFirst()).values(); boolean unique = true;
                            outer: for (int i = 0; i < items.size(); i++) for (int j = 0; j < i; j++) {
                                Val left = items.get(i), right = items.get(j);
                                if (atDepth(level, () -> equal(left, right))) { unique = false; break outer; }
                            }
                            work.complete(done, new BoolValue(unique));
                        }
                        case "all", "any", "satisfiesAll", "satisfiesOnlyOneOf", "satisfiesOneOf", "satisfiesAtLeastOneOf" -> combine(name, args, types, level, done);
                        default -> throw fail("evaluation.name", "unsupported built-in function");
                    }
                }
                void combine(String name, List<Val> args, Map<String, Binding> types, int level, Consumer<Val> done) {
                    String mode = name.equals("all") || name.equals("satisfiesAll") ? "all" : name.equals("satisfiesOnlyOneOf") ? "one" : "any";
                    boolean overValues = name.equals("all") || name.equals("any");
                    var items = ((ListValue)args.get(overValues ? 1 : 0)).values();
                    work.later(new Runnable() {
                        int index; int yes; Failure unknown;
                        @Override public void run() {
                            if (index == items.size()) {
                                if (unknown != null) throw unknown;
                                work.complete(done, new BoolValue(mode.equals("all") || mode.equals("one") && yes == 1)); return;
                            }
                            Val item = items.get(index++), fn = overValues ? args.getFirst() : item, argument = overValues ? item : args.get(1);
                            work.<Val>attempt(receiver -> apply(fn, argument, types, level, receiver), value -> {
                                boolean satisfied = ((BoolValue)value).value(); if (satisfied) yes++;
                                if (mode.equals("all") && !satisfied || mode.equals("any") && satisfied || mode.equals("one") && yes > 1)
                                    work.complete(done, new BoolValue(mode.equals("any")));
                                else work.later(this);
                            }, failure -> { if (unknown == null) unknown = failure; work.later(this); });
                        }
                    });
                }
`
