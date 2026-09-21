package dev.goforge.refine.maven;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;

/** Prepares formatted bytes without touching any owned generated output. */
final class JavaFormatting implements AutoCloseable {
  private final Path root;
  private final Path directory;

  private JavaFormatting(Path root) throws IOException {
    this.root = root.toRealPath();
    directory = Files.createTempDirectory(this.root, ".refine-format-");
  }

  static JavaFormatting prepare(Path root, String sourcePlan, Path formatter)
      throws IOException, InterruptedException {
    var prepared = new JavaFormatting(root);
    try {
      JsonObject plan = JsonParser.parseString(sourcePlan).getAsJsonObject();
      var names = new ArrayList<String>();
      int index = 0;
      // Numbered staging paths avoid trusting output paths or shell quoting.
      for (var entry : plan.entrySet()) {
        String name = "Source" + index++ + ".java";
        Files.writeString(
            prepared.directory.resolve(name),
            entry.getValue().getAsJsonObject().get("source").getAsString());
        names.add(name);
      }
      if (!names.isEmpty()) {
        Path args = prepared.directory.resolve("arguments.txt");
        Files.write(args, names);
        Path log = prepared.directory.resolve("formatter.log");
        String binary = System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java";
        Process process =
            new ProcessBuilder(
                    Path.of(System.getProperty("java.home"), "bin", binary).toString(),
                    "-Dfile.encoding=UTF-8",
                    "-jar",
                    formatter.toAbsolutePath().toString(),
                    "--replace",
                    "@arguments.txt")
                .directory(prepared.directory.toFile())
                .redirectErrorStream(true)
                .redirectOutput(log.toFile())
                .start();
        int status;
        try {
          status = process.waitFor();
        } catch (InterruptedException e) {
          process.destroyForcibly();
          throw e;
        }
        if (status != 0)
          throw new IOException(
              "Google Java formatting failed (" + status + "): " + Files.readString(log));
      }
      index = 0;
      for (var entry : plan.entrySet()) {
        entry
            .getValue()
            .getAsJsonObject()
            .addProperty(
                "formatted", Files.readString(prepared.directory.resolve(names.get(index++))));
      }
      Files.writeString(prepared.directory.resolve("plan.json"), new Gson().toJson(plan));
      return prepared;
    } catch (IOException | InterruptedException | RuntimeException e) {
      try {
        prepared.close();
      } catch (IOException cleanup) {
        e.addSuppressed(cleanup);
      }
      throw e;
    }
  }

  String relativePlan() {
    return root.relativize(directory.resolve("plan.json")).toString().replace('\\', '/');
  }

  @Override
  public void close() throws IOException {
    try (var paths = Files.walk(directory)) {
      for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
    }
  }
}
