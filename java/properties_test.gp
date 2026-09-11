package java

import (
    "crypto/sha256"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "testing"
)

// Dependencies are provisioned separately: neither generation nor tests fetch
// network resources. Verify bytes before executing third-party test code.
func jetCheckClasspath(t *testing.T) string {
    t.Helper()
    dir := os.Getenv("REFINE_JETCHECK_DIR")
    if dir == "" {
        if os.Getenv("REFINE_REQUIRE_JAVA") == "1" { t.Fatal("REFINE_JETCHECK_DIR is required for the Java release gate") }
        t.Skip("set REFINE_JETCHECK_DIR to run jetCheck properties; mandatory in CI")
    }
    jars := []struct { name string; digest string }{
        {"jetCheck-0.3.0.jar", "e19162a11d3c2865f7bd35819c85dc3dc65ddfec41f649b46078d201991dca1e"},
        {"annotations-13.0.jar", "ace2a10dc8e2d5fd34925ecac03e4988b2c0f851650c94b8cef49ba1bd111478"},
    }
    paths := []string{}
    for _, jar := range jars {
        target := filepath.Join(dir, jar.name)
        data, err := os.ReadFile(target); if err != nil { t.Fatal(err) }
        if fmt.Sprintf("%x", sha256.Sum256(data)) != jar.digest { t.Fatalf("checksum mismatch: %s", jar.name) }
        paths = append(paths, target)
    }
    return strings.Join(paths, string(os.PathListSeparator))
}

func TestGeneratedJavaJetCheck(t *testing.T) {
    compiler, vm := javaTools(t)
    dependencies := jetCheckClasspath(t)
    root := t.TempDir()
    files, err := GenerateRuntime("refine.runtime"); if err != nil { t.Fatal(err) }
    sources := []string{}
    for _, file := range files {
        target := filepath.Join(root, filepath.FromSlash(file.Path))
        if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil { t.Fatal(err) }
        if err := os.WriteFile(target, []byte(file.Source), 0644); err != nil { t.Fatal(err) }
        sources = append(sources, target)
    }
    harness := filepath.Join(root, "Properties.java")
    if err := os.WriteFile(harness, []byte(propertiesJava), 0644); err != nil { t.Fatal(err) }
    sources = append(sources, harness)
    classes := filepath.Join(root, "classes")
    args := append([]string{"--release", "25", "-encoding", "UTF-8", "-Xlint:all", "-Werror", "-cp", dependencies, "-d", classes}, sources...)
    if output, err := exec.Command(compiler, args...).CombinedOutput(); err != nil { t.Fatalf("javac properties: %v\n%s", err, output) }
    cp := classes + string(os.PathListSeparator) + dependencies
    if output, err := exec.Command(vm, "-cp", cp, "Properties").CombinedOutput(); err != nil { t.Fatalf("jetCheck (including replay instructions): %v\n%s", err, output) } else { t.Log(string(output)) }
}

