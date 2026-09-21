package dev.goforge.refine.engine;

import com.dylibso.chicory.runtime.*;
import com.dylibso.chicory.wasi.*;
import com.dylibso.chicory.wasm.WasmModule;
import java.io.*;
import java.nio.file.Path;
import java.util.*;

/** Executes the published Refine compiler entirely within the JVM. */
public final class RefineEngine {
    private RefineEngine() {}
    private static final class ModuleHolder { static final WasmModule MODULE = RefineModule.load(); }

    private static OutputStream nonClosing(OutputStream stream) {
        return new FilterOutputStream(stream) {
            @Override public void write(byte[] bytes, int offset, int length) throws IOException { out.write(bytes, offset, length); }
            @Override public void close() throws IOException { flush(); }
        };
    }

    /**
     * Runs Refine with only {@code root} mounted, as {@code /workspace}.
     * Relative input/output paths resolve there. Streams remain owned by the caller.
     * @return the CLI status; nonzero indicates validation or generation failure
     */
    public static int run(Path root, List<String> arguments, InputStream stdin, OutputStream stdout, OutputStream stderr) throws IOException {
        Path directory = root.toRealPath();
        var argv = new ArrayList<String>();
        argv.add("refine"); argv.addAll(arguments);
        var options = WasiOptions.builder().withDirectory("/workspace", directory)
            .withEnvironment("PWD", "/workspace").withArguments(argv)
            .withStdin(new FilterInputStream(stdin) { @Override public void close() {} })
            .withStdout(nonClosing(stdout)).withStderr(nonClosing(stderr)).build();
        try (var wasi = WasiPreview1.builder().withOptions(options).build()) {
            var functions = WasiFilesystem.adapt(wasi.toHostFunctions(), directory);
            Instance.builder(ModuleHolder.MODULE).withMachineFactory(RefineModule::create)
                .withImportValues(ImportValues.builder().addFunction(functions).build()).build();
            return 0;
        } catch (WasiExitException exit) {
            return exit.exitCode();
        }
    }
}
