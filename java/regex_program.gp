package java

import (
    "fmt"
    "strings"
    "unicode"
)

// Pin simple-fold orbits instead of using the JDK's independently versioned
// case mapping. Bounded string chunks keep generated JVM initialization small.
func buildRegexFoldJava()string {
    var encoded strings.Builder
    for point:=rune(0);point<=unicode.MaxRune;point++{fold:=unicode.SimpleFold(point);if fold!=point{fmt.Fprintf(&encoded,"%d,%d,",point,fold)}}
    raw:=strings.TrimSuffix(encoded.String(),",");chunks:=[]string{}
    for len(raw)>8000{chunks=append(chunks,javaQuote(raw[:8000]));raw=raw[8000:]};chunks=append(chunks,javaQuote(raw))
    return fmt.Sprintf("    public static final String UNICODE_VERSION = %s;\n    private static final int[] FOLDS = java.util.Arrays.stream(String.join(\"\", java.util.List.of(%s)).split(\",\")).mapToInt(Integer::parseInt).toArray();\n",javaQuote(unicode.Version),strings.Join(chunks,","))
}

// Immutable source depends only on the pinned toolchain tables; reuse it without
// rescanning all Unicode points for every generated package or fuzz candidate.
var regexFoldSource = buildRegexFoldJava()

func regexProgramJava()string {
    notice:=strings.ReplaceAll(goUnicodeNotice,"Unicode classification tables derived from Go's unicode package.","Simple-fold tables and rune/empty-width matching derived from Go's unicode and regexp/syntax packages.")
    notice=strings.ReplaceAll(notice,"Copyright 2009 The Go Authors.","Copyright 2009, 2011 The Go Authors.")
    return regexProgramImports+notice+regexProgramPrefix+regexFoldSource+regexProgramBody
}

