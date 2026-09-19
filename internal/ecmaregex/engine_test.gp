package ecmaregex

import (
    "context"
    "strings"
    "sync"
    "testing"
    "time"
)

func engineForTest(t *testing.T,initialization InitLimits)*Engine{t.Helper();engine,err:=New(context.Background(),initialization);if err!=nil{t.Fatal(err)};t.Cleanup(func(){if err:=engine.Close(context.Background());err!=nil{t.Error(err)}});return engine}
func requestForTest(t *testing.T,engine *Engine,limits Limits)*Request{t.Helper();request,err:=engine.Begin(context.Background(),limits);if err!=nil{t.Fatal(err)};t.Cleanup(func(){if err:=request.Close();err!=nil{t.Error(err)}});return request}
func requireFailure(t *testing.T,err error,kind FailureKind,phase Phase){t.Helper();failureValue,ok:=err.(*Failure);if !ok||failureValue.Kind!=kind||failureValue.Phase!=phase{t.Fatalf("got %T %v, want %s during %s",err,err,kind,phase)};if strings.Contains(err.Error(),"Greek")||strings.Contains(err.Error(),"secret"){t.Fatal("failure leaked input")}}

func TestCheckedArtifactInventoryAndLimits(t *testing.T){
    first:=Artifact();if len(first)!=1202261{t.Fatalf("artifact bytes = %d",len(first))};first[0]^=0xff;if Artifact()[0]==first[0]{t.Fatal("Artifact exposed mutable embedded bytes")};if err:=verifyArtifact(Artifact());err!=nil{t.Fatal(err)}
    engine:=engineForTest(t,DefaultInitLimits());if engine.compiled==nil{t.Fatal("artifact was not compiled")}
    invalid:=DefaultLimits();invalid.MaxInputUnits=HardInputUnits+1;if _,err:=engine.Begin(context.Background(),invalid);err==nil{t.Fatal("relaxed request limit accepted")}
    invalidInit:=DefaultInitLimits();invalidInit.MaxDuration=HardInitializationDuration+time.Nanosecond;if _,err:=New(context.Background(),invalidInit);err==nil{t.Fatal("relaxed initialization limit accepted")}
}

func TestUTF16ECMA262SyntaxHandlesAndTypedFailures(t *testing.T){
    engine:=engineForTest(t,DefaultInitLimits());request:=requestForTest(t,engine,DefaultLimits())
    greek,err:=request.Compile(`^\p{Script=Greek}+$`);if err!=nil{t.Fatal(err)};matched,err:=request.Test(greek,"πΩ");if err!=nil||!matched{t.Fatalf("Greek script failed: %v",err)};matched,err=request.Test(greek,"abc");if err!=nil||matched{t.Fatalf("false match changed: %v",err)};if err:=request.Release(greek);err!=nil{t.Fatal(err)}
    if _,err:=request.Compile(`\p{Katakana}`);err==nil{t.Fatal("invalid lone script property accepted")}else{requireFailure(t,err,SyntaxFailure,CompilationPhase)}
    if _,err:=request.Compile(`(?>a)`);err==nil{t.Fatal("atomic group accepted")}else{requireFailure(t,err,SyntaxFailure,CompilationPhase)}
    lone,err:=request.CompileUTF16([]uint16{0xd800});if err!=nil{t.Fatal(err)};matched,err=request.TestUTF16(lone,[]uint16{0xd800});if err!=nil||!matched{t.Fatalf("lone surrogate changed: %v",err)};matched,err=request.TestUTF16(lone,[]uint16{0xdc00});if err!=nil||matched{t.Fatalf("distinct lone surrogate matched: %v",err)};if err:=request.Release(lone);err!=nil{t.Fatal(err)}
    astral,err:=request.Compile(`^.$`);if err!=nil{t.Fatal(err)};matched,err=request.TestUTF16(astral,[]uint16{0xd83d,0xde00});if err!=nil||!matched{t.Fatalf("astral code point was not one Unicode match: %v",err)}
}

