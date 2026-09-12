package project

import (
    "fmt"

    "goforge.dev/refine/java"
    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

// propertyOptionsWithEmbeddedExamples adapts checked native metadata without
// introducing a native-to-Java package dependency. It never silently adds a
// target because wire adapters currently have one explicit generated target.
func propertyOptionsWithEmbeddedExamples(program *language.Program,metadata native.WireMetadata,options java.PropertyTestOptions)(java.PropertyTestOptions,error){
    checked,err:=native.CheckExamples(program,metadata.Examples);if err!=nil{return options,err};if len(checked)==0{return options,nil};targets:=map[string]bool{};for _,target:=range options.Targets{targets[target.Name]=true};out:=options;out.Examples=append([]java.PropertyExample(nil),options.Examples...)
    for _,example:=range checked{if !targets[example.Target]{return options,fmt.Errorf("project.examples: embedded example %s targets %s, which is not an explicitly generated property target",example.Name,example.Target)};expected:=java.ExampleValid;if example.Expected==native.ExpectedInvalid{expected=java.ExampleInvalid};nativeExpected:=java.ExampleNativeValid;if example.NativeExpected==native.NativeExpectedInvalid{nativeExpected=java.ExampleNativeInvalid};out.Examples=append(out.Examples,java.PropertyExample{Target:example.Target,Value:example.Value,Expected:expected,NativeExpected:nativeExpected,DiagnosticCodes:append([]string(nil),example.DiagnosticCodes...)})}
    return out,nil
}