const regexProgramImports = `
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
`
const regexProgramPrefix = `
/** Immutable, metered regex instruction execution. This is not a pattern parser.
 * Go-generated plans and the future Java compiler share this execution boundary.
 * Programs carry an explicit instruction profile and Unicode table version.
 */
public final class RegexProgram {
    public static final String PROFILE = "refine.regex.instructions.v1";
`
const regexProgramBody = `
    public enum Opcode { ALT, ALT_MATCH, CAPTURE, EMPTY_WIDTH, MATCH, FAIL, NOP, RUNE, RUNE1, RUNE_ANY, RUNE_ANY_NOT_NL }
    public enum Mode { FULL, SEARCH }
    public static final class Error extends RuntimeException {
        private static final long serialVersionUID = 1L;
        private final String code;
        private Error(String code, String message) { super(message); this.code = code; }
        public String code() { return code; }
    }
    public record Instruction(Opcode opcode, int out, long arg, List<Integer> runes) {
        public Instruction { Objects.requireNonNull(opcode); runes = List.copyOf(runes); }
    }
    private final int start;
    private final List<Instruction> instructions;
    public RegexProgram(String profile, String unicodeVersion, int start, List<Instruction> instructions) {
        if (!PROFILE.equals(profile) || !UNICODE_VERSION.equals(unicodeVersion)) throw invalid();
        this.instructions = List.copyOf(instructions); this.start = start;
        if (start < 0 || start >= instructions.size()) throw invalid();
        for (Instruction instruction : this.instructions) {
            if (instruction.arg() < 0 || instruction.arg() > 0xffffffffL) throw invalid();
            var runes = instruction.runes();
            boolean consumes = switch (instruction.opcode()) { case RUNE, RUNE1, RUNE_ANY, RUNE_ANY_NOT_NL -> true; default -> false; };
            if (consumes) {
                if (runes.size() > 1 && runes.size() % 2 != 0) throw invalid();
                for (int i = 0; i < runes.size(); i++) {
                    int scalar = runes.get(i); if (scalar < 0 || scalar > 0x10ffff) throw invalid();
                    if (i > 0 && (i % 2 == 1 ? scalar < runes.get(i-1) : scalar <= runes.get(i-1))) throw invalid();
                }
                if (instruction.arg() > 1) throw invalid();
                if (instruction.opcode() == Opcode.RUNE1 && runes.size() != 1 && !(runes.size() == 2 && runes.getFirst().equals(runes.get(1)))) throw invalid();
                if (instruction.opcode() == Opcode.RUNE_ANY && !runes.equals(List.of(0,0x10ffff))) throw invalid();
                if (instruction.opcode() == Opcode.RUNE_ANY_NOT_NL && !runes.equals(List.of(0,9,11,0x10ffff))) throw invalid();
            } else if (!runes.isEmpty()) throw invalid();
            switch (instruction.opcode()) {
                case MATCH, FAIL -> { if (instruction.out() != 0 || instruction.arg() != 0) throw invalid(); }
                case ALT, ALT_MATCH -> { target(instruction.out()); target(instruction.arg()); }
                case EMPTY_WIDTH -> {
                    long arg = instruction.arg(); if (arg != 1 && arg != 2 && arg != 4 && arg != 8 && arg != 16 && arg != 32) throw invalid();
                    target(instruction.out());
                }
                case NOP -> { if (instruction.arg() != 0) throw invalid(); target(instruction.out()); }
                default -> target(instruction.out());
            }
        }
    }
    private static IllegalArgumentException invalid() { return new IllegalArgumentException("invalid regular expression instruction program"); }
    private void target(long pc) { if (pc < 0 || pc >= instructions.size()) throw invalid(); }
    public int start() { return start; }
    public List<Instruction> instructions() { return instructions; }
    private static void charge(Budget.Meter meter, long cost) {
        try { meter.step(cost); } catch (Budget.Exceeded failure) { throw new Error("regex.budget", "regular expression step budget exhausted"); }
    }
    private static int simpleFold(int scalar) {
        int low = 0, high = FOLDS.length / 2;
        while (low < high) {
            int middle = (low + high) >>> 1, point = FOLDS[2*middle];
            if (scalar < point) high = middle; else if (scalar > point) low = middle+1; else return FOLDS[2*middle+1];
        }
        return scalar;
    }
    private static boolean word(int point) { return point >= 'a' && point <= 'z' || point >= 'A' && point <= 'Z' || point >= '0' && point <= '9' || point == '_'; }
    private static boolean emptyWidth(long arg, int before, int after) {
        return switch ((int)arg) {
            case 1 -> before == '\n' || before == -1;
            case 2 -> after == '\n' || after == -1;
            case 4 -> before == -1;
            case 8 -> after == -1;
            case 16 -> word(before) != word(after);
            case 32 -> word(before) == word(after);
            default -> throw new AssertionError("unvalidated empty-width instruction");
        };
    }
    private static boolean rune(Instruction instruction, int point) {
        var ranges = instruction.runes();
        if (ranges.size() == 1) {
            int first = ranges.getFirst(); if (point == first) return true;
            if ((instruction.arg() & 1) != 0) for (int next = simpleFold(first); next != first; next = simpleFold(next)) if (point == next) return true;
            return false;
        }
        int low = 0, high = ranges.size()/2;
        while (low < high) {
            int middle = (low+high) >>> 1;
            if (point < ranges.get(2*middle)) high = middle;
            else if (point > ranges.get(2*middle+1)) low = middle+1;
            else return true;
        }
        return false;
    }
    /** Iterative Thompson state sets; no backtracking or host-stack recursion.
     * Valid surrogate pairs form one point; lone UTF-16 units retain identity.
     * Every invocation owns its state, so programs can be shared across threads.
     */
    public boolean match(String subject, Mode mode, Budget.Meter meter) {
        Objects.requireNonNull(subject); Objects.requireNonNull(mode); Objects.requireNonNull(meter);
        charge(meter, (long)subject.length() + instructions.size());
        int[] points = subject.codePoints().toArray();
        int[] visited = new int[instructions.size()]; Arrays.fill(visited,-1);
        var seeds = new ArrayList<Integer>(); boolean search = mode == Mode.SEARCH;
        for (int position = 0; position <= points.length; position++) {
            charge(meter,1);
            int before = position > 0 ? points[position-1] : -1, after = position < points.length ? points[position] : -1;
            if (position == 0 || search) seeds.add(start);
            var work = seeds; var next = new ArrayList<Integer>();
            while (!work.isEmpty()) {
                charge(meter,1); int pc = work.removeLast();
                if (visited[pc] == position) continue; visited[pc] = position;
                Instruction instruction = instructions.get(pc);
                switch (instruction.opcode()) {
                    case ALT, ALT_MATCH -> { work.add((int)instruction.arg()); work.add(instruction.out()); }
                    case CAPTURE, NOP -> work.add(instruction.out());
                    case EMPTY_WIDTH -> { if (emptyWidth(instruction.arg(),before,after)) work.add(instruction.out()); }
                    case MATCH -> { if (search || position == points.length) return true; }
                    case FAIL -> { }
                    case RUNE, RUNE1, RUNE_ANY, RUNE_ANY_NOT_NL -> {
                        if (position == points.length) continue;
                        long cost = 1; for (int n = instruction.runes().size(); n > 1; n >>= 1) cost++;
                        if ((instruction.arg() & 1) != 0) cost += 4;
                        charge(meter,cost); if (rune(instruction,after)) next.add(instruction.out());
                    }
                }
            }
            seeds = next; if (!search && seeds.isEmpty()) return false;
        }
        return false;
    }
}
`
