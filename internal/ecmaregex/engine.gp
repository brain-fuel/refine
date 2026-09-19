// Package ecmaregex executes one checked ECMA-262 2020 Unicode regular
// expression guest in isolated WebAssembly instances. It is not the Refine
// language regular-expression engine.
package ecmaregex

import (
    "context"
    "crypto/sha256"
    _ "embed"
    "encoding/hex"
    "errors"
    "fmt"
    "sync"
    "sync/atomic"
    "time"

    "github.com/tetratelabs/wazero"
    "github.com/tetratelabs/wazero/api"
)

const (
    ArtifactName = "refine-ecma262.wasm"
    ArtifactSHA256 = "ee1ff0212d3a3bd28a72f00033f51dad747c8b36e9302edbbbd35cf6a58bfe8f"
    ABIVersion uint32 = 2
    HardMemoryPages uint32 = 512
    HardPatternUnits = 16384
    HardInputUnits = 1 << 20
    HardHandles = 1024
    HardEvaluations uint64 = 10000
    HardWorkUnits uint64 = 8 << 20
    HardPolls uint32 = 1000000
    HardDuration = time.Second
    HardInitializationDuration = 10 * time.Second
    HardInitializationPolls uint32 = 1000000
    HardSessions = 4
)

//go:embed refine-ecma262.wasm
var artifact []byte

type FailureKind string
const (
    SyntaxFailure FailureKind = "syntax"
    ResourceFailure FailureKind = "resource"
    InternalFailure FailureKind = "internal"
)

type Phase string
const (
    InitializationPhase Phase = "initialization"
    CompilationPhase Phase = "compilation"
    MatchPhase Phase = "match"
    ReleasePhase Phase = "release"
)

// Failure deliberately excludes pattern and subject text from Error().
type Failure struct { Kind FailureKind; Phase Phase; cause error }
func (f *Failure) Error()string{if f==nil{return "ECMA-262 regular expression failure"};return "ECMA-262 regular expression "+string(f.Kind)+" failure during "+string(f.Phase)}
func (f *Failure) Unwrap()error{if f==nil{return nil};return f.cause}
func IsFailure(err error,kind FailureKind)bool{var failure *Failure;return errors.As(err,&failure)&&failure.Kind==kind}
func failure(kind FailureKind,phase Phase,cause error)error{return &Failure{Kind:kind,Phase:phase,cause:cause}}

type InitLimits struct { MaxDuration time.Duration; MaxPolls uint32 }
func DefaultInitLimits()InitLimits{return InitLimits{MaxDuration:HardInitializationDuration,MaxPolls:HardInitializationPolls}}
func checkedInitLimits(input InitLimits)(InitLimits,error){if input.MaxDuration==0{input.MaxDuration=HardInitializationDuration};if input.MaxPolls==0{input.MaxPolls=HardInitializationPolls};if input.MaxDuration<0||input.MaxPolls==0{return input,errors.New("ECMA-262 initialization limits must be positive")};if input.MaxDuration>HardInitializationDuration||input.MaxPolls>HardInitializationPolls{return input,errors.New("ECMA-262 initialization limits may only tighten hard limits")};return input,nil}

type Engine struct {runtime wazero.Runtime;compiled wazero.CompiledModule;initialization InitLimits;idle chan *guestSession;capacity chan struct{};closed atomic.Bool;once sync.Once;closeErr error}

// Artifact returns a defensive copy for generators that must emit the exact
// guest as a sibling resource rather than a Java source constant.
func Artifact()[]byte{return append([]byte(nil),artifact...)}

func New(ctx context.Context,limits InitLimits)(*Engine,error){
    if ctx==nil{return nil,errors.New("ECMA-262 engine requires a context")};if err:=ctx.Err();err!=nil{return nil,failure(ResourceFailure,InitializationPhase,err)}
    checked,err:=checkedInitLimits(limits);if err!=nil{return nil,err}
    if err:=verifyArtifact(artifact);err!=nil{return nil,failure(InternalFailure,InitializationPhase,err)}
    initCtx,cancel:=context.WithTimeout(ctx,checked.MaxDuration);defer cancel()
    config:=wazero.NewRuntimeConfigInterpreter().WithMemoryLimitPages(HardMemoryPages).WithCloseOnContextDone(true).WithCustomSections(false)
    runtime:=wazero.NewRuntimeWithConfig(initCtx,config)
    engine:=&Engine{runtime:runtime,initialization:checked,idle:make(chan *guestSession,HardSessions),capacity:make(chan struct{},HardSessions)};for index:=0;index<HardSessions;index++{engine.capacity<-struct{}{}}
    _,err=runtime.NewHostModuleBuilder("refine").NewFunctionBuilder().WithFunc(interruptHost).Export("should_interrupt").Instantiate(initCtx)
    if err!=nil{runtime.Close(initCtx);return nil,failure(InternalFailure,InitializationPhase,err)}
    compiled,err:=runtime.CompileModule(initCtx,artifact);if err!=nil{runtime.Close(context.Background());kind:=InternalFailure;if initCtx.Err()!=nil{kind=ResourceFailure};return nil,failure(kind,InitializationPhase,err)}
    if err:=verifyCompiled(compiled);err!=nil{runtime.Close(initCtx);return nil,failure(InternalFailure,InitializationPhase,err)}
    engine.compiled=compiled
    return engine,nil
}

