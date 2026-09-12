package java

const codecExecutionJava = `
                void show(Val input, int level, Consumer<String> done) {
                    work.later(() -> {
                        enterDepth(level);
                        switch (input) {
                            case NumberValue number -> { String shown = number.value().show(); step(shown.length()); work.complete(done, shown); }
                            case TextValue text -> { step(text.value().length()); work.complete(done, TextCodec.show(text.value())); }
                            case TimestampValue timestamp -> { step(timestamp.value().raw().length()); work.complete(done, timestamp.value().show()); }
                            case BoolValue bool -> work.complete(done, bool.value() ? "True" : "False");
                            case FunctionValue ignored -> throw fail("evaluation.show", "functions do not support canonical display");
                            case GuardedFunction ignored -> throw fail("evaluation.show", "functions do not support canonical display");
                            case ListValue list -> {
                                step(list.values().size());
                                showItems(list.values(), level + 1, false, parts -> work.complete(done, "[" + String.join(", ", parts) + "]"));
                            }
                            case RecordValue record -> {
                                long levels = 1; for (int n = record.fields().size(); n > 1; n >>= 1) levels++;
                                step(record.fields().size() * levels);
                                var fields = new ArrayList<>(record.fields());
                                fields.sort((a, b) -> scalarCompare(a.name(), b.name()));
                                work.later(new Runnable() {
                                    int index; final List<String> parts = new ArrayList<>();
                                    @Override public void run() {
                                        if (index == fields.size()) { work.complete(done, "{" + String.join(", ", parts) + "}"); return; }
                                        FieldValue field = fields.get(index++); step(utf8Size(field.name()));
                                        if (!codecIdentifier(field.name(), false)) throw fail("evaluation.show", "record field is not representable in the canonical value grammar");
                                        show(field.value(), level + 1, shown -> { parts.add(field.name() + " = " + shown); work.later(this); });
                                    }
                                });
                            }
                            case VariantValue variant -> {
                                step((long)utf8Size(variant.name()) + variant.values().size());
                                if (!codecIdentifier(variant.name(), true)) throw fail("evaluation.show", "constructor is not representable in the canonical value grammar");
                                if (variant.values().isEmpty()) { work.complete(done, variant.name()); return; }
                                showItems(variant.values(), level + 1, true, parts -> work.complete(done, "(" + variant.name() + " " + String.join(" ", parts) + ")"));
                            }
                        }
                    });
                }
                void showItems(List<Val> values, int level, boolean constructor, Consumer<List<String>> done) {
                    work.later(new Runnable() {
                        int index; final List<String> parts = new ArrayList<>();
                        @Override public void run() {
                            if (index == values.size()) { work.complete(done, parts); return; }
                            Val value = values.get(index++);
                            show(value, level, shown -> {
                                if (constructor && value instanceof NumberValue && (shown.startsWith("-") || shown.contains("/"))) parts.add("(" + shown + ")");
                                else parts.add(shown);
                                work.later(this);
                            });
                        }
                    });
                }
`

const codecNamesJava = `
    private static boolean codecReserved(String name) {
        return switch (name) { case "type", "data", "where", "if", "then", "else", "let", "in", "case", "of", "import", "package" -> true; default -> false; };
    }
    private static boolean codecIdentifier(String name, boolean constructor) {
        if (name.isEmpty() || codecReserved(name)) return false;
        if (constructor && (!CodecUnicode.upper(name.codePointAt(0)) || name.equals("True") || name.equals("False"))) return false;
        for (int i = 0; i < name.length();) {
            int scalar = name.codePointAt(i);
            if (!CodecUnicode.letter(scalar) && scalar != '_' && (i == 0 || !CodecUnicode.digit(scalar) && scalar != '\'')) return false;
            i += Character.charCount(scalar);
        }
        return true;
    }
    private static int scalarCompare(String a, String b) {
        int i = 0, j = 0;
        while (i < a.length() && j < b.length()) {
            int left = a.codePointAt(i), right = b.codePointAt(j);
            if (left != right) return Integer.compare(left, right);
            i += Character.charCount(left); j += Character.charCount(right);
        }
        return Integer.compare(a.length() - i, b.length() - j);
    }
`
