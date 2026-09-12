package java

// The simplifier and instruction ordering follow Go's regexp/syntax compiler.
// Its full BSD-style notice is emitted by regexProgramJava alongside this code.
const regexCompileJava = `
    public enum TreeOp { NO_MATCH, EMPTY, LITERAL, CLASS, ANY_NOT_NL, ANY, BEGIN_LINE, END_LINE, BEGIN_TEXT, END_TEXT, WORD_BOUNDARY, NO_WORD_BOUNDARY, CAPTURE, STAR, PLUS, QUEST, REPEAT, CONCAT, ALTERNATE }
    public record Tree(TreeOp op, int flags, List<Integer> runes, List<Tree> children, int min, int max, int capture, String name) {
        public Tree {
            Objects.requireNonNull(op); Objects.requireNonNull(name); runes = List.copyOf(runes); children = List.copyOf(children);
            if (flags < 0 || flags > 0xffff || capture < 0) throw invalidTree();
            switch (op) {
                case CAPTURE, STAR, PLUS, QUEST, REPEAT -> { if (children.size() != 1) throw invalidTree(); }
                case CONCAT, ALTERNATE -> { }
                default -> { if (!children.isEmpty()) throw invalidTree(); }
            }
            if (op != TreeOp.LITERAL && op != TreeOp.CLASS && !runes.isEmpty()) throw invalidTree();
            for (int point : runes) if (point < 0 || point > 0x10ffff) throw invalidTree();
            if (op == TreeOp.CLASS) {
                if (runes.size() % 2 != 0) throw invalidTree();
                for (int i = 1; i < runes.size(); i++) if (i % 2 == 1 ? runes.get(i) < runes.get(i-1) : runes.get(i) <= runes.get(i-1)) throw invalidTree();
            }
            if (op == TreeOp.REPEAT && (min < 0 || max < -1 || max != -1 && max < min)) throw invalidTree();
        }
    }
    private static IllegalArgumentException invalidTree() { return new IllegalArgumentException("invalid parsed regular expression tree"); }
    private static Tree tree(TreeOp op, int flags, List<Tree> children) { return new Tree(op, flags, List.of(), children, 0, 0, 0, ""); }
    private static Error expansionLimit() { return new Error("regex.limit", "regular expression expansion is too large"); }
    private static void charge(Budget.Meter meter, java.math.BigInteger cost) {
        try { meter.step(cost); } catch (Budget.Exceeded failure) { throw new Error("regex.budget", "regular expression step budget exhausted"); }
    }
    private static final class BoundFrame {
        final Tree tree; final int depth; int index; java.math.BigInteger total;
        BoundFrame(Tree tree, int depth, Budget.Meter meter) {
            if (depth >= 512) throw new Error("regex.limit", "regular expression nesting limit exceeded");
            charge(meter, 1); this.tree = tree; this.depth = depth;
            total = java.math.BigInteger.valueOf(4L + tree.runes().size() + tree.children().size());
        }
    }
    private static java.math.BigInteger expansion(Tree tree, Budget.Meter meter) {
        var stack = new java.util.ArrayDeque<BoundFrame>(); stack.push(new BoundFrame(tree, 0, meter));
        while (true) {
            var frame = stack.peek();
            if (frame.index < frame.tree.children().size()) { stack.push(new BoundFrame(frame.tree.children().get(frame.index++), frame.depth + 1, meter)); continue; }
            if (frame.tree.op() == TreeOp.REPEAT) {
                long count = frame.tree.max(); if (count < 0) count = (long)frame.tree.min() + 1;
                frame.total = frame.total.multiply(java.math.BigInteger.valueOf(Math.max(count, 1)));
                if (frame.total.compareTo(Budget.MAX) > 0) throw expansionLimit();
            }
            stack.pop(); if (stack.isEmpty()) return frame.total;
            var parent = stack.peek(); parent.total = parent.total.add(frame.total);
            if (parent.total.compareTo(Budget.MAX) > 0) throw expansionLimit();
        }
    }
    private static final class CompileQueue {
        final java.util.ArrayDeque<Runnable> tasks = new java.util.ArrayDeque<>();
        void later(Runnable task) { tasks.push(task); }
        <T> void complete(java.util.function.Consumer<T> done, T value) { later(() -> done.accept(value)); }
        void run() { while (!tasks.isEmpty()) tasks.pop().run(); }
    }
    private static Tree unary(TreeOp op, int flags, Tree sub, Tree original) {
        if (sub.op() == TreeOp.EMPTY || op == sub.op() && (flags & 32) == (sub.flags() & 32)) return sub;
        if (original != null && original.op() == op && (original.flags() & 32) == (flags & 32) && sub == original.children().getFirst()) return original;
        return tree(op, flags, List.of(sub));
    }
    private static void simplify(Tree node, CompileQueue queue, java.util.function.Consumer<Tree> done) {
        queue.later(() -> {
            switch (node.op()) {
                case CAPTURE, CONCAT, ALTERNATE -> queue.later(new Runnable() {
                    int index; boolean changed; final List<Tree> children = new ArrayList<>();
                    @Override public void run() {
                        if (index == node.children().size()) {
                            queue.complete(done, changed ? new Tree(node.op(), node.flags(), List.of(), children, node.min(), node.max(), node.capture(), node.name()) : node); return;
                        }
                        Tree child = node.children().get(index++);
                        simplify(child, queue, result -> { changed |= result != child; children.add(result); queue.later(this); });
                    }
                });
                case STAR, PLUS, QUEST -> simplify(node.children().getFirst(), queue, sub -> queue.complete(done, unary(node.op(), node.flags(), sub, node)));
                case REPEAT -> {
                    if (node.min() == 0 && node.max() == 0) { queue.complete(done, tree(TreeOp.EMPTY, 0, List.of())); return; }
                    simplify(node.children().getFirst(), queue, sub -> {
                        if (node.max() == -1) {
                            if (node.min() == 0) { queue.complete(done, unary(TreeOp.STAR, node.flags(), sub, null)); return; }
                            if (node.min() == 1) { queue.complete(done, unary(TreeOp.PLUS, node.flags(), sub, null)); return; }
                            var children = new ArrayList<Tree>(); for (int i = 0; i < node.min()-1; i++) children.add(sub);
                            children.add(unary(TreeOp.PLUS, node.flags(), sub, null)); queue.complete(done, tree(TreeOp.CONCAT, 0, children)); return;
                        }
                        if (node.min() == 1 && node.max() == 1) { queue.complete(done, sub); return; }
                        var prefix = new ArrayList<Tree>(); for (int i = 0; i < node.min(); i++) prefix.add(sub);
                        if (node.max() > node.min()) {
                            Tree suffix = unary(TreeOp.QUEST, node.flags(), sub, null);
                            for (int i = node.min()+1; i < node.max(); i++) suffix = unary(TreeOp.QUEST, node.flags(), tree(TreeOp.CONCAT, 0, List.of(sub, suffix)), null);
                            if (prefix.isEmpty()) { queue.complete(done, suffix); return; }
                            prefix.add(suffix);
                        }
                        queue.complete(done, tree(prefix.isEmpty() ? TreeOp.NO_MATCH : TreeOp.CONCAT, 0, prefix));
                    });
                }
                default -> queue.complete(done, node);
            }
        });
    }
    private static final class MutableInstruction {
        Opcode opcode; long out, arg; List<Integer> runes = List.of();
        MutableInstruction(Opcode opcode) { this.opcode = opcode; }
    }
    private record Patches(long head, long tail) {}
    private record Fragment(int index, Patches patches, boolean nullable) {}
    private static final Patches NO_PATCHES = new Patches(0, 0);
    private static final Fragment NO_FRAGMENT = new Fragment(0, NO_PATCHES, false);
    private static Patches patchList(long pointer) { return new Patches(pointer, pointer); }
    private static final class TreeCompiler {
        final List<MutableInstruction> instructions = new ArrayList<>(); final CompileQueue queue = new CompileQueue();
        TreeCompiler() { instruction(Opcode.FAIL); }
        Fragment instruction(Opcode op) {
            int index = instructions.size(); instructions.add(new MutableInstruction(op)); return new Fragment(index, NO_PATCHES, true);
        }
        void patch(Patches patches, int value) {
            long head = patches.head();
            while (head != 0) {
                var instruction = instructions.get((int)(head >>> 1));
                if ((head & 1) == 0) { head = instruction.out; instruction.out = value; }
                else { head = instruction.arg; instruction.arg = value; }
            }
        }
        Patches append(Patches first, Patches second) {
            if (first.head() == 0) return second; if (second.head() == 0) return first;
            var instruction = instructions.get((int)(first.tail() >>> 1));
            if ((first.tail() & 1) == 0) instruction.out = second.head(); else instruction.arg = second.head();
            return new Patches(first.head(), second.tail());
        }
        Fragment simple(Opcode opcode, long arg) {
            Fragment f = instruction(opcode); instructions.get(f.index()).arg = arg;
            return new Fragment(f.index(), patchList((long)f.index() << 1), true);
        }
        Fragment cat(Fragment first, Fragment second) {
            if (first.index() == 0 || second.index() == 0) return NO_FRAGMENT;
            patch(first.patches(), second.index()); return new Fragment(first.index(), second.patches(), first.nullable() && second.nullable());
        }
        Fragment alt(Fragment first, Fragment second) {
            if (first.index() == 0) return second; if (second.index() == 0) return first;
            Fragment f = instruction(Opcode.ALT); var inst = instructions.get(f.index()); inst.out = first.index(); inst.arg = second.index();
            return new Fragment(f.index(), append(first.patches(), second.patches()), first.nullable() || second.nullable());
        }
        Fragment branch(Fragment child, boolean lazy, boolean loop) {
            Fragment f = instruction(Opcode.ALT); var inst = instructions.get(f.index()); Patches patches;
            if (lazy) { inst.arg = child.index(); patches = patchList((long)f.index() << 1); }
            else { inst.out = child.index(); patches = patchList(((long)f.index() << 1) | 1); }
            if (loop) patch(child.patches(), f.index()); else patches = append(patches, child.patches());
            return new Fragment(f.index(), patches, true);
        }
        Fragment plus(Fragment child, boolean lazy) { return new Fragment(child.index(), branch(child, lazy, true).patches(), child.nullable()); }
        Fragment star(Fragment child, boolean lazy) { return child.nullable() ? branch(plus(child, lazy), lazy, false) : branch(child, lazy, true); }
        Fragment rune(List<Integer> runes, int flags) {
            Fragment f = instruction(Opcode.RUNE); var inst = instructions.get(f.index()); inst.runes = runes;
            flags &= 1; if (runes.size() != 1 || simpleFold(runes.getFirst()) == runes.getFirst()) flags = 0;
            inst.arg = flags;
            if (flags == 0 && (runes.size() == 1 || runes.size() == 2 && runes.getFirst().equals(runes.get(1)))) inst.opcode = Opcode.RUNE1;
            else if (runes.equals(List.of(0,0x10ffff))) inst.opcode = Opcode.RUNE_ANY;
            else if (runes.equals(List.of(0,9,11,0x10ffff))) inst.opcode = Opcode.RUNE_ANY_NOT_NL;
            return new Fragment(f.index(), patchList((long)f.index() << 1), false);
        }
        void visit(Tree node, java.util.function.Consumer<Fragment> done) {
            queue.later(() -> {
                boolean lazy = (node.flags() & 32) != 0;
                switch (node.op()) {
                    case NO_MATCH -> queue.complete(done, NO_FRAGMENT);
                    case EMPTY -> queue.complete(done, simple(Opcode.NOP, 0));
                    case LITERAL -> {
                        if (node.runes().isEmpty()) { queue.complete(done, simple(Opcode.NOP, 0)); return; }
                        Fragment result = null;
                        for (int point : node.runes()) { Fragment next = rune(List.of(point), node.flags()); result = result == null ? next : cat(result, next); }
                        queue.complete(done, result);
                    }
                    case CLASS -> queue.complete(done, rune(node.runes(), node.flags()));
                    case ANY -> queue.complete(done, rune(List.of(0,0x10ffff), 0));
                    case ANY_NOT_NL -> queue.complete(done, rune(List.of(0,9,11,0x10ffff), 0));
                    case BEGIN_LINE -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 1));
                    case END_LINE -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 2));
                    case BEGIN_TEXT -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 4));
                    case END_TEXT -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 8));
                    case WORD_BOUNDARY -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 16));
                    case NO_WORD_BOUNDARY -> queue.complete(done, simple(Opcode.EMPTY_WIDTH, 32));
                    case CAPTURE -> {
                        Fragment before = simple(Opcode.CAPTURE, (long)node.capture() << 1);
                        visit(node.children().getFirst(), child -> queue.complete(done, cat(cat(before, child), simple(Opcode.CAPTURE, ((long)node.capture() << 1) | 1))));
                    }
                    case STAR -> visit(node.children().getFirst(), child -> queue.complete(done, star(child, lazy)));
                    case PLUS -> visit(node.children().getFirst(), child -> queue.complete(done, plus(child, lazy)));
                    case QUEST -> visit(node.children().getFirst(), child -> queue.complete(done, branch(child, lazy, false)));
                    case CONCAT, ALTERNATE -> queue.later(new Runnable() {
                        int index; Fragment result = NO_FRAGMENT;
                        @Override public void run() {
                            if (index == node.children().size()) { queue.complete(done, index == 0 && node.op() == TreeOp.CONCAT ? simple(Opcode.NOP, 0) : result); return; }
                            int position = index++;
                            visit(node.children().get(position), child -> {
                                result = node.op() == TreeOp.ALTERNATE ? alt(result, child) : position == 0 ? child : cat(result, child); queue.later(this);
                            });
                        }
                    });
                    case REPEAT -> throw new AssertionError("counted repetition survived simplification");
                }
            });
        }
        RegexProgram finish(Fragment fragment) {
            patch(fragment.patches(), instruction(Opcode.MATCH).index()); var result = new ArrayList<Instruction>();
            for (var instruction : instructions) result.add(new Instruction(instruction.opcode, (int)instruction.out, instruction.arg, instruction.runes));
            return new RegexProgram(PROFILE, UNICODE_VERSION, fragment.index(), result);
        }
    }
    /** Compile an already parsed/normalized tree. Source parsing and its initial
     * size charge belong to the caller; this boundary meters tree expansion
     * before simplifying counted repetitions or allocating instructions.
     */
    public static RegexProgram compileTree(Tree tree, Budget.Meter meter) {
        Objects.requireNonNull(tree); Objects.requireNonNull(meter); charge(meter, expansion(tree, meter));
        var compiler = new TreeCompiler(); RegexProgram[] result = new RegexProgram[1];
        simplify(tree, compiler.queue, simple -> compiler.visit(simple, fragment -> result[0] = compiler.finish(fragment)));
        compiler.queue.run(); return result[0];
    }
`