func TestRequestBudgetsBoundCompilationMatchingAndHandles(t *testing.T){
    engine:=engineForTest(t,DefaultInitLimits())
    handleLimits:=DefaultLimits();handleLimits.MaxHandles=1;request:=requestForTest(t,engine,handleLimits);first,err:=request.Compile("a");if err!=nil{t.Fatal(err)};if _,err:=request.Compile("b");err==nil{t.Fatal("handle limit ignored")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};if err:=request.Release(first);err!=nil{t.Fatal(err)};if _,err:=request.Compile("b");err!=nil{t.Fatal("released handle was not reusable",err)};if err:=request.Close();err!=nil{t.Fatal(err)}
    workLimits:=DefaultLimits();workLimits.MaxWorkUnits=3;work:=requestForTest(t,engine,workLimits);handle,err:=work.Compile("a");if err!=nil{t.Fatal(err)};if matched,err:=work.Test(handle,"a");err!=nil||!matched{t.Fatal("exact work boundary rejected",err)};if _,err:=work.Test(handle,"");err==nil{t.Fatal("aggregate work limit ignored")}else{requireFailure(t,err,ResourceFailure,MatchPhase)};if err:=work.Close();err!=nil{t.Fatal(err)}
    evaluationLimits:=DefaultLimits();evaluationLimits.MaxEvaluations=1;evaluations:=requestForTest(t,engine,evaluationLimits);handle,err=evaluations.Compile("a");if err!=nil{t.Fatal(err)};if _,err:=evaluations.Test(handle,"a");err!=nil{t.Fatal(err)};if _,err:=evaluations.Test(handle,"a");err==nil{t.Fatal("evaluation limit ignored")}else{requireFailure(t,err,ResourceFailure,MatchPhase)};if err:=evaluations.Close();err!=nil{t.Fatal(err)}
    capped:=requestForTest(t,engine,DefaultLimits());if _,err:=capped.CompileUTF16(make([]uint16,HardPatternUnits+1));err==nil{t.Fatal("pattern cap ignored")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};valid,err:=capped.Compile("a");if err!=nil{t.Fatal("preflight resource failure poisoned request",err)};if _,err:=capped.TestUTF16(valid,make([]uint16,HardInputUnits+1));err==nil{t.Fatal("input cap ignored")}else{requireFailure(t,err,ResourceFailure,MatchPhase)};if err:=capped.Close();err!=nil{t.Fatal(err)}
    pollLimits:=DefaultLimits();pollLimits.MaxCompilationPolls=1;pollBound:=requestForTest(t,engine,pollLimits);if _,err:=pollBound.Compile(strings.Repeat("a",HardPatternUnits));err==nil{t.Fatal("parser poll budget ignored")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};if err:=pollBound.Close();err!=nil{t.Fatal(err)}
    durationLimits:=DefaultLimits();durationLimits.MaxCompilationDuration=time.Nanosecond;durationBound:=requestForTest(t,engine,durationLimits);if _,err:=durationBound.Compile(strings.Repeat("a",HardPatternUnits));err==nil{t.Fatal("parser duration budget ignored")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)}
}