func (e *Engine) Close(ctx context.Context)error{if e==nil{return nil};e.once.Do(func(){e.closed.Store(true);if ctx==nil{ctx=context.Background()};e.closeErr=e.runtime.Close(ctx)});return e.closeErr}

func verifyArtifact(input []byte)error{sum:=sha256.Sum256(input);actual:=hex.EncodeToString(sum[:]);if actual!=ArtifactSHA256{return fmt.Errorf("checked ECMA-262 artifact digest mismatch: %s",actual)};return nil}

func verifyCompiled(module wazero.CompiledModule)error{
    imports:=module.ImportedFunctions();if len(imports)!=1{return fmt.Errorf("ECMA-262 artifact imports %d functions",len(imports))};namespace,name,ok:=imports[0].Import();if !ok||namespace!="refine"||name!="should_interrupt"||!sameTypes(imports[0].ParamTypes(),api.ValueTypeI32)||!sameTypes(imports[0].ResultTypes(),api.ValueTypeI32){return errors.New("ECMA-262 artifact import inventory changed")}
    if len(module.ImportedMemories())!=0{return errors.New("ECMA-262 artifact imports memory")}
    expected:=map[string]signature{
        "regex_abi_version":{results:[]api.ValueType{api.ValueTypeI32}},"regex_init":{results:[]api.ValueType{api.ValueTypeI32}},"regex_alloc":{params:[]api.ValueType{api.ValueTypeI32},results:[]api.ValueType{api.ValueTypeI32}},"regex_free":{params:[]api.ValueType{api.ValueTypeI32}},
        "regex_compile":{params:[]api.ValueType{api.ValueTypeI32,api.ValueTypeI32,api.ValueTypeI32,api.ValueTypeI32},results:[]api.ValueType{api.ValueTypeI32}},
        "regex_test":{params:[]api.ValueType{api.ValueTypeI32,api.ValueTypeI32,api.ValueTypeI32,api.ValueTypeI32},results:[]api.ValueType{api.ValueTypeI32}},
        "regex_release":{params:[]api.ValueType{api.ValueTypeI32},results:[]api.ValueType{api.ValueTypeI32}},"regex_reset":{results:[]api.ValueType{api.ValueTypeI32}},"regex_destroy":{},
    }
    functions:=module.ExportedFunctions();if len(functions)!=len(expected){return fmt.Errorf("ECMA-262 artifact exports %d functions",len(functions))};for name,want:=range expected{actual,ok:=functions[name];if !ok||!sameTypes(actual.ParamTypes(),want.params...)||!sameTypes(actual.ResultTypes(),want.results...){return fmt.Errorf("ECMA-262 artifact export %s changed",name)}}
    memories:=module.ExportedMemories();if len(memories)!=1{return errors.New("ECMA-262 artifact memory inventory changed")};memory,ok:=memories["memory"];if !ok{return errors.New("ECMA-262 artifact does not export memory")};maximum,bounded:=memory.Max();if !bounded||maximum!=HardMemoryPages{return fmt.Errorf("ECMA-262 artifact memory maximum is %d pages (bounded=%t)",maximum,bounded)};if memory.Min()>maximum{return errors.New("ECMA-262 artifact memory minimum exceeds its maximum")}
    return nil
}

type signature struct {params []api.ValueType;results []api.ValueType}
func sameTypes(actual []api.ValueType,want ...api.ValueType)bool{if len(actual)!=len(want){return false};for i:=range actual{if actual[i]!=want[i]{return false}};return true}

type requestContextKey struct{}
func interruptHost(ctx context.Context,phase uint32)uint32{request,ok:=ctx.Value(requestContextKey{}).(*Request);if !ok||request==nil{return 1};return request.shouldInterrupt(phase)}
