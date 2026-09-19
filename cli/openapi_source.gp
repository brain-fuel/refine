package cli

import (
    "fmt"

    "goforge.dev/refine/language"
    "goforge.dev/refine/native"
)

func authoredOpenAPIFormats(family string,settings familyConfig)([]native.Format,error){
    if settings.Root!=""{return nil,fmt.Errorf("family %s has a standalone OpenAPI declaration and must not configure a payload root",family)}
    if settings.Wire.OpenAPI!=nil{return nil,fmt.Errorf("family %s declares OpenAPI operations in source and cannot configure competing OpenAPI wire metadata",family)}
    formats:=append([]native.Format(nil),settings.Formats...);if len(formats)==0{formats=[]native.Format{native.OpenAPI}}
    if len(formats)!=1||formats[0]!=native.OpenAPI{return nil,fmt.Errorf("family %s standalone OpenAPI declaration supports only the openapi format",family)}
    return formats,nil
}

func authoredOpenAPIProject(program *language.Program,family string,settings familyConfig)(*native.Project,[]native.Format,error){
    if program==nil||program.OpenAPI()==nil{return nil,nil,fmt.Errorf("family %s has no checked standalone OpenAPI declaration",family)}
    formats,err:=authoredOpenAPIFormats(family,settings);if err!=nil{return nil,nil,err}
    result,err:=native.AuthorOpenAPIProject(program,native.AuthorOpenAPIOptions{Metadata:settings.Wire});if err!=nil{return nil,nil,err}
    return result,formats,nil
}

func authoredOpenAPIEntry(entry *releaseSchemaEntry)bool{return entry!=nil&&entry.kind==refineSchema&&releaseOperationsEntry(entry)}
