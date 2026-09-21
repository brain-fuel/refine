package dev.goforge.refine.maven;

import dev.goforge.refine.engine.RefineEngine;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

/** Generates and validates Refine outputs during Maven's generate-sources phase. */
@Mojo(name = "generate", defaultPhase = LifecyclePhase.GENERATE_SOURCES, threadSafe = true)
public final class GenerateMojo extends AbstractMojo {
  @Parameter(defaultValue = "${project.basedir}", readonly = true, required = true)
  private File projectDirectory;

  @Parameter(property = "refine.executable")
  private String executable;

  @Parameter(property = "refine.javaFormat", defaultValue = "google")
  private String javaFormat;

  @Parameter(defaultValue = "${plugin.artifacts}", readonly = true, required = true)
  private List<org.apache.maven.artifact.Artifact> pluginArtifacts;

  @Parameter(property = "refine.root")
  private File root;

  @Parameter(property = "refine.skip", defaultValue = "false")
  private boolean skip;

  @Parameter(defaultValue = "${project}", readonly = true, required = true)
  private MavenProject project;

  @Override
  public void execute() throws MojoExecutionException {
    if (skip) {
      getLog().info("Refine generation is skipped");
      return;
    }
    File working = root == null ? projectDirectory : root;
    boolean external = executable != null && !executable.isBlank();
    List<String> command =
        new ArrayList<>(
            List.of(
                "project",
                "generate",
                "--root",
                external ? working.getAbsolutePath() : "/workspace",
                "--maven-group-id",
                project.getGroupId()));
    command.add("--maven-artifact-id");
    command.add(getProjectArtifactId());
    command.add("--maven-version");
    command.add(getProjectVersion());
    getLog().info("Running Refine " + (external ? "external executable" : "JVM engine"));
    try {
      String style = javaFormat == null ? "google" : javaFormat;
      if (!style.equals("google") && !style.equals("none"))
        throw new MojoExecutionException(
            "Unknown refine.javaFormat '" + style + "'; supported values: google, none");
      if (style.equals("none")) {
        run(working, command, external);
      } else {
        var planCommand = new ArrayList<>(command);
        planCommand.add("--java-format-plan");
        String plan = run(working, planCommand, external);
        File formatter =
            pluginArtifacts.stream()
                .filter(
                    a ->
                        a.getGroupId().equals("com.google.googlejavaformat")
                            && a.getArtifactId().equals("google-java-format")
                            && "all-deps".equals(a.getClassifier()))
                .map(org.apache.maven.artifact.Artifact::getFile)
                .findFirst()
                .orElseThrow(
                    () ->
                        new MojoExecutionException(
                            "Google Java formatter artifact was not resolved"));
        try (var prepared = JavaFormatting.prepare(working.toPath(), plan, formatter.toPath())) {
          command.add("--java-format-input");
          command.add(prepared.relativePlan());
          run(working, command, external);
        }
        getLog().info("Generated Java formatted with Google Java Format 1.36.0");
      }
      project.addCompileSourceRoot(
          new File(working, "target/generated-sources/refine").getAbsolutePath());
      project.addTestCompileSourceRoot(
          new File(working, "target/generated-test-sources/refine").getAbsolutePath());
      org.apache.maven.model.Resource resources = new org.apache.maven.model.Resource();
      resources.setDirectory(
          new File(working, "target/generated-resources/refine").getAbsolutePath());
      project.addResource(resources);
    } catch (IOException error) {
      throw new MojoExecutionException("cannot execute Refine generation", error);
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new MojoExecutionException("Refine generation interrupted", error);
    }
  }

  private String run(File working, List<String> arguments, boolean external)
      throws IOException, InterruptedException, MojoExecutionException {
    var output = new ByteArrayOutputStream();
    var errors = new ByteArrayOutputStream();
    int status;
    if (external) {
      var command = new ArrayList<>(arguments);
      command.addFirst(executable);
      // File redirection avoids pipe deadlocks for large formatting plans.
      var stdout = java.nio.file.Files.createTempFile("refine-stdout-", ".log");
      var stderr = java.nio.file.Files.createTempFile("refine-stderr-", ".log");
      try {
        Process process =
            new ProcessBuilder(command)
                .directory(working)
                .redirectOutput(stdout.toFile())
                .redirectError(stderr.toFile())
                .start();
        try {
          status = process.waitFor();
        } catch (InterruptedException e) {
          process.destroyForcibly();
          throw e;
        }
        output.write(java.nio.file.Files.readAllBytes(stdout));
        errors.write(java.nio.file.Files.readAllBytes(stderr));
      } finally {
        java.nio.file.Files.deleteIfExists(stdout);
        java.nio.file.Files.deleteIfExists(stderr);
      }
    } else {
      status =
          RefineEngine.run(
              working.toPath(), arguments, java.io.InputStream.nullInputStream(), output, errors);
    }
    if (status != 0)
      throw new MojoExecutionException(
          "Refine exited with status " + status + ": " + errors.toString(StandardCharsets.UTF_8));
    if (errors.size() > 0) getLog().warn(errors.toString(StandardCharsets.UTF_8).strip());
    String result = output.toString(StandardCharsets.UTF_8);
    if (!arguments.contains("--java-format-plan") && !result.isBlank())
      getLog().info(result.strip());
    return result;
  }

  private String getProjectArtifactId() {
    return project.getArtifactId();
  }

  private String getProjectVersion() {
    return project.getVersion();
  }
}
