package dev.goforge.refine.maven;

import dev.goforge.refine.engine.RefineEngine;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.*;

/** Imports a pinned native schema into a Refine bundle without an external CLI. */
@Mojo(name = "ingest", threadSafe = true)
public final class IngestMojo extends AbstractMojo {
    @Parameter(defaultValue = "${project.basedir}", readonly = true, required = true)
    private File projectDirectory;
    @Parameter(property = "refine.input", required = true)
    private String input;
    @Parameter(property = "refine.output", required = true)
    private String output;
    @Parameter(property = "refine.format", defaultValue = "openapi")
    private String format;
    @Parameter(property = "refine.type", required = true)
    private String type;
    @Parameter(property = "refine.pointer")
    private String pointer;
    @Parameter(property = "refine.resource")
    private String resource;
    @Override public void execute() throws MojoExecutionException {
        Path temporary = null;
        try {
            Path root = projectDirectory.toPath().toRealPath();
            Path source = root.resolve(input).normalize();
            Path destination = root.resolve(output).normalize();
            if (!source.toRealPath().startsWith(root) || !destination.startsWith(root) || destination.equals(root))
                throw new IOException("Schema input/output must remain inside the project");
            List<String> args = new ArrayList<>(List.of("native", "ingest", "--type", type));
            if (pointer != null && !pointer.isBlank()) args.addAll(List.of("--pointer", pointer));
            if (resource != null && !resource.isBlank()) args.addAll(List.of("--resource", resource));
            args.add(format); args.add("/workspace/" + root.relativize(source).toString().replace(File.separatorChar, '/'));
            var out = new ByteArrayOutputStream(); var err = new ByteArrayOutputStream();
            int status = RefineEngine.run(root, args, InputStream.nullInputStream(), out, err);
            if (status != 0) throw new MojoExecutionException("Refine import failed: " + err.toString(StandardCharsets.UTF_8));
            Files.createDirectories(destination.getParent());
            if (!destination.getParent().toRealPath().startsWith(root) || Files.isSymbolicLink(destination))
                throw new IOException("Schema output traverses a symbolic link");
            temporary = Files.createTempFile(destination.getParent(), ".refine-import-", ".json");
            Files.write(temporary, out.toByteArray());
            Files.move(temporary, destination, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            temporary = null;
            getLog().info("Imported " + type + " into " + output + " using the JVM engine");
        } catch (IOException e) { throw new MojoExecutionException("Cannot import Refine schema", e); }
        finally { if (temporary != null) try { Files.deleteIfExists(temporary); } catch (IOException ignored) {} }
    }
}