func TestSessionsReuseOnlyAfterCleanBoundedReset(t *testing.T){
    engine:=engineForTest(t,DefaultInitLimits());engine.idle=make(chan *guestSession,1);engine.capacity=make(chan struct{},1);engine.capacity<-struct{}{}
    tight:=DefaultLimits();tight.MaxCompilationDuration=100*time.Millisecond;first,err:=engine.Begin(context.Background(),tight);if err!=nil{t.Fatal("cold trusted initialization consumed the compilation budget",err)};firstSession:=first.session;handle,err:=first.Compile(`^\p{Script=Greek}+$`);if err!=nil{t.Fatal(err)};matched,err:=first.Test(handle,"πΩ");if err!=nil||!matched{t.Fatalf("warm Unicode match failed: %v",err)};matched,err=first.Test(handle,"abc");if err!=nil||matched{t.Fatalf("warm Unicode nonmatch changed: %v",err)};if err:=first.Close();err!=nil{t.Fatal(err)}
    second,err:=engine.Begin(context.Background(),tight);if err!=nil{t.Fatal(err)};if second.session!=firstSession{t.Fatal("clean initialized session was not reused")};if len(second.handles)!=0||second.evaluations!=0||second.work!=0||second.polls.Load()!=0||second.compilationPolls.Load()!=0{t.Fatal("request-local state crossed the session boundary")};handle,err=second.Compile("^a+$");if err!=nil{t.Fatal(err)};matched,err=second.Test(handle,"aaaa");if err!=nil||!matched{t.Fatalf("reused session changed match: %v",err)}
    blocked:=DefaultLimits();blocked.MaxCompilationDuration=time.Millisecond;if _,err:=engine.Begin(context.Background(),blocked);err==nil{t.Fatal("session acquisition wait was unbounded")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};if err:=second.Close();err!=nil{t.Fatal(err)}
    syntax,err:=engine.Begin(context.Background(),DefaultLimits());if err!=nil{t.Fatal(err)};if _,err=syntax.Compile(`(?>a)`);err==nil{t.Fatal("invalid syntax accepted")}else{requireFailure(t,err,SyntaxFailure,CompilationPhase)};if err:=syntax.Close();err!=nil{t.Fatal("uncertified clean state changed the syntax outcome",err)}
    mixed,err:=engine.Begin(context.Background(),DefaultLimits());if err!=nil{t.Fatal(err)};lone,err:=mixed.CompileUTF16([]uint16{0xd800});if err!=nil{t.Fatal(err)};matched,err=mixed.TestUTF16(lone,[]uint16{0xd800});if err!=nil||!matched{t.Fatalf("mixed lone-surrogate match failed: %v",err)};astral,err:=mixed.Compile(`^.$`);if err!=nil{t.Fatal(err)};matched,err=mixed.TestUTF16(astral,[]uint16{0xd83d,0xde00});if err!=nil||!matched{t.Fatalf("mixed astral match failed: %v",err)};if err=mixed.Close();err!=nil{t.Fatal("legitimate lazy guest state changed the completed outcome",err)}
    exhaustedLimits:=DefaultLimits();exhaustedLimits.MaxCompilationPolls=1;exhausted,err:=engine.Begin(context.Background(),exhaustedLimits);if err!=nil{t.Fatal(err)};exhaustedSession:=exhausted.session;if _,err=exhausted.Compile(strings.Repeat("a",HardPatternUnits));err==nil{t.Fatal("guest compilation exhaustion accepted")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};if err=exhausted.Close();err!=nil{t.Fatal(err)};afterExhaustion,err:=engine.Begin(context.Background(),DefaultLimits());if err!=nil{t.Fatal(err)};if afterExhaustion.session==exhaustedSession{t.Fatal("resource-exhausted session was reused")};if err=afterExhaustion.Close();err!=nil{t.Fatal(err)}
    cancelledContext,cancel:=context.WithCancel(context.Background());cancelled,err:=engine.Begin(cancelledContext,DefaultLimits());if err==nil{cancel();if _,err=cancelled.Compile("a");err==nil{t.Fatal("cancelled request compiled")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};cancelledSession:=cancelled.session;if err=cancelled.Close();err!=nil{t.Fatal(err)};recovered,beginErr:=engine.Begin(context.Background(),DefaultLimits());if beginErr!=nil{t.Fatal(beginErr)};if recovered.session==cancelledSession{t.Fatal("cancelled session was reused")};if closeErr:=recovered.Close();closeErr!=nil{t.Fatal(closeErr)}}else{cancel();t.Fatal(err)}
    allocation:=&Request{};if _,err=allocation.checkedAllocation([]uint64{0},CompilationPhase);err==nil{t.Fatal("guest allocation exhaustion accepted")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)};if !allocation.poisoned{t.Fatal("guest allocation exhaustion did not poison its session")}
}

