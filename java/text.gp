package java

const textJava=`
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Objects;

/** Canonical language text, separate from JSON/Avro wire codecs. */
public final class TextCodec {
    private TextCodec() {}
    public static String fromUnits(char[] units) { return new String(units); }
    public static char[] units(String text) { return text.toCharArray(); }
    public static String fromUtf8(byte[] bytes) {
        try {
            return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException failure) { throw new IllegalArgumentException("invalid UTF-8 text"); }
    }
    private static int scalarWidth(String text, int position, int end) {
        char unit = text.charAt(position);
        if (Character.isHighSurrogate(unit)) {
            if (position + 1 < end && Character.isLowSurrogate(text.charAt(position + 1))) return 2;
            throw new IllegalArgumentException("unpaired UTF-16 surrogate");
        }
        if (Character.isLowSurrogate(unit)) throw new IllegalArgumentException("unpaired UTF-16 surrogate");
        return 1;
    }
    public static byte[] utf8(String text) {
        for (int i = 0; i < text.length();) i += scalarWidth(text, i, text.length());
        return text.getBytes(StandardCharsets.UTF_8);
    }
    public static String show(String text) {
        Objects.requireNonNull(text);
        StringBuilder result = new StringBuilder();
        result.append('"');
        for (int i = 0; i < text.length(); i++) {
            char unit = text.charAt(i);
            if (unit == '"' || unit == '\\') result.append('\\').append(unit);
            else if (unit >= 0x20 && unit <= 0x7e) result.append(unit);
            else {
                result.append('\\').append('u');
                String hex = Integer.toHexString(unit);
                result.append("0".repeat(4 - hex.length())).append(hex);
            }
        }
        return result.append('"').toString();
    }
    public static String read(String input) {
        Objects.requireNonNull(input);
        if (input.length() < 2 || input.charAt(0) != '"' || input.charAt(input.length() - 1) != '"')
            throw new IllegalArgumentException("expected quoted text");
        int end = input.length() - 1;
        StringBuilder result = new StringBuilder();
        for (int i = 1; i < end;) {
            char unit = input.charAt(i++);
            if (unit == '\\') {
                if (i >= end) throw new IllegalArgumentException("unfinished text escape");
                char escape = input.charAt(i++);
                switch (escape) {
                    case '"', '\\', '/' -> result.append(escape);
                    case 'b' -> result.append('\b');
                    case 'f' -> result.append('\f');
                    case 'n' -> result.append('\n');
                    case 'r' -> result.append('\r');
                    case 't' -> result.append('\t');
                    case 'u' -> {
                        if (i + 4 > end) throw new IllegalArgumentException("unfinished Unicode escape");
                        int value = 0;
                        for (int j = 0; j < 4; j++) {
                            char digit = input.charAt(i++);
                            int n = digit >= '0' && digit <= '9' ? digit - '0'
                                : digit >= 'a' && digit <= 'f' ? digit - 'a' + 10
                                : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10 : -1;
                            if (n < 0) throw new IllegalArgumentException("invalid Unicode escape");
                            value = value * 16 + n;
                        }
                        result.append((char) value);
                    }
                    default -> throw new IllegalArgumentException("invalid text escape");
                }
            } else {
                if (unit < 0x20 || unit == '"') throw new IllegalArgumentException("unescaped text control or quote");
                int width = scalarWidth(input, i - 1, end);
                result.append(unit);
                if (width == 2) result.append(input.charAt(i++));
            }
        }
        return result.toString();
    }
}
`
