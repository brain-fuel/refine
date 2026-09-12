package java

const functionExecutionJava = `
                void resolve(String name, Type signature, int level, Consumer<Val> done) {
                    FunctionDef function = functions.get(name);
                    if (function != null) {
                        int arity = function.equations().getFirst().patterns().size();
                        if (arity == 0) invoke(name, List.of(), signature, level, done);
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
                        case "not", "length", "reverse", "unique", "isInteger" -> 1;
                        case "map", "filter", "all", "any", "oneOf", "elem", "satisfiesAll", "satisfiesOnlyOneOf", "satisfiesOneOf", "satisfiesAtLeastOneOf" -> 2;
                        case "foldl" -> 3;
                        default -> null;
                    };
                    if (arity == null) throw fail("evaluation.name", "unresolved function or variable");
                    work.complete(done, new FunctionValue(name, arity, List.of(), signature));
                }
                void apply(Val function, Val argument, int level, Consumer<Val> done) {
                    work.later(() -> {
                        enterDepth(level);
                        if (function instanceof GuardedFunction guarded) {
                            assertInline(guarded.argument(), argument, guarded.types(), level + 1, checked ->
                                apply(guarded.function(), checked, level + 1, result ->
                                    assertInline(guarded.result(), result, guarded.types(), level + 1, done)));
                            return;
                        }
                        if (!(function instanceof FunctionValue fn)) throw fail("evaluation.type", "application requires a function");
                        step((long)fn.arguments().size() + 1); var arguments = new ArrayList<>(fn.arguments()); arguments.add(argument);
                        if (arguments.size() < fn.arity()) work.complete(done, new FunctionValue(fn.name(), fn.arity(), arguments, fn.signature()));
                        else invoke(fn.name(), arguments, fn.signature(), level + 1, done);
                    });
                }
                void invoke(String name, List<Val> args, Type signature, int level, Consumer<Val> done) {
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
                                        if (matched) visit(equation.body(), env, types, level + 1, result -> {
                                            if (args.isEmpty() && hasInline(function.signature())) assertInline(function.signature(), result, types, level + 1, done);
                                            else work.complete(done, result);
                                        }); else work.later(this);
                                    });
                                }
                            });
                        } else if (constructors.containsKey(name)) work.complete(done, new VariantValue(name, args));
                        else builtin(name, args, level + 1, done);
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
                void builtin(String name, List<Val> args, int level, Consumer<Val> done) {
                    switch (name) {
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
                                    apply(args.getFirst(), item, level, value -> {
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
                                    apply(args.getFirst(), result, level, fn -> apply(fn, item, level, value -> { result = value; work.later(this); }));
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
                        case "all", "any", "satisfiesAll", "satisfiesOnlyOneOf", "satisfiesOneOf", "satisfiesAtLeastOneOf" -> combine(name, args, level, done);
                        default -> throw fail("evaluation.name", "unsupported built-in function");
                    }
                }
                void combine(String name, List<Val> args, int level, Consumer<Val> done) {
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
                            work.<Val>attempt(receiver -> apply(fn, argument, level, receiver), value -> {
                                boolean satisfied = ((BoolValue)value).value(); if (satisfied) yes++;
                                if (mode.equals("all") && !satisfied || mode.equals("any") && satisfied || mode.equals("one") && yes > 1)
                                    work.complete(done, new BoolValue(mode.equals("any")));
                                else work.later(this);
                            }, failure -> { if (unknown == null) unknown = failure; work.later(this); });
                        }
                    });
                }
`