func TestTrustedInitializationAndTrapFailuresFailClosed(t *testing.T){
    cancelled,cancel:=context.WithCancel(context.Background());cancel();if engine,err:=New(cancelled,DefaultInitLimits());err==nil{engine.Close(context.Background());t.Fatal("cancelled trusted initialization accepted")}else{requireFailure(t,err,ResourceFailure,InitializationPhase)}
    engine:=engineForTest(t,DefaultInitLimits());request:=requestForTest(t,engine,DefaultLimits());handle,err:=request.Compile("secret");if err!=nil{t.Fatal(err)};if err:=request.module.Close(context.Background());err!=nil{t.Fatal(err)};if _,err:=request.Test(handle,"secret");err==nil{t.Fatal("closed guest produced a truth value")}else{requireFailure(t,err,InternalFailure,MatchPhase)};if _,err:=request.Compile("secret");err==nil{t.Fatal("trapped request was reused")}else{requireFailure(t,err,InternalFailure,CompilationPhase)}
}

func TestStringConveniencesPreflightUTF16Units(t *testing.T){
    engine:=engineForTest(t,DefaultInitLimits());limits:=DefaultLimits();limits.MaxPatternUnits=1;limits.MaxInputUnits=1;request:=requestForTest(t,engine,limits)
    if _,err:=request.Compile("😀");err==nil{t.Fatal("astral pattern crossed the UTF-16 cap")}else{requireFailure(t,err,ResourceFailure,CompilationPhase)}
    handle,err:=request.Compile("a");if err!=nil{t.Fatal("preflight failure poisoned request",err)}
    if _,err:=request.Test(handle,"😀");err==nil{t.Fatal("astral subject crossed the UTF-16 cap")}else{requireFailure(t,err,ResourceFailure,MatchPhase)}
    matched,err:=request.Test(handle,"a");if err!=nil||!matched{t.Fatalf("bounded conversion changed an ordinary match: %v",err)}
    notice:=DistributionNotice();if len(notice)==0{t.Fatal("guest notice is empty")};notice[0]^=0xff;if DistributionNotice()[0]==notice[0]{t.Fatal("guest notice exposed mutable embedded bytes")}
}

func TestFirstMatchDeadlineIsSerializedAndNilSafe(t *testing.T){
    var absent *Request;if _,err:=absent.TestUTF16(1,nil);err==nil{t.Fatal("nil request matched")}else{requireFailure(t,err,InternalFailure,MatchPhase)}
    engine:=engineForTest(t,DefaultInitLimits());request:=requestForTest(t,engine,DefaultLimits());handle,err:=request.Compile("^a+$");if err!=nil{t.Fatal(err)};start:=make(chan struct{});var wait sync.WaitGroup;errorsFound:=make(chan error,16);matches:=make(chan bool,16);for i:=0;i<16;i++{wait.Add(1);go func(){defer wait.Done();<-start;matched,matchErr:=request.Test(handle,"aaaa");matches<-matched;errorsFound<-matchErr}()};close(start);wait.Wait();close(errorsFound);close(matches);success:=0;for matchErr:=range errorsFound{if matchErr==nil{success++;continue};requireFailure(t,matchErr,InternalFailure,MatchPhase)};matchedCount:=0;for matched:=range matches{if matched{matchedCount++}};if success==0||matchedCount!=success{t.Fatalf("serialized first match successes=%d matches=%d",success,matchedCount)};matched,err:=request.Test(handle,"aaaa");if err!=nil||!matched{t.Fatalf("request did not recover after concurrent entry rejection: %v",err)}
}
