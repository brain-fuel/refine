package dev.goforge.refine.maven;

import java.io.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.TimeUnit;
import javax.xml.parsers.DocumentBuilderFactory;

/** Runs one source mutation at a time against independently compiled, isolated application classes. */
final class MutationRunner {
  final Path ROOT, RUN, WORK, catalog;
  final int expectedSuites;
  final String maven, propertyMain;
  final long timeoutSeconds;
  static final String SEP = File.pathSeparator;
  static final String JAVA = Path.of(System.getProperty("java.home"), "bin", "java").toString();
  static final String JAVAC = Path.of(System.getProperty("java.home"), "bin", "javac").toString();
  final List<Object> entries = new ArrayList<>(), augmented = new ArrayList<>();
  final Map<String,Integer> counts = new TreeMap<>();

  MutationRunner(Path root, Path catalog, int expectedSuites, String maven, String propertyMain, long timeoutSeconds) {
    if (expectedSuites < 1 || timeoutSeconds < 1) throw new IllegalArgumentException("Positive suite count and timeout required");
    this.ROOT = root.toAbsolutePath().normalize();
    this.catalog = catalog.toAbsolutePath().normalize();
    this.expectedSuites = expectedSuites;
    this.maven = maven;
    this.propertyMain = propertyMain;
    this.timeoutSeconds = timeoutSeconds;
    RUN = ROOT.resolve(".mut/runs/" + Instant.now().toString().replace(':', '-') + "-" + UUID.randomUUID());
    WORK = RUN.resolve("work");
  }

