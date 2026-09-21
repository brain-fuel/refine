package dev.goforge.refine.maven;

import java.io.File;
import java.nio.file.Path;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugin.MojoFailureException;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;

/** Mutates production Java in isolated builds and exports test evidence for Rice's Tax. */
@Mojo(name = "mutate", threadSafe = false)
public final class MutateMojo extends AbstractMojo {
    @Parameter(defaultValue = "${project.basedir}", readonly = true, required = true)
    private File projectDirectory;
    @Parameter(property = "refine.mutationCatalog", defaultValue = "refine.mutations.tsv")
    private String catalog;
    @Parameter(property = "refine.mutationSuites", defaultValue = "1")
    private int suites;
    @Parameter(property = "refine.mutationMain", defaultValue = "refine.generated.RefineGeneratedTests")
    private String mainClass;
    @Parameter(property = "refine.mutationTimeout", defaultValue = "180")
    private long timeoutSeconds;
    @Parameter(defaultValue = "${maven.home}", readonly = true)
    private File mavenHome;

    @Override public void execute() throws MojoExecutionException, MojoFailureException {
        try {
            Path root = projectDirectory.toPath().toRealPath();
            String executable = mavenHome.toPath().resolve("bin/mvn").toString();
            var runner = new MutationRunner(root, root.resolve(catalog), suites, executable, mainClass, timeoutSeconds);
            if (!runner.execute()) throw new MojoFailureException(
                "Mutation verification has survivors or inconclusive results. Review " + runner.RUN.resolve("out/report.json"));
        } catch (MojoFailureException e) { throw e; }
        catch (InterruptedException e) {
            Thread.currentThread().interrupt(); throw new MojoExecutionException("Mutation run interrupted", e);
        } catch (Exception e) { throw new MojoExecutionException("Cannot complete mutation verification", e); }
    }
}
