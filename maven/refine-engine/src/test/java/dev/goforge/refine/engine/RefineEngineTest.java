package dev.goforge.refine.engine;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import static org.junit.jupiter.api.Assertions.*;

class RefineEngineTest {
    @TempDir Path root;
    private record Result(int status, String out, String err) {}
    private Result run(String... args) throws Exception {
        var out = new ByteArrayOutputStream(); var err = new ByteArrayOutputStream();
        int status = RefineEngine.run(root, List.of(args), InputStream.nullInputStream(), out, err);
        return new Result(status, out.toString(StandardCharsets.UTF_8), err.toString(StandardCharsets.UTF_8));
    }
    @Test void generatesChecksAndRejectsModifiedOwnedFiles() throws Exception {
        Files.writeString(root.resolve("pom.xml"), "<project/>");
        Files.writeString(root.resolve("refine.project.json"), "{\"package\":\"test.contracts\",\"families\":{\"id\":{\"formats\":[\"json-schema\"]}}}");
        Files.createDirectories(root.resolve("schemata/id"));
        Files.writeString(root.resolve("schemata/id/v1.0.0.refine"), "type ID = Int where it >= 0\n");
        assertEquals(0, run("project", "generate", "--root", "/workspace").status());
        Path generated = root.resolve("target/generated-sources/refine/test/contracts/id/v1_0_0/ID.java");
        byte[] original = Files.readAllBytes(generated);
        assertEquals(0, run("project", "generate", "--root", "/workspace", "--check").status());
        assertEquals(0, run("project", "generate", "--root", "/workspace").status());
        assertArrayEquals(original, Files.readAllBytes(generated));
        Files.writeString(generated, "// user-owned modification\n");
        assertNotEquals(0, run("project", "generate", "--root", "/workspace").status());
        assertEquals("// user-owned modification\n", Files.readString(generated));
    }
    @Test void returnsDiagnosticsWithoutExitingJvm() throws Exception {
        Files.writeString(root.resolve("bad.refine"), "type Broken = MissingType\n");
        var result = run("typecheck", "bad.refine");
        assertNotEquals(0, result.status());
        assertTrue((result.out() + result.err()).contains("MissingType"));
        assertEquals(0, run("help").status());
    }
    @Test void renameIsAtomicAndConfined() throws Exception {
        Path canonical = root.toRealPath();
        Files.writeString(root.resolve("a"), "new"); Files.writeString(root.resolve("b"), "old");
        assertEquals(0 /* WASI ESUCCESS */, WasiFilesystem.rename(canonical, "a", "b"));
        assertEquals("new", Files.readString(root.resolve("b")));
        assertFalse(Files.exists(root.resolve("a")));
        assertEquals(2 /* WASI EACCES */, WasiFilesystem.rename(canonical, "../outside", "b"));
        Files.createSymbolicLink(root.resolve("escape"), root.getParent());
        assertEquals(2 /* WASI EACCES */, WasiFilesystem.rename(canonical, "b", "escape/outside"));
        assertEquals("new", Files.readString(root.resolve("b")));
    }
}
