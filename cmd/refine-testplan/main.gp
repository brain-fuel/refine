// Command refine-testplan prints or executes the deterministic CI fuzz plan.
package main

import (
    "encoding/json"
    "flag"
    "fmt"
    "os"
    "os/exec"
    "regexp"
    "strings"
    "time"

    "goforge.dev/refine/internal/testplan"
)

func main(){if err:=run();err!=nil{fmt.Fprintln(os.Stderr,err);os.Exit(1)}}
func run()error{
    base:=flag.String("base","","baseline commit; absent or unavailable means full selection");head:=flag.String("head","HEAD","candidate commit");full:=flag.Bool("full",false,"select every discovered fuzz target");execute:=flag.Bool("run",false,"execute the printed selection");duration:=flag.Duration("duration",10*time.Second,"fuzz time per selected target (1s to 1m)");flag.Parse();if flag.NArg()!=0||*duration<time.Second||*duration>time.Minute{return fmt.Errorf("expected flags only and a fuzz duration between 1s and 1m")}
command:=exec.Command("git","rev-parse","--show-toplevel");output,err:=command.Output();if err!=nil{return fmt.Errorf("fuzz selection requires a Git repository: %w",err)};root:=strings.TrimSpace(string(output));changed,missing,err:=testplan.Changed(root,*base,*head);if err!=nil{return err};packages,err:=testplan.Discover(root);if err!=nil{return err};if !*full&&!missing{if err=testplan.IncludeChangedTestImports(root,*base,changed,packages);err!=nil{return err}};plan:=testplan.Select(changed,packages,*full||missing);encoder:=json.NewEncoder(os.Stdout);encoder.SetIndent("","  ");if err=encoder.Encode(plan);err!=nil{return err};if !*execute{return nil}
    for _,selection:=range plan.Selections{target:=selection.Target;arguments:=[]string{"test",target.Package,"-run","^$","-fuzz","^"+regexp.QuoteMeta(target.Name)+"$","-fuzztime="+duration.String(),"-fuzzminimizetime=1000x"};fmt.Fprintf(os.Stderr,"Running %s: %s\n",target.Name,strings.Join(selection.Reasons,"; "));command:=exec.Command("go",arguments...);command.Dir=root;command.Stdout=os.Stderr;command.Stderr=os.Stderr;if err=command.Run();err!=nil{return fmt.Errorf("selected fuzz target %s failed: %w",target.Name,err)}};return nil
}
