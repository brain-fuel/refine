package testplan

import (
    "bytes"
    "encoding/json"
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "io"
    "os/exec"
    "path/filepath"
    "sort"
    "strings"
    "unicode"
    "unicode/utf8"
)

// Discover enumerates actual build-selected Go test files; new fuzz targets
// therefore join CI automatically. It never executes a test or reads .gp and
// generated Go as separate test definitions. Generation consistency must run
// before discovery in CI.
func Discover(root string)([]Package,error){
    command:=exec.Command("go","list","-json","./...");command.Dir=root;var stderr bytes.Buffer;command.Stderr=&stderr;output,err:=command.Output();if err!=nil{return nil,fmt.Errorf("go list for fuzz selection: %w: %s",err,stderr.String())}
    decoder:=json.NewDecoder(bytes.NewReader(output));result:=[]Package{}
    for {var metadata struct{Dir string;ImportPath string;Imports,TestImports,XTestImports,TestGoFiles,XTestGoFiles []string};err:=decoder.Decode(&metadata);if err==io.EOF{break};if err!=nil{return nil,err};relative,err:=filepath.Rel(root,metadata.Dir);if err!=nil||relative==".."||strings.HasPrefix(relative,".."+string(filepath.Separator)){return nil,fmt.Errorf("package is outside the repository")};pkg:=Package{ImportPath:metadata.ImportPath,Directory:filepath.ToSlash(relative),Imports:metadata.Imports,TestImports:metadata.TestImports,XTestImports:metadata.XTestImports,Targets:[]Target{}}
        declarations:=map[string][]testDeclaration{};initializers:=[]testDeclaration{}
        for _,name:=range append(metadata.TestGoFiles,metadata.XTestGoFiles...){source:=filepath.Join(metadata.Dir,name);file,err:=parser.ParseFile(token.NewFileSet(),source,nil,parser.SkipObjectResolution);if err!=nil{return nil,err};testFile:=filepath.ToSlash(filepath.Join(relative,name));pkg.TestFiles=append(pkg.TestFiles,testFile);for _,spec:=range file.Imports{if spec.Name!=nil&&spec.Name.Name=="_"{initializers=append(initializers,testDeclaration{File:testFile,Node:spec})}};for _,decl:=range file.Decls{
            switch node:=decl.(type){case *ast.FuncDecl:entry:=testDeclaration{File:testFile,Node:node};declarations[node.Name.Name]=append(declarations[node.Name.Name],entry);if node.Recv!=nil&&len(node.Recv.List)==1{if receiver:=receiverName(node.Recv.List[0].Type);receiver!=""{declarations[receiver]=append(declarations[receiver],entry)}};if node.Name.Name=="init"||node.Recv==nil&&node.Name.Name=="TestMain"{initializers=append(initializers,entry)};if node.Recv!=nil||!fuzzName(node.Name.Name)||!fuzzSignature(node.Type){continue};pkg.Targets=append(pkg.Targets,Target{Package:"./"+pkg.Directory,Name:node.Name.Name,File:testFile})
            case *ast.GenDecl:for _,spec:=range node.Specs{entry:=testDeclaration{File:testFile,Node:spec};switch value:=spec.(type){case *ast.ValueSpec:for _,name:=range value.Names{declarations[name.Name]=append(declarations[name.Name],entry)};if node.Tok==token.VAR&&len(value.Values)>0{initializers=append(initializers,entry)};case *ast.TypeSpec:declarations[value.Name.Name]=append(declarations[value.Name.Name],entry)}}
            }
        }}
        for i:=range pkg.Targets{pkg.Targets[i].Inputs=testInputs(pkg.Targets[i],declarations,initializers)}
        sort.Slice(pkg.Targets,func(i,j int)bool{return targetKey(pkg.Targets[i])<targetKey(pkg.Targets[j])});seen:=map[string]bool{};for _,target:=range pkg.Targets{if seen[target.Name]{return nil,fmt.Errorf("duplicate fuzz target %s in %s",target.Name,pkg.ImportPath)};seen[target.Name]=true};result=append(result,pkg)
    };sort.Slice(result,func(i,j int)bool{return result[i].ImportPath<result[j].ImportPath});return result,nil
}

type testDeclaration struct {File string;Node ast.Node}
func testInputs(target Target,declarations map[string][]testDeclaration,initializers []testDeclaration)[]string{
    pending:=append(append([]testDeclaration(nil),declarations[target.Name]...),initializers...);seen:=map[ast.Node]bool{};files:=map[string]bool{target.File:true}
    for len(pending)>0{current:=pending[len(pending)-1];pending=pending[:len(pending)-1];if seen[current.Node]{continue};seen[current.Node]=true;files[current.File]=true;ast.Inspect(current.Node,func(node ast.Node)bool{if name,ok:=node.(*ast.Ident);ok{pending=append(pending,declarations[name.Name]...)};return true})}
    result:=[]string{};for file:=range files{result=append(result,file)};sort.Strings(result);return result
}

func receiverName(expr ast.Expr)string{switch node:=expr.(type){case *ast.Ident:return node.Name;case *ast.StarExpr:return receiverName(node.X);case *ast.IndexExpr:return receiverName(node.X);case *ast.IndexListExpr:return receiverName(node.X)};return ""}
func fuzzSignature(signature *ast.FuncType)bool{if signature.Params==nil||len(signature.Params.List)!=1||signature.Results!=nil&&len(signature.Results.List)!=0||signature.TypeParams!=nil&&len(signature.TypeParams.List)!=0{return false};parameter:=signature.Params.List[0];if len(parameter.Names)>1{return false};pointer,ok:=parameter.Type.(*ast.StarExpr);if !ok{return false};switch typ:=pointer.X.(type){case *ast.Ident:return typ.Name=="F";case *ast.SelectorExpr:return typ.Sel.Name=="F"};return false}
func fuzzName(name string)bool{if !strings.HasPrefix(name,"Fuzz"){return false};if len(name)==4{return true};next,_:=utf8.DecodeRuneInString(name[4:]);return !unicode.IsLower(next)}

// Changed returns committed changed paths. A missing/initial baseline selects
// a full campaign instead of interpreting missing evidence as an empty diff.
func Changed(root,base,head string)(paths []string,full bool,failure error){
    if !revision(head){return nil,false,fmt.Errorf("fuzz plan head must be a hexadecimal commit ID or HEAD")};if base==""||strings.Trim(base,"0")==""{return []string{},true,nil};if base=="HEAD"||!revision(base){return nil,false,fmt.Errorf("fuzz plan baseline must be a hexadecimal commit ID")}
    exists:=exec.Command("git","cat-file","-e",base+"^{commit}");exists.Dir=root;if err:=exists.Run();err!=nil{return []string{},true,nil}
    command:=exec.Command("git","diff","--name-only","--no-renames","-z",base,head,"--");command.Dir=root;output,err:=command.Output();if err!=nil{return nil,false,fmt.Errorf("git diff for fuzz selection: %w",err)};for _,name:=range strings.Split(string(output),"\x00"){if name!=""{paths=append(paths,name)}};return uniqueSorted(paths),false,nil
}
func revision(value string)bool{if value=="HEAD"{return true};if len(value)<7||len(value)>64{return false};for _,unit:=range value{if !(unit>='0'&&unit<='9'||unit>='a'&&unit<='f'||unit>='A'&&unit<='F'){return false}};return true}
