package dev.goforge.refine.maven;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.project.MavenProject;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;

/** Generates and validates Refine outputs during Maven's generate-sources phase. */
@Mojo(name = "generate", defaultPhase = LifecyclePhase.GENERATE_SOURCES, threadSafe = true)
public final class GenerateMojo extends AbstractMojo {
    @Parameter(defaultValue = "${project.basedir}", readonly = true, required = true)
    private File projectDirectory;
    @Parameter(property = "refine.executable", defaultValue = "refine")
    private String executable;
    @Parameter(property = "refine.root")
    private File root;
    @Parameter(property = "refine.skip", defaultValue = "false")
    private boolean skip;
    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Override public void execute() throws MojoExecutionException {
        if (skip) { getLog().info("Refine generation is skipped"); return; }
        File working = root == null ? projectDirectory : root;
        List<String> command = new ArrayList<>(List.of(executable, "project", "generate", "--root", working.getAbsolutePath(), "--maven-group-id", project.getGroupId()));
        command.add("--maven-artifact-id"); command.add(getProjectArtifactId());
        command.add("--maven-version"); command.add(getProjectVersion());
        getLog().info("Running Refine: " + String.join(" ", command));
        try {
            Process process = new ProcessBuilder(command).directory(working).inheritIO().start();
            int status = process.waitFor();
            if (status != 0) throw new MojoExecutionException("Refine exited with status " + status);
            project.addCompileSourceRoot(new File(working, "target/generated-sources/refine").getAbsolutePath());
            project.addTestCompileSourceRoot(new File(working, "target/generated-test-sources/refine").getAbsolutePath());
            org.apache.maven.model.Resource resources = new org.apache.maven.model.Resource();
            resources.setDirectory(new File(working, "target/generated-resources/refine").getAbsolutePath());
            project.addResource(resources);
        } catch (IOException error) { throw new MojoExecutionException("cannot start Refine executable " + executable, error); }
        catch (InterruptedException error) { Thread.currentThread().interrupt(); throw new MojoExecutionException("Refine generation interrupted", error); }
    }
    private String getProjectArtifactId() { return project.getArtifactId(); }
    private String getProjectVersion() { return project.getVersion(); }
}
