package java

import "fmt"

// nativeRegexJavaParts keeps every GraalJS reference out of validators whose
// schemas do not contain pattern or patternProperties. Regex-enabled helpers
// use one isolated Context per validation request, a deterministic aggregate
// budget, and a watchdog that may cancel guest execution from another thread.
type nativeRegexJavaParts struct{
    hardLimits string
    nestedTypes string
    fieldsAndConstructors string
    validationOpen string
    validationCheck string
    validationClose string
    compileSignature string
    configFactory string
}

func nativeRegexParts(enabled bool,className string)nativeRegexJavaParts{
    if !enabled{return nativeRegexJavaParts{fieldsAndConstructors:fmt.Sprintf("    private final Limits limits;private final tools.jackson.databind.ObjectMapper instanceMapper;private final com.networknt.schema.Schema schema;\n    public %s(){this(Limits.defaults());}public %s(Limits limits){this.limits=java.util.Objects.requireNonNull(limits);this.instanceMapper=mapper(limits);this.schema=compile();}",className,className),validationOpen:"var result=",compileSignature:"()"}}
    return nativeRegexJavaParts{
        hardLimits:",HARD_MAX_REGEX_PATTERN_UNITS=16384,HARD_MAX_REGEX_INPUT_UNITS=1<<20,HARD_MAX_REGEX_MILLIS=1000;private static final long HARD_MAX_REGEX_EVALUATIONS=10000,HARD_MAX_REGEX_WORK_UNITS=8L<<20",
        nestedTypes:nativeRegexRuntimeJava,
        fieldsAndConstructors:fmt.Sprintf("    private final Limits limits;private final RegexLimits regexLimits;private final tools.jackson.databind.ObjectMapper instanceMapper;private final com.networknt.schema.Schema schema;\n    public %s(){this(Limits.defaults(),RegexLimits.defaults());}public %s(Limits limits){this(limits,RegexLimits.defaults());}public %s(Limits limits,RegexLimits regexLimits){this.limits=java.util.Objects.requireNonNull(limits);this.regexLimits=java.util.Objects.requireNonNull(regexLimits);this.instanceMapper=mapper(limits);this.schema=compile(regexLimits);}",className,className,className),
        validationOpen:"com.networknt.schema.output.OutputFlag result;try(var regexRequest=RegexRequest.open(regexLimits)){result=",
        validationCheck:"regexRequest.checkComplete();",
        validationClose:"}",
        compileSignature:"(RegexLimits regexLimits)",
        configFactory:".regularExpressionFactory(new BoundedRegexFactory())",
    }
}

