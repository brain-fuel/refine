package dev.goforge.refine.engine;

import com.dylibso.chicory.runtime.HostFunction;
import java.io.IOException;
import java.nio.file.*;

/** Compatibility for Chicory 1.7.5 passing COPY_ATTRIBUTES to Files.move. */
final class WasiFilesystem {
    private WasiFilesystem() {}
    static HostFunction[] adapt(HostFunction[] functions, Path root) {
        for (int i = 0; i < functions.length; i++) {
            var original = functions[i];
            if (!original.name().equals("path_rename")) continue;
            functions[i] = new HostFunction(original.module(), original.name(), original.functionType(), (instance, args) -> {
                var result = original.handle().apply(instance, args);
                if (result[0] != 58 /* WASI ENOTSUP */) return result;
                // There is exactly one preopen: fd 3 = /workspace. Other descriptors
                // remain under Chicory's control and never gain fallback access.
                if (args[0] != 3 || args[3] != 3) return result;
                String from = instance.memory().readString((int) args[1], (int) args[2]);
                String to = instance.memory().readString((int) args[4], (int) args[5]);
                return new long[] {rename(root, from, to)};
            });
        }
        return functions;
    }
    static int rename(Path root, String from, String to) {
        try {
            Path source = confined(root, from), destination = confined(root, to);
            // Preserve atomicity. Never fall back to copy/delete.
            Files.move(source, destination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            return 0 /* WASI ESUCCESS */;
        } catch (AccessDeniedException | SecurityException e) { return 2 /* WASI EACCES */; }
        catch (NoSuchFileException e) { return 44 /* WASI ENOENT */; }
        catch (DirectoryNotEmptyException e) { return 55 /* WASI ENOTEMPTY */; }
        catch (AtomicMoveNotSupportedException | UnsupportedOperationException e) { return 58 /* WASI ENOTSUP */; }
        catch (IOException e) { return 29 /* WASI EIO */; }
    }
    private static Path confined(Path root, String raw) throws IOException {
        Path relative = Path.of(raw);
        Path result = root.resolve(relative).normalize();
        if (relative.isAbsolute() || !result.startsWith(root) || result.equals(root)
            || !result.getParent().toRealPath().startsWith(root) || Files.isSymbolicLink(result)) {
            throw new AccessDeniedException(raw);
        }
        return result;
    }
}
