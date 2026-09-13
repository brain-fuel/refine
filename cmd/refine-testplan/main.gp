// Command refine-testplan prints or executes the deterministic CI fuzz plan.
package main

import (
    "encoding/json"
    "flag"
    "fmt"
    "io"
    "os"
    "os/exec"
    "regexp"
    "strings"
    "time"

    "goforge.dev/refine/internal/testplan"
)

func main(){if err:=run();err!=nil{fmt.Fprintln(os.Stderr,err);os.Exit(1)}}
type runOptions struct{base,head string;full,execute bool;execution executionPolicy}
type executionPolicy struct{Mode string `json:"mode"`;Iterations uint64 `json:"iterations,omitempty"`;Duration string `json:"duration,omitempty"`;MinimizationIterations uint64 `json:"minimizationIterations"`;TestTimeout string `json:"testTimeout"`}

func parseRunOptions(args []string,output io.Writer)(runOptions,error){
    options:=runOptions{};flags:=flag.NewFlagSet("refine-testplan",flag.ContinueOnError);flags.SetOutput(output)
    flags.StringVar(&options.base,"base","","baseline commit; absent or unavailable means full selection");flags.StringVar(&options.head,"head","HEAD","candidate commit");flags.BoolVar(&options.full,"full",false,"select every discovered fuzz target");flags.BoolVar(&options.execute,"run",false,"execute the printed selection")
    var iterations uint64;var duration time.Duration
    flags.Uint64Var(&iterations,"iterations",0,"fuzz iterations per selected target (1 to 100000; default 10000)");flags.DurationVar(&duration,"duration",0,"explicit wall-clock fuzz mode (1s to 1m; conflicts with --iterations)")
    if err:=flags.Parse(args);err!=nil{return options,err};if flags.NArg()!=0{return options,fmt.Errorf("expected flags only")}
    counted,timed:=false,false;flags.Visit(func(option *flag.Flag){if option.Name=="iterations"{counted=true};if option.Name=="duration"{timed=true}})
    if counted&&timed{return options,fmt.Errorf("--iterations and --duration are mutually exclusive")}
    options.execution=executionPolicy{Mode:"iterations",Iterations:10000,MinimizationIterations:1000,TestTimeout:"2m"}
    if timed{if duration<time.Second||duration>time.Minute{return options,fmt.Errorf("--duration must be between 1s and 1m")};options.execution.Mode="duration";options.execution.Iterations=0;options.execution.Duration=duration.String()}else if counted{if iterations==0||iterations>100000{return options,fmt.Errorf("--iterations must be between 1 and 100000")};options.execution.Iterations=iterations}
    return options,nil
}

func fuzzArguments(target testplan.Target,policy executionPolicy)[]string{
    amount:=fmt.Sprintf("%dx",policy.Iterations);if policy.Mode=="duration"{amount=policy.Duration}
    return []string{"test",target.Package,"-run","^$","-fuzz","^"+regexp.QuoteMeta(target.Name)+"$","-fuzztime="+amount,fmt.Sprintf("-fuzzminimizetime=%dx",policy.MinimizationIterations),"-timeout="+policy.TestTimeout}
}

func run()error{
    options,err:=parseRunOptions(os.Args[1:],os.Stderr);if err==flag.ErrHelp{return nil};if err!=nil{return err}
    command:=exec.Command("git","rev-parse","--show-toplevel");output,err:=command.Output();if err!=nil{return fmt.Errorf("fuzz selection requires a Git repository: %w",err)};root:=strings.TrimSpace(string(output));changed,missing,err:=testplan.Changed(root,options.base,options.head);if err!=nil{return err};packages,err:=testplan.Discover(root);if err!=nil{return err};if !options.full&&!missing{if err=testplan.IncludeChangedTestImports(root,options.base,changed,packages);err!=nil{return err}};plan:=testplan.Select(changed,packages,options.full||missing);encoder:=json.NewEncoder(os.Stdout);encoder.SetIndent("","  ");if err=encoder.Encode(struct{testplan.Plan;Execution executionPolicy `json:"execution"`}{plan,options.execution});err!=nil{return err};if !options.execute{return nil}
    for _,selection:=range plan.Selections{target:=selection.Target;arguments:=fuzzArguments(target,options.execution);fmt.Fprintf(os.Stderr,"Running %s: %s\nCommand: go %s\n",target.Name,strings.Join(selection.Reasons,"; "),strings.Join(arguments," "));command:=exec.Command("go",arguments...);command.Dir=root;command.Stdout=os.Stderr;command.Stderr=os.Stderr;if err=command.Run();err!=nil{return fmt.Errorf("selected fuzz target %s failed: %w",target.Name,err)}};return nil
}