const nativeRegexRuntimeJava=`
    public record RegexLimits(int maxPatternUnits,int maxInputUnits,long maxEvaluations,long maxWorkUnits,int maxMillis){public RegexLimits{if(maxPatternUnits<=0||maxInputUnits<=0||maxEvaluations<=0||maxWorkUnits<=0||maxMillis<=0)throw new IllegalArgumentException("Native regex limits must be positive.");if(maxPatternUnits>HARD_MAX_REGEX_PATTERN_UNITS||maxInputUnits>HARD_MAX_REGEX_INPUT_UNITS||maxEvaluations>HARD_MAX_REGEX_EVALUATIONS||maxWorkUnits>HARD_MAX_REGEX_WORK_UNITS||maxMillis>HARD_MAX_REGEX_MILLIS)throw new IllegalArgumentException("Native regex limits may only tighten generated hard limits.");}public static RegexLimits defaults(){return new RegexLimits(HARD_MAX_REGEX_PATTERN_UNITS,HARD_MAX_REGEX_INPUT_UNITS,HARD_MAX_REGEX_EVALUATIONS,HARD_MAX_REGEX_WORK_UNITS,HARD_MAX_REGEX_MILLIS);}}
    private static final class BoundedRegexFactory implements com.networknt.schema.regex.RegularExpressionFactory{@Override public com.networknt.schema.regex.RegularExpression getRegularExpression(String pattern){return new BoundedRegularExpression(pattern);}@Override public com.networknt.schema.regex.RegularExpression getRegularExpression(String pattern,com.networknt.schema.SchemaContext context){return new BoundedRegularExpression(pattern);}}
    private static final class BoundedRegularExpression implements com.networknt.schema.regex.RegularExpression{private final String pattern;private BoundedRegularExpression(String pattern){this.pattern=java.util.Objects.requireNonNull(pattern);if(pattern.length()>HARD_MAX_REGEX_PATTERN_UNITS)throw new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex pattern limit exceeded.");}@Override public boolean matches(String input){return RegexRequest.current().matches(pattern,java.util.Objects.requireNonNull(input));}}
    private static final class RegexRequest implements AutoCloseable{
        private static final ThreadLocal<RegexRequest> ACTIVE=new ThreadLocal<>();
        // Engine/linkage initialization failures are fatal deployment errors, not payload outcomes.
        private static final org.graalvm.polyglot.Engine ENGINE=org.graalvm.polyglot.Engine.newBuilder("js").useSystemProperties(false).sandbox(org.graalvm.polyglot.SandboxPolicy.CONSTRAINED).in(java.io.InputStream.nullInputStream()).out(java.io.OutputStream.nullOutputStream()).err(java.io.OutputStream.nullOutputStream()).option("engine.WarnInterpreterOnly","false").build();
        private static final org.graalvm.polyglot.Source MATCHER=org.graalvm.polyglot.Source.newBuilder("js","(function(pattern){return function(input){return new RegExp(pattern,'u').test(input);};})","refine-native-regex.js").cached(true).buildLiteral();
        private final RegexLimits limits;private final long deadline;private final java.util.concurrent.atomic.AtomicBoolean timedOut=new java.util.concurrent.atomic.AtomicBoolean();private final java.util.Map<String,org.graalvm.polyglot.Value> matchers=new java.util.HashMap<>();private long evaluations,work;private org.graalvm.polyglot.Context context;private Thread watchdog;private volatile boolean closed;
        private RegexRequest(RegexLimits limits){this.limits=limits;this.deadline=System.nanoTime()+java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(limits.maxMillis());}
        private static RegexRequest open(RegexLimits limits){if(ACTIVE.get()!=null)throw new NativeValidationException(Code.ENFORCEMENT,"Native regex validation cannot be re-entered.");var request=new RegexRequest(limits);ACTIVE.set(request);return request;}
        private static RegexRequest current(){var request=ACTIVE.get();if(request==null)throw new NativeValidationException(Code.ENFORCEMENT,"Native regex execution escaped its validation request.");return request;}
        private boolean matches(String pattern,String input){claim(pattern,input);var active=context();try{var matcher=matchers.get(pattern);if(matcher==null){matcher=active.eval(MATCHER).execute(pattern);matchers.put(pattern,matcher);}boolean result=matcher.execute(input).asBoolean();checkComplete();return result;}catch(NativeValidationException failure){throw failure;}catch(org.graalvm.polyglot.PolyglotException failure){if(timedOut.get()||failure.isCancelled()||failure.isInterrupted()||failure.isResourceExhausted())throw resource();throw new NativeValidationException(Code.ENFORCEMENT,"Native ECMA-262 regex evaluation could not complete.");}catch(RuntimeException failure){if(timedOut.get())throw resource();throw new NativeValidationException(Code.ENFORCEMENT,"Native ECMA-262 regex evaluation could not complete.");}}
        private void claim(String pattern,String input){if(pattern.length()>limits.maxPatternUnits())throw new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex pattern limit exceeded.");if(input.length()>limits.maxInputUnits())throw new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex input limit exceeded.");if(evaluations>=limits.maxEvaluations())throw new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex evaluation limit exceeded.");long charge=(long)pattern.length()+input.length();if(charge>limits.maxWorkUnits()-work)throw new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex aggregate work limit exceeded.");evaluations++;work+=charge;checkComplete();}
        private org.graalvm.polyglot.Context context(){if(context!=null)return context;checkComplete();var hostAccess=org.graalvm.polyglot.HostAccess.newBuilder(org.graalvm.polyglot.HostAccess.NONE).allowMutableTargetMappings().build();var created=org.graalvm.polyglot.Context.newBuilder("js").engine(ENGINE).sandbox(org.graalvm.polyglot.SandboxPolicy.CONSTRAINED).allowHostAccess(hostAccess).allowHostClassLookup(name->false).allowNativeAccess(false).allowCreateThread(false).allowCreateProcess(false).allowIO(org.graalvm.polyglot.io.IOAccess.NONE).allowEnvironmentAccess(org.graalvm.polyglot.EnvironmentAccess.NONE).allowPolyglotAccess(org.graalvm.polyglot.PolyglotAccess.NONE).allowValueSharing(false).in(java.io.InputStream.nullInputStream()).out(java.io.OutputStream.nullOutputStream()).err(java.io.OutputStream.nullOutputStream()).option("js.ecmascript-version","2020").option("js.allow-eval","false").build();this.context=created;long remaining=deadline-System.nanoTime();if(remaining<=0){try{created.close(true);}catch(RuntimeException ignored){}throw resource();}var thread=Thread.ofVirtual().name("refine-native-regex-watchdog").inheritInheritableThreadLocals(false).unstarted(()->watch(created));thread.setContextClassLoader(null);this.watchdog=thread;thread.start();return created;}
        private void watch(org.graalvm.polyglot.Context active){for(;;){long remaining=deadline-System.nanoTime();if(remaining<=0)break;java.util.concurrent.locks.LockSupport.parkNanos(remaining);if(Thread.interrupted())return;}if(closed)return;timedOut.set(true);try{active.close(true);}catch(RuntimeException ignored){}}
        private void checkComplete(){if(timedOut.get()||System.nanoTime()-deadline>=0)throw resource();}
        private static NativeValidationException resource(){return new NativeValidationException(Code.RESOURCE_LIMIT,"Native regex resource limit exceeded.");}
        @Override public void close(){if(closed)return;closed=true;ACTIVE.remove();if(watchdog!=null)watchdog.interrupt();RuntimeException cleanup=null;if(context!=null&&!timedOut.get())try{context.close(true);}catch(RuntimeException failure){cleanup=failure;}matchers.clear();if(cleanup!=null)throw new NativeValidationException(Code.ENFORCEMENT,"Native ECMA-262 regex cleanup could not complete.");}
    }
`