  int run(Path cwd, Path log, String... command) throws Exception {
    Files.createDirectories(log.getParent());
    var builder = new ProcessBuilder(command).directory(cwd.toFile()).redirectErrorStream(true)
        .redirectOutput(log.toFile());
    builder.environment().put("JAVA_HOME", System.getProperty("java.home"));
    var process = builder.start();
    if (process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) return process.exitValue();
    process.descendants().forEach(ProcessHandle::destroyForcibly);
    process.destroyForcibly(); process.waitFor();
    return 124;
  }
  static void copy(Path from, Path to) throws IOException {
    try (var paths = Files.walk(from)) {
      for (var p : paths.toList()) {
        var dest = to.resolve(from.relativize(p));
        if (Files.isDirectory(p)) Files.createDirectories(dest);
        else { Files.createDirectories(dest.getParent()); Files.copy(p, dest, StandardCopyOption.REPLACE_EXISTING); }
      }
    }
  }
  static void remove(Path path) throws IOException {
    if (!Files.exists(path)) return;
    try (var paths = Files.walk(path)) {
      for (var p : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(p);
    }
  }
  static String json(Object value) {
    return new com.google.gson.GsonBuilder().disableHtmlEscaping().create().toJson(value);
  }
  static void write(Path path, Object value) throws IOException {
    Files.createDirectories(path.getParent()); Files.writeString(path, json(value) + "\n");
  }
  static long suitePasses(Path log) throws IOException {
    var suites = new HashSet<String>();
    var pattern = java.util.regex.Pattern.compile(
        "REFINE_SUITE PASS properties=[1-9][0-9]* cases=[1-9][0-9]* examples=[0-9]+ suite=(\\S+)");
    for (String line : Files.readAllLines(log)) {
      if (!line.startsWith("REFINE_SUITE PASS ")) continue;
      var match = pattern.matcher(line);
      if (!match.matches() || !suites.add(match.group(1))) return -1;
    }
    return suites.size();
  }
  // XML evidence is required: a Maven process failure alone is not a test kill.
  static int[] junitEvidence(Path directory) throws Exception {
    int tests = 0, failed = 0;
    var factory = DocumentBuilderFactory.newInstance();
    factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
    try (var paths = Files.list(directory)) {
      for (var file : paths.filter(p -> p.getFileName().toString().matches("TEST-.*\\.xml")).toList()) {
        var suite = factory.newDocumentBuilder().parse(file.toFile()).getDocumentElement();
        tests += Integer.parseInt(suite.getAttribute("tests"))
            - (suite.hasAttribute("skipped") ? Integer.parseInt(suite.getAttribute("skipped")) : 0);
        failed += Integer.parseInt(suite.getAttribute("failures")) + Integer.parseInt(suite.getAttribute("errors"));
      }
    }
    return new int[]{tests, failed};
  }
  static String propertyOutcome(int exit, Path log, long expectedSuites) throws IOException {
    if (exit == 124) return "timeout";
    if (exit == 0 && suitePasses(log) == expectedSuites) return "passed";
    if (exit != 0 && Files.readString(log).contains("REFINE_PROPERTY FAIL ")) return "killed";
    return "infrastructure_error";
  }
  static String applicationOutcome(int exit, int[] evidence, int expectedTests) {
    if (exit == 124) return "timeout";
    if (exit != 0 && evidence[1] > 0) return "killed";
    if (exit == 0 && evidence[0] == expectedTests && evidence[1] == 0) return "passed";
    return "infrastructure_error";
  }
  void publish(boolean corpusOk) throws Exception {
    write(RUN.resolve("out/report.json"), Map.of("groups", List.of(entries),
        "controls", Map.of("passed", corpusOk ? 1 : 0, "failed", corpusOk ? 0 : 1), "counts", counts));
    write(RUN.resolve("augmented/manifest-augmented.json"), List.of(augmented));
    write(RUN.resolve("out/observations.json"), Map.of("$run", Map.of("corpusOk", corpusOk)));
    write(RUN.resolve("run.json"), Map.of("driver", "refine-source-mutation 1", "expectedSuites", expectedSuites,
        "date", Instant.now().toString(), "toolchain", System.getProperty("java.runtime.version"),
        "scope", "explicit catalog sites; generated properties and application JUnit; no coverage probes"));
    // Only completed, green-control runs become the review ledger's current run.
    if (corpusOk) {
      Path link = ROOT.resolve(".mut/current-next");
      Files.deleteIfExists(link);
      Files.createSymbolicLink(link, ROOT.resolve(".mut").relativize(RUN));
      Files.move(link, ROOT.resolve(".mut/current"), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    }
  }
  boolean execute() throws Exception {
    Files.createDirectories(RUN);
    Path baseline = RUN.resolve("baseline.log");
    System.out.println("Baseline clean verify; logs: " + RUN);
    int baselineExit = run(ROOT, baseline, maven, "-B", "-ntp", "clean", "verify",
        "org.apache.maven.plugins:maven-dependency-plugin:3.10.0:build-classpath", "-Dmdep.outputFile=target/mutation-classpath.txt");
    if (baselineExit != 0 || suitePasses(baseline) != expectedSuites) {
      publish(false); throw new IllegalStateException("Baseline failed or missing generated suite evidence: " + baseline);
    }
    int[] control = junitEvidence(ROOT.resolve("target/surefire-reports"));
    if (control[0] == 0 || control[1] != 0) { publish(false); throw new IllegalStateException("No green JUnit control"); }
    for (String name : List.of("pom.xml", "mvnw", ".mvn", "src", "target"))
      if (Files.exists(ROOT.resolve(name))) copy(ROOT.resolve(name), WORK.resolve(name));
    copy(ROOT.resolve("target/generated-sources"), RUN.resolve("sources/target/generated-sources"));
    copy(ROOT.resolve("src"), RUN.resolve("sources/src"));
    copy(ROOT.resolve("target/generated-test-sources"), RUN.resolve("sources/target/generated-test-sources"));
    for (String name : List.of("pom.xml", "refine.project.json", "schemata", "specs", "tools"))
      if (Files.exists(ROOT.resolve(name))) copy(ROOT.resolve(name), RUN.resolve("sources/" + name));
    var hashes = new TreeMap<String,String>();
    try (var paths = Files.walk(RUN.resolve("sources"))) {
      for (var path : paths.filter(Files::isRegularFile).toList())
        hashes.put(RUN.resolve("sources").relativize(path).toString(), HexFormat.of().formatHex(
            java.security.MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(path))));
    }
    write(RUN.resolve("source-sha256.json"), hashes);
    Files.copy(catalog, RUN.resolve("mutations.tsv"));
    String dependencies = Files.readString(ROOT.resolve("target/mutation-classpath.txt")).strip();
    String cp = WORK.resolve("target/classes") + SEP + WORK.resolve("target/test-classes") + SEP + dependencies;
    var ids = new HashSet<String>();
    for (String row : Files.readAllLines(catalog)) {
      if (row.isBlank() || row.startsWith("#")) continue;
      String[] m = row.split("\t", -1);
      if (m.length != 5 || !m[0].matches("[a-zA-Z0-9_-]+") || !ids.add(m[0])) throw new IllegalArgumentException("Invalid mutation row: " + row);
      String id = m[0], file = m[1], binding = m[2], before = m[3], after = m[4];
      Path logDir = RUN.resolve(id); Files.createDirectories(logDir);
      Path candidate = ROOT.resolve(file).normalize();
      if (!candidate.startsWith(ROOT) || !candidate.toRealPath().startsWith(ROOT) || !file.endsWith(".java")
          || !(file.startsWith("target/generated-sources/") || file.startsWith("src/main/java/")))
        throw new IllegalArgumentException("Mutations must target project production Java: " + file);
      String original = Files.readString(candidate);
      int pos = original.indexOf(before);
      if (pos < 0 || original.indexOf(before, pos + before.length()) >= 0 || before.equals(after))
        throw new IllegalStateException("Mutation must match exactly one changed site: " + id);
      String changed = original.substring(0, pos) + after + original.substring(pos + before.length());
      Path source = logDir.resolve(Path.of(file).getFileName()); Files.writeString(source, changed);
      remove(WORK.resolve("target/classes")); copy(ROOT.resolve("target/classes"), WORK.resolve("target/classes"));
      remove(WORK.resolve("target/surefire-reports"));
      int compiled = run(WORK, logDir.resolve("compile.log"), JAVAC, "--release", "25", "-cp", cp,
          "-d", WORK.resolve("target/classes").toString(), source.toString());
      String outcome, property = "not_run", application = "not_run";
      if (compiled != 0) outcome = compiled == 124 ? "timeout" : "invalid";
      else {
        Path propertyLog = logDir.resolve("properties.log");
        int propertyExit = run(WORK, propertyLog, JAVA, "-cp", cp, propertyMain);
        property = propertyOutcome(propertyExit, propertyLog, expectedSuites);
        int appExit = run(WORK, logDir.resolve("junit.log"), maven, "-B", "-ntp", "surefire:test");
        int[] evidence = Files.isDirectory(WORK.resolve("target/surefire-reports"))
            ? junitEvidence(WORK.resolve("target/surefire-reports")) : new int[]{0,0};
        application = applicationOutcome(appExit, evidence, control[0]);
        if (Files.isDirectory(WORK.resolve("target/surefire-reports"))) copy(WORK.resolve("target/surefire-reports"), logDir.resolve("surefire-reports"));
        outcome = property.equals("infrastructure_error") || application.equals("infrastructure_error") ? "infrastructure_error"
            : property.equals("timeout") || application.equals("timeout") ? "timeout"
            : property.equals("killed") || application.equals("killed") ? "killed" : "survived";
      }
      int line = (int) original.substring(0, pos).chars().filter(c -> c == '\n').count() + 1;
      String sourceLine = original.lines().toList().get(line - 1);
      var mutation = new LinkedHashMap<String,Object>();
      mutation.put("id", List.of(id)); mutation.put("module", file); mutation.put("operator", id);
      mutation.put("source_file", file); mutation.put("line", line); mutation.put("end_line", line);
      mutation.put("col_start", pos - original.lastIndexOf('\n', pos));
      mutation.put("col_end", pos - original.lastIndexOf('\n', pos) + before.length());
      mutation.put("original", before); mutation.put("replacement", after);
      mutation.put("source_lines", List.of(sourceLine)); mutation.put("mutated_lines", List.of(sourceLine.replace(before, after)));
      // The existing adapter calls non-runnable mutants skipped; preserve precise status alongside it.
      String ledgerOutcome = outcome.equals("invalid") || outcome.equals("infrastructure_error") ? "skipped" : outcome;
      entries.add(Map.of("mutation", mutation, "outcome", ledgerOutcome, "status", outcome,
          "generated_properties", property, "application_junit", application));
      augmented.add(Map.of("id", List.of(id), "binding", binding, "covering_tests", Map.of(),
          "context_before", original.lines().limit(line - 1).skip(Math.max(0, line - 6)).toList(),
          "context_after", original.lines().skip(line).limit(5).toList()));
      counts.merge(outcome, 1, Integer::sum);
      System.out.println(id + ": " + outcome + " (properties=" + property + ", junit=" + application + ")");
    }
    if (entries.isEmpty()) throw new IllegalStateException("No mutations selected");
    publish(true); remove(WORK);
    System.out.println(json(counts) + " — report: .mut/current/out/report.json; detailed logs: " + RUN);
    // Survivors require human review; neither skipped mutants nor timeouts inflate the score.
    return counts.keySet().stream().allMatch("killed"::equals);
  }
}