const propertiesJava = `
import refine.runtime.*;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.List;
import org.jetbrains.jetCheck.Generator;
import org.jetbrains.jetCheck.PropertyChecker;
import org.jetbrains.jetCheck.PropertyFalsified;

public final class Properties {
    record Pair(Rational a, Rational b) {}
    record Triple(Pair pair, Rational c) {}
    record Trace(int limit, List<Integer> costs) {}
    static final Validation.Diagnostic DETAIL = new Validation.Diagnostic("rule", List.of("/value"), "predicate", "explanation");
    static void require(boolean condition) { if (!condition) throw new AssertionError("law failed"); }
    public static void main(String[] args) {
        Generator<Rational> rational = Generator.zipWith(Generator.integers(), Generator.integers(1, Integer.MAX_VALUE),
            (n, d) -> new Rational(BigInteger.valueOf(n), BigInteger.valueOf(d)));
        Generator<Triple> triples = Generator.zipWith(Generator.zipWith(rational, rational, Pair::new), rational, Triple::new);
        PropertyChecker.customized().withIterationCount(2000).forAll(triples, t -> {
            Rational a = t.pair().a(), b = t.pair().b(), c = t.c();
            require(a.add(b).equals(b.add(a)));
            require(a.add(b).add(c).equals(a.add(b.add(c))));
            require(a.multiply(b.add(c)).equals(a.multiply(b).add(a.multiply(c))));
            require(a.add(b).subtract(b).equals(a));
            require(a.multiply(Rational.ONE).equals(a));
            require(Rational.parse(a.show()).equals(a));
            require(a.numerator().gcd(a.denominator()).equals(BigInteger.ONE));
            if (b.signum() != 0) require(a.divide(b).multiply(b).equals(a));
            return true;
        });
        PropertyChecker.customized().withIterationCount(2000).forAll(
            Generator.stringsOf(Generator.charsInRange((char)0, (char)65535)), s -> {
                require(TextCodec.read(TextCodec.show(s)).equals(s));
                char[] units = TextCodec.units(s);
                String copy = TextCodec.fromUnits(units);
                if (units.length > 0) units[0] ^= 1;
                require(copy.equals(s));
                require(TextCodec.units(copy).length == s.length());
                return true;
            });
        // Do not cycle back to size 1 after every 100 iterations: the finite
        // three-state alphabet would exhaust jetCheck's distinct small lists.
        PropertyChecker.customized().withIterationCount(2000).withSizeHint(i -> Math.min(100, i)).forAll(
            Generator.listsOf(Generator.integers(0, 2)), states -> {
                List<Validation.Check> checks = new ArrayList<>();
                for (int s : states) checks.add(s == 0 ? new Validation.Satisfied() : s == 1 ? new Validation.Violated(DETAIL) : new Validation.Undecided(DETAIL));
                Validation.Outcome outcome = Validation.collect(checks);
                require(outcome.state() == (states.contains(1) ? Validation.State.INVALID : states.contains(2) ? Validation.State.INDETERMINATE : Validation.State.VALID));
                require(outcome.incomplete() == states.contains(2));
                require(outcome.diagnostics().size() == states.stream().filter(s -> s != 0).count());
                checks.clear();
                require(outcome.diagnostics().size() == states.stream().filter(s -> s != 0).count());
                try { outcome.orThrow(); require(outcome.state() == Validation.State.VALID); }
                catch (ValidationException e) { require(e.outcome().equals(outcome)); require(outcome.state() != Validation.State.VALID); }
                return true;
            });
        PropertyChecker.customized().withIterationCount(2000).forAll(
            Generator.zipWith(Generator.integers(1, 10000), Generator.listsOf(Generator.integers(0, 1000)), Trace::new), trace -> {
                Budget budget = new Budget(new Budget.Limits(trace.limit(), trace.limit()), Budget.Limits.defaults());
                Budget.Meter parent = budget.beginClause(0), child = parent.nested(0);
                int used = 0; boolean failed = false;
                for (int cost : trace.costs()) {
                    boolean permitted = !failed && cost <= trace.limit() - used;
                    try { child.step(cost); require(permitted); used += cost; }
                    catch (Budget.Exceeded e) { require(!permitted); failed = true; }
                    require(budget.used().equals(BigInteger.valueOf(used)));
                    require(parent.used().equals(budget.used()));
                    require(child.used().equals(parent.used()));
                }
                return true;
            });
        shrinkAndReplay();
        System.out.println("jetCheck: four 2000-iteration law suites and shrink/replay regression passed");
    }
    // Only this test of the test infrastructure uses a fixed replay seed. The
    // actual runtime properties above explore fresh seeds on every invocation.
    @SuppressWarnings("deprecation") // jetCheck deliberately marks its supported debug/replay API deprecated.
    static void shrinkAndReplay() {
        Generator<Integer> generator = Generator.integers();
        PropertyFalsified first = null;
        try { PropertyChecker.customized().silent().recheckingIteration(123456789L, 100).forAll(generator, n -> false); }
        catch (PropertyFalsified e) { first = e; }
        require(first != null);
        require(first.getFailure().getShrinkingStageCount() > 0);
        require(first.getBreakingValue().equals(0));
        String replay = first.getFailure().getMinimalCounterexample().getSerializedData();
        PropertyFalsified repeated = null;
        try { PropertyChecker.customized().silent().rechecking(replay).forAll(generator, n -> false); }
        catch (PropertyFalsified e) { repeated = e; }
        require(repeated != null);
        require(repeated.getBreakingValue().equals(first.getBreakingValue()));
        require(repeated.getFailure().getMinimalCounterexample().getSerializedData().equals(replay));
    }
}
`
