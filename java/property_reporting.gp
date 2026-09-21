package java

// Counts property evaluations, not requested iterations or generated helpers.
const propertyReportingJava=`
    private static long passedProperties,passedCases,passedExamples;
    private static void beginSuite(){passedProperties=0;passedCases=0;passedExamples=0;}
    private static void coverage(String detail){System.err.println("REFINE_COVERAGE "+detail+" suite="+SUITE);}
    private static void examplePassed(String label){passedExamples++;System.err.println("REFINE_EXAMPLE PASS "+label+" suite="+SUITE);}
    private static <T> void check(String label,org.jetbrains.jetCheck.Generator<T> generator,java.util.function.Predicate<T> property,String replay){
        checkCases(label,generator,property,replay,CASES);
    }
    private static <T> void checkCases(String label,org.jetbrains.jetCheck.Generator<T> generator,java.util.function.Predicate<T> property,String replay,int requested){
        long[] evaluated={0};
        java.util.function.Predicate<T> counted=value->{evaluated[0]++;return property.test(value);};
        try{
            if(replay.isEmpty())org.jetbrains.jetCheck.PropertyChecker.customized().withSeed(SEED).withIterationCount(requested).silent().forAll(generator,counted);
            else org.jetbrains.jetCheck.PropertyChecker.customized().rechecking(replay).silent().forAll(generator,counted);
            if(evaluated[0]==0)throw new AssertionError("property executed zero cases: "+label);
        }catch(RuntimeException|Error failure){System.err.println("REFINE_PROPERTY FAIL "+label+" evaluations="+evaluated[0]+" suite="+SUITE);throw failure;}
        passedProperties++;passedCases+=evaluated[0];
        System.err.println("REFINE_PROPERTY PASS "+label+" cases="+evaluated[0]+" mode="+(replay.isEmpty()?"generated":"replay")+" suite="+SUITE);
    }
    private static void finishSuite(){
        if(passedProperties==0)throw new AssertionError("suite executed zero properties");
        System.err.println("REFINE_SUITE PASS properties="+passedProperties+" cases="+passedCases+" examples="+passedExamples+" suite="+SUITE);
    }
`
