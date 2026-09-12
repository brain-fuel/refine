package cli

import (
    "bytes"
    "encoding/json"
    "errors"
    "flag"
    "fmt"
    "io"

    "goforge.dev/refine/native"
    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/validation"
)

// Native artifact commands write only stdout. Updating an artifact on disk is
// an explicit caller action; malformed edits never produce a partial bundle.
func nativeCommand(args []string,input io.Reader,output,errorOutput io.Writer)int{
    if len(args)==0{fmt.Fprintln(errorOutput,"expected native ingest, source, update, original, or validate-payload");return 2}
    action:=args[0];flags:=flag.NewFlagSet("native "+action,flag.ContinueOnError);flags.SetOutput(errorOutput)
    resource,pointer,rootType,resourceFile:="urn:refine:root","","ImportedRoot",""
    nativeOnly,jsonMode:=false,false
    var totalSteps,clauseSteps uint64
    switch action{
    case "ingest":flags.StringVar(&resource,"resource",resource,"absolute URI identifying the input; never fetched");flags.StringVar(&pointer,"pointer","","selected root JSON Pointer");flags.StringVar(&rootType,"type",rootType,"editable root type name");flags.StringVar(&resourceFile,"resources","","explicit JSON array of offline native resources")
    case "validate-payload":flags.BoolVar(&nativeOnly,"native-only",false,"validate only original native constraints, not added refinements");flags.BoolVar(&jsonMode,"json",false,"emit machine-readable report");flags.Uint64Var(&totalSteps,"total-steps",0,"refinement evaluation total step limit");flags.Uint64Var(&clauseSteps,"clause-steps",0,"refinement evaluation per-clause step limit")
    case "source","update","original":
    default:fmt.Fprintln(errorOutput,"unknown native command");return 2
    }
    if err:=flags.Parse(args[1:]);err!=nil{return 2};paths:=flags.Args();expected:=1;if action=="ingest"||action=="update"||action=="validate-payload"{expected=2};if len(paths)!=expected{fmt.Fprintln(errorOutput,"incorrect native command arguments; use refine help");return 2}
    inputPaths:=paths;if action=="ingest"{inputPaths=paths[1:]};if resourceFile!=""{inputPaths=append(append([]string(nil),inputPaths...),resourceFile)}
    stdin:=0;for _,name:=range inputPaths{if name=="-"{stdin++}};if stdin>1{fmt.Fprintln(errorOutput,"only one input may use stdin");return 2}
    loaded:=map[string][]byte{};for _,name:=range inputPaths{data,err:=load(name,input);if err!=nil{fmt.Fprintln(errorOutput,"cannot read native workflow input:",err);return 2};if len(data)>16<<20{fmt.Fprintln(errorOutput,"native workflow input exceeds 16 MiB");return 1};loaded[name]=data}
    failure:=func(err error)int{
        code:="native.workflow";var detail *native.Error;if errors.As(err,&detail){code=detail.Code}
        message:="Native workflow failed; input values and native-oracle details are omitted."
        if action=="validate-payload"&&jsonMode{result:=report{Phase:"native.validate-payload",State:"invalid",Diagnostics:[]diagnostic{{Code:code,Message:message}}};if code=="native.enforcement"||code=="native.limit"{result.State="indeterminate"};if err:=json.NewEncoder(output).Encode(result);err!=nil{return 2}}else{if _,err:=fmt.Fprintf(errorOutput,"%s: %s\n",code,message);err!=nil{return 2}};return 1
    }
    var project *native.Project;var err error
    if action=="ingest"{
        options:=native.ProjectOptions{ResourceID:resource,Root:native.ResourceSelector{Resource:resource,Pointer:pointer,TypeName:rootType}}
        if resourceFile==""{project,err=native.IngestProject(native.Format(paths[0]),loaded[paths[1]],options)}else{
            raw:=loaded[resourceFile];if _,err=schemajson.Parse(raw,schemajson.Limits{});err!=nil{return failure(err)};var resources []native.Resource;decoder:=json.NewDecoder(bytes.NewReader(raw));decoder.DisallowUnknownFields();if err=decoder.Decode(&resources);err!=nil{return failure(err)}
            for _,dependency:=range resources{if dependency.URI==resource{return failure(fmt.Errorf("root resource must not be duplicated in dependencies"))}}
            resources=append(resources,native.Resource{URI:resource,Source:string(loaded[paths[1]])});project,err=native.IngestProjectResources(native.Format(paths[0]),resources,options)
        }
    }else{project,err=native.ParseBundle(loaded[paths[0]])}
    if err!=nil{return failure(err)}
    var artifact []byte
    switch action{
    case "ingest":artifact,err=project.Bundle()
    case "source":artifact=[]byte(project.EditableSource())
    case "original":artifact=project.NativeDocument().ExportOriginal()
    case "update":project,err=project.WithEditedSource(string(loaded[paths[1]]));if err==nil{artifact,err=project.Bundle()}
    case "validate-payload":
        if !nativeOnly{
            _,checked,decodeErr:=project.DecodeAndValidateJSON(loaded[paths[1]],validation.Limits{Total:totalSteps,Clause:clauseSteps});if decodeErr!=nil{return failure(decodeErr)}
            state:=validation.StateName(checked.State());result:=report{Phase:"native.validate-payload",State:state,Summary:"Native and refined JSON payload validation: "+state,Diagnostics:[]diagnostic{},Result:struct{NativeOnly bool `json:"nativeOnly"`;Validation validation.Report `json:"validation"`}{false,checked}}
            for _,detail:=range checked.Diagnostics(){result.Diagnostics=append(result.Diagnostics,diagnostic{Code:detail.Code,Message:detail.Message})}
            if jsonMode{if err:=json.NewEncoder(output).Encode(result);err!=nil{return 2}}else{writer:=output;if state!="valid"{writer=errorOutput};if _,err:=fmt.Fprintln(writer,result.Summary);err!=nil{return 2};for _,detail:=range result.Diagnostics{if _,err:=fmt.Fprintf(writer,"%s: %s\n",detail.Code,detail.Message);err!=nil{return 2}}}
            if state!="valid"{return 1};return 0
        }
        if project.Format()==native.Avro{err=project.ValidateAvroBinary(loaded[paths[1]],native.AvroPayloadLimits{})}else{err=project.ValidateJSON(loaded[paths[1]])};if err!=nil{return failure(err)}
        summary:="Original native payload constraints passed; added Refine predicates were NOT evaluated."
        if jsonMode{if err:=json.NewEncoder(output).Encode(report{Phase:"native.validate-payload",State:"valid",Summary:summary,Diagnostics:[]diagnostic{},Result:struct{NativeOnly bool `json:"nativeOnly"`}{true}});err!=nil{return 2};return 0};artifact=[]byte(summary+"\n")
    }
    if err!=nil{return failure(err)};if _,err:=output.Write(artifact);err!=nil{return 2};return 0
}
