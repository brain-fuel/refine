package java

import (
    "os"
    "os/exec"
    "path/filepath"
    "testing"

    "goforge.dev/refine/language"
)

const schemaLimitsHarnessJava=`
import example.schemalimits.*;
public final class SchemaLimitsHarness {
    private static void state(Validation.Outcome value,Validation.State expected){if(value.state()!=expected)throw new AssertionError(value);}
    public static void main(String[] args){
        state(Contract.read("Default","1").outcome(),Validation.State.INDETERMINATE);
        var accepted=Contract.read("Override","1");state(accepted.outcome(),Validation.State.VALID);
        state(Contract.validate("Default",accepted.data()),Validation.State.INDETERMINATE);
        state(Contract.validate("Override",accepted.data()),Validation.State.VALID);
        state(Contract.validate("Override",accepted.data(),new Budget.Limits(0,1)),Validation.State.INDETERMINATE);
        state(Contract.payloadType("Override").validate(accepted.data()),Validation.State.VALID);
        state(Contract.payloadType("Override").read("1",new Budget.Limits(1,0)).outcome(),Validation.State.INDETERMINATE);
        var scalar=new ContractRuntime.Type("named","Int",java.util.List.of(),java.util.List.of(),java.util.List.of());
        var definitions=java.util.Map.of("Legacy",new ContractRuntime.Definition(java.util.List.of(),scalar,java.util.List.of()));
        var functions=java.util.Map.<String,ContractRuntime.FunctionDef>of();
        var caller=Budget.Limits.defaults();
        state(ContractRuntime.validate(definitions,"Legacy",accepted.data(),caller),Validation.State.VALID);
        state(ContractRuntime.validateStructure(definitions,"Legacy",accepted.data(),caller),Validation.State.VALID);
        state(ContractRuntime.validate(definitions,functions,"Legacy",accepted.data(),caller),Validation.State.VALID);
        state(ContractRuntime.validateStructure(definitions,functions,"Legacy",accepted.data(),caller),Validation.State.VALID);
        state(ContractRuntime.read(definitions,functions,"Legacy","1",caller).outcome(),Validation.State.VALID);
    }
}`

func TestGeneratedSchemaLimitsApplyToValidationAndRead(t *testing.T){
    program,err:=language.Compile("@limits total 1000 clause 1\ntype Default = Int where it == it\ntype Override = Int where it == it @steps 100\n");if err!=nil{t.Fatal(err)};files,err:=GenerateValidatorWithTypes(program,"example.schemalimits","Contract",map[string]string{"Override":"Override"});if err!=nil{t.Fatal(err)};compiler,vm:=javaTools(t);dir:=t.TempDir();sources:=[]string{};for _,file:=range files{target:=filepath.Join(dir,filepath.FromSlash(file.Path));if err:=os.MkdirAll(filepath.Dir(target),0755);err!=nil{t.Fatal(err)};if err:=os.WriteFile(target,[]byte(file.Source),0600);err!=nil{t.Fatal(err)};sources=append(sources,target)};harness:=filepath.Join(dir,"SchemaLimitsHarness.java");if err:=os.WriteFile(harness,[]byte(schemaLimitsHarnessJava),0600);err!=nil{t.Fatal(err)};sources=append(sources,harness);classes:=filepath.Join(dir,"classes");args:=append([]string{"--release","25","-encoding","UTF-8","-Xlint:all","-Werror","-d",classes},sources...);if output,err:=exec.Command(compiler,args...).CombinedOutput();err!=nil{t.Fatalf("schema limits javac: %v\n%s",err,output)};if output,err:=exec.Command(vm,"-Xss256k","-cp",classes,"SchemaLimitsHarness").CombinedOutput();err!=nil{t.Fatalf("schema limits Java: %v\n%s",err,output)}
}
