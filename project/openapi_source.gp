package project

import (
    "fmt"

    "goforge.dev/refine/native"
)

// normalizeAuthoredOpenAPI converts a checked source declaration into the
// existing rootless native execution target. The source Program remains the
// authority used to construct that target; callers cannot also supply a
// payload root or competing OpenAPI metadata.
func normalizeAuthoredOpenAPI(c Contract)(Contract,error){
    if c.NativeProject!=nil||c.Program==nil||c.Program.OpenAPI()==nil{return c,nil}
    if c.RootType!=""{return c,fmt.Errorf("project.openapi: a standalone OpenAPI declaration has no payload root")}
    if c.Wire.OpenAPI!=nil{return c,fmt.Errorf("project.openapi: operation metadata is declared in the source and cannot be overridden")}
    if len(c.Formats)==0{c.Formats=[]native.Format{native.OpenAPI}}
    if len(c.Formats)!=1||c.Formats[0]!=native.OpenAPI{return c,fmt.Errorf("project.openapi: a standalone OpenAPI declaration supports only its OpenAPI origin format")}
    authored,err:=native.AuthorOpenAPIProject(c.Program,native.AuthorOpenAPIOptions{Metadata:c.Wire});if err!=nil{return c,err}
    c.NativeProject=authored;c.Program=nil;c.Wire=native.WireMetadata{}
    return c,nil
}
