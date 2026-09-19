package project

import (
    "bytes"
    "fmt"
    "path"

    "goforge.dev/refine/java"
    "goforge.dev/refine/native"
)

type javaResourceSet struct { content map[string][]byte }

func (s *javaResourceSet)addNativeJSON(project *native.Project)error{if project==nil||project.Format()==native.Avro{return nil};resources,err:=java.GenerateProjectNativeJSONResources(project);if err!=nil{return err};if s.content==nil{s.content=map[string][]byte{}};for _,resource:=range resources{if prior,ok:=s.content[resource.Path];ok{if !bytes.Equal(prior,resource.Content){return fmt.Errorf("project.resource: generated Java runtime resources disagree at %s",resource.Path)};continue};s.content[resource.Path]=append([]byte(nil),resource.Content...)};return nil}

func (s *javaResourceSet)emit(files map[string][]byte,directory string)error{for name,content:=range s.content{if err:=addFile(files,path.Join(directory,name),content);err!=nil{return err}};return nil}
