package dev.goforge.refine.maven;

import static org.junit.jupiter.api.Assertions.*;

import java.nio.file.*;
import java.util.*;
import org.apache.maven.artifact.DefaultArtifact;
import org.apache.maven.artifact.handler.DefaultArtifactHandler;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.project.MavenProject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class GenerateMojoTest {
  @TempDir Path root;

  private Path formatter() throws Exception {
    return Path.of(
        com.google.googlejavaformat.java.Main.class
            .getProtectionDomain()
            .getCodeSource()
            .getLocation()
            .toURI());
  }

  private GenerateMojo mojo(String style) throws Exception {
    Files.createDirectories(root.resolve("schemata/thing"));
    Files.writeString(root.resolve("schemata/thing/SNAPSHOT.refine"), "type Thing = String\n");
    Files.writeString(
        root.resolve("refine.project.json"),
        "{\"package\":\"example\",\"families\":{\"thing\":{\"formats\":[\"json-schema\"]}}}");
    var project = new MavenProject();
    project.setGroupId("example");
    project.setArtifactId("example");
    project.setVersion("1.0-SNAPSHOT");
    var artifact =
        new DefaultArtifact(
            "com.google.googlejavaformat",
            "google-java-format",
            "1.36.0",
            "runtime",
            "jar",
            "all-deps",
            new DefaultArtifactHandler("jar"));
    artifact.setFile(formatter().toFile());
    var mojo = new GenerateMojo();
    for (var entry :
        Map.<String, Object>of(
                "projectDirectory",
                root.toFile(),
                "project",
                project,
                "javaFormat",
                style,
                "pluginArtifacts",
                List.of(artifact))
            .entrySet()) {
      var field = GenerateMojo.class.getDeclaredField(entry.getKey());
      field.setAccessible(true);
      field.set(mojo, entry.getValue());
    }
    return mojo;
  }

  private Map<String, String> outputs() throws Exception {
    var result = new TreeMap<String, String>();
    try (var files = Files.walk(root.resolve("target"))) {
      for (Path file : files.filter(Files::isRegularFile).toList())
        result.put(root.relativize(file).toString(), Files.readString(file));
    }
    result.put(".refine-generated.json", Files.readString(root.resolve(".refine-generated.json")));
    return result;
  }

  @Test
  void formatsAllJavaAndPreservesOwnershipAcrossRunsAndStyleChanges() throws Exception {
    var mojo = mojo("google");
    mojo.execute();
    var first = outputs();
    var javaFiles = first.entrySet().stream().filter(e -> e.getKey().endsWith(".java")).toList();
    assertTrue(javaFiles.stream().anyMatch(e -> e.getKey().contains("generated-test-sources")));
    // Ask the real pinned formatter to verify every production and test source.
    var args = root.resolve("check.args");
    Files.write(args, javaFiles.stream().map(Map.Entry::getKey).toList());
    var process =
        new ProcessBuilder(
                Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-jar",
                formatter().toString(),
                "--dry-run",
                "--set-exit-if-changed",
                "@check.args")
            .directory(root.toFile())
            .inheritIO()
            .start();
    assertEquals(0, process.waitFor());
    mojo.execute();
    assertEquals(first, outputs());
    mojo("none").execute();
    assertNotEquals(first, outputs());
    mojo.execute();
    assertEquals(first, outputs());
    Path edited = root.resolve(javaFiles.getFirst().getKey());
    Files.writeString(edited, Files.readString(edited) + "// manual edit\n");
    var beforeFailure = outputs();
    assertThrows(MojoExecutionException.class, mojo::execute);
    assertEquals(beforeFailure, outputs());
    try (var paths = Files.list(root)) {
      assertFalse(paths.anyMatch(p -> p.getFileName().toString().startsWith(".refine-format-")));
    }
  }

  @Test
  void invalidStyleFailsBeforeWriting() throws Exception {
    assertThrows(MojoExecutionException.class, () -> mojo("typo").execute());
    assertFalse(Files.exists(root.resolve("target")));
  }

  @Test
  void formatterFailureLeavesNoStagingOrOutputs() throws Exception {
    String plan = "{\"Broken.java\":{\"source\":\"this is not Java!\",\"formatted\":\"\"}}";
    assertThrows(java.io.IOException.class, () -> JavaFormatting.prepare(root, plan, formatter()));
    try (var paths = Files.list(root)) {
      assertEquals(0, paths.count());
    }
  }
}
