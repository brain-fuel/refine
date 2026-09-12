package native

import (
    "context"
    "errors"
    "fmt"
    "net/url"
    "sort"
    "strings"

    "github.com/getkin/kin-openapi/openapi3"
    avro "github.com/hamba/avro/v2"
    yaml "github.com/oasdiff/yaml3"
    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
    "goforge.dev/refine/language"
    "goforge.dev/refine/provenance"
    "goforge.dev/refine/schemajson"
)

// IngestProjectResources validates references using only the explicitly
// supplied, ordered resource set. It never falls back to filesystem or network.
func IngestProjectResources(format Format,resources []Resource,options ProjectOptions)(*Project,error){
    options,err:=normalizeProjectOptions(format,options);if err!=nil{return nil,err};if len(resources)==0{return nil,&Error{Code:"native.resource",Format:format,Message:"at least one resource is required"}};if len(resources)>10000{return nil,&Error{Code:"native.resource",Format:format,Message:"at most 10,000 resources may be supplied"}}
    byURI:=make(map[string][]byte);ordered:=make([]Resource,len(resources));total:=0;for i,resource:=range resources{if len(resource.Source)>(64<<20)-total{return nil,&Error{Code:"native.resource",Format:format,Message:"resource bundle exceeds 64 MiB"}};total+=len(resource.Source);parsed,err:=url.Parse(resource.URI);if err!=nil||!parsed.IsAbs()||parsed.Fragment!=""{return nil,&Error{Code:"native.resource",Format:format,Pointer:resource.URI,Message:"resource URI must be absolute without a fragment"}};if _,duplicate:=byURI[resource.URI];duplicate{return nil,&Error{Code:"native.resource",Format:format,Pointer:resource.URI,Message:"duplicate resource URI"}};byURI[resource.URI]=[]byte(resource.Source);ordered[i]=Resource{URI:resource.URI,Source:resource.Source}}
    mainBytes,ok:=byURI[options.Root.Resource];if !ok{return nil,&Error{Code:"native.root",Format:format,Pointer:options.Root.Resource,Message:"root resource is not in the explicit resource set"}};options.ResourceID=options.Root.Resource
    var document *Document;source:=""
    switch format{
    case JSONSchema:document,err=validateJSONResources(byURI,options.Root);if err==nil{source,err=projectJSONResourceRoot(byURI,options.Root,false);if err==nil&&document.ConstraintSource()!=""{source+="\n"+document.ConstraintSource()}}
    case OpenAPI:document,err=validateOpenAPIResources(byURI,options.Root);if err==nil{if annotated,_,ok:=rootAnnotation(document,options.Root);ok{source=annotated}else{source,err=projectJSONResourceRoot(byURI,options.Root,true)}}
    case Avro:if options.Root.Pointer!=""{return nil,&Error{Code:"native.root",Format:Avro,Pointer:options.Root.Pointer,Message:"Avro root selector pointer must be empty"}};document,source,err=validateAvroResources(ordered,options.Root)
    default:return nil,&Error{Code:"native.format",Format:format,Message:"unsupported project format"}
    }
    if err!=nil{return nil,err};if annotated,rootName,ok:=rootAnnotation(document,options.Root);ok{source=annotated;if rootName!=options.Root.TypeName{source+="\ntype "+options.Root.TypeName+" = "+rootName+"\n"}};if annotation,ok:=selectedRootAnnotation(document,options.Root);ok{options.Metadata,err=mergeAnnotationMetadata(format,options.Metadata,annotation);if err!=nil{return nil,err}};program,err:=language.Compile(source);if err!=nil{return nil,wrap(format,"native.projection","",err)};if _,err:=program.PayloadType(options.Root.TypeName);err!=nil{return nil,wrap(format,"native.root",options.Root.Pointer,err)};if err:=validateMetadata(program,options.Metadata);err!=nil{return nil,wrap(format,"native.metadata","",err)}
    origins:=make(map[string]*provenance.JSONSchema);units:=make(map[string]string);linked:=make(map[string]bool);if format==JSONSchema{for _,resource:=range ordered{origin,e:=provenance.DiscoverJSONSchema([]byte(resource.Source),schemajson.Limits{});if e!=nil{return nil,wrap(JSONSchema,"native.provenance",resource.URI,e)};origins[resource.URI]=origin;if canonical:=origin.ConstraintSource();canonical!=""{units[resource.URI]=canonical}};if rootOrigin:=origins[options.Root.Resource];rootOrigin!=nil&&nativeConstraintUnitsUnchanged(rootOrigin,source){linked[options.Root.Resource]=true}}
    _=mainBytes;return &Project{document:document,root:options.Root,source:source,program:program,metadata:copyMetadata(options.Metadata),resources:ordered,jsonOrigins:origins,nativeUnitSources:units,nativeUnitsInEditable:linked},nil
}

func sortedResourceURIs(resources map[string][]byte)[]string{uris:=make([]string,0,len(resources));for uri:=range resources{uris=append(uris,uri)};sort.Strings(uris);return uris}
func validateJSONResources(resources map[string][]byte,root ResourceSelector)(document *Document,failure error){defer recoverRegexEvaluation(JSONSchema,&failure);compiler:=jsonoracle.NewCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);compiler.UseRegexpEngine(jsonRegexp);var rootDoc schemajson.Document;numericExpansion:=0
    for _,uri:=range sortedResourceURIs(resources){input:=resources[uri];doc,err:=schemajson.Parse(input,schemajson.Limits{});if err!=nil{return nil,wrap(JSONSchema,"native.syntax",uri,err)};if err:=scalarJSONBudget(doc.Root(),"",DefaultNumericExpansion,&numericExpansion);err!=nil{return nil,wrap(JSONSchema,"native.encoding",uri,err)};if err:=checkJSONDraft(doc.Root(),uri);err!=nil{return nil,err};value,err:=jsonoracle.UnmarshalJSON(strings.NewReader(doc.Raw()));if err!=nil{return nil,wrap(JSONSchema,"native.syntax",uri,err)};if err:=compiler.AddResource(uri,value);err!=nil{return nil,wrap(JSONSchema,"native.resource",uri,err)};if uri==root.Resource{rootDoc=doc}}
    location:=root.Resource;if root.Pointer!=""{location+="#"+root.Pointer};if _,err:=compiler.Compile(location);err!=nil{return nil,wrap(JSONSchema,"native.structure",root.Pointer,err)};annotations,err:=jsonSchemaAnnotations(rootDoc.Root());if err!=nil{return nil,err};origins,err:=provenance.DiscoverJSONSchema([]byte(rootDoc.Raw()),schemajson.Limits{});if err!=nil{return nil,wrap(JSONSchema,"native.provenance","",err)};return &Document{format:JSONSchema,version:"2020-12",raw:rootDoc.Raw(),annotations:annotations,jsonProvenance:origins},nil
}

func validateOpenAPIResources(resources map[string][]byte,root ResourceSelector)(document *Document,failure error){defer recoverRegexEvaluation(OpenAPI,&failure);if !strings.HasPrefix(root.Pointer,"/components/schemas/"){return nil,&Error{Code:"native.root",Format:OpenAPI,Pointer:root.Pointer,Message:"selected OpenAPI root must be a Schema Object under /components/schemas"}};main:=resources[root.Resource];l,_:=limits(Options{});var yamlRoot *yaml.Node;numericExpansion:=0;for _,uri:=range sortedResourceURIs(resources){input:=resources[uri];node,err:=parseYAMLWithNumericExpansion(input,l,&numericExpansion);if err!=nil{return nil,wrap(OpenAPI,"native.syntax",uri,err)};if strings.HasPrefix(strings.TrimSpace(string(input)),"{"){doc,err:=schemajson.Parse(input,l);if err!=nil{return nil,wrap(OpenAPI,"native.syntax",uri,err)};if err:=scalarJSONText(doc.Root(),"");err!=nil{return nil,wrap(OpenAPI,"native.encoding",uri,err)}};if uri==root.Resource{yamlRoot=node}}
    loader:=openapi3.NewLoader();loader.IsExternalRefsAllowed=true;loader.ReadFromURIFunc=func(_ *openapi3.Loader,target *url.URL)([]byte,error){copy:=*target;copy.Fragment="";if data,ok:=resources[copy.String()];ok{return append([]byte(nil),data...),nil};return nil,fmt.Errorf("resource %s is not in the explicit bundle",copy.String())};location,_:=url.Parse(root.Resource);parsed,err:=loader.LoadFromDataWithPath(main,location);if err!=nil{return nil,wrap(OpenAPI,"native.structure","",err)};if !supportedOpenAPI(parsed.OpenAPI){return nil,&Error{Code:"native.version",Format:OpenAPI,Pointer:"/openapi",Message:"supported published versions are 3.0.0-3.0.4, 3.1.0-3.1.2, and 3.2.0"}};if err:=parsed.Validate(context.Background(),openapi3.SetRegexCompiler(openAPIRegexp));err!=nil{return nil,wrap(OpenAPI,"native.structure","",err)};annotations,err:=yamlRootAnnotation(yamlRoot);if err!=nil{return nil,err};return &Document{format:OpenAPI,version:parsed.OpenAPI,raw:string(main),annotations:annotations},nil
}

func validateAvroResources(resources []Resource,root ResourceSelector)(*Document,string,error){cache:=&avro.SchemaCache{};sources:=[]string{};var main schemajson.Document
    for index,resource:=range resources{doc,err:=schemajson.Parse([]byte(resource.Source),schemajson.Limits{});if err!=nil{return nil,"",wrap(Avro,"native.syntax",resource.URI,err)};if err:=scalarJSON(doc.Root(),"");err!=nil{return nil,"",wrap(Avro,"native.encoding",resource.URI,err)};if _,err:=avro.ParseBytesWithCache([]byte(resource.Source),"",cache);err!=nil{return nil,"",wrap(Avro,"native.structure",resource.URI,err)};selector:=ResourceSelector{TypeName:fmt.Sprintf("NativeResource%d",index+1)};if resource.URI==root.Resource{selector.TypeName=root.TypeName;main=doc};projected,err:=projectAvro(doc,selector);if err!=nil{return nil,"",err};sources=append(sources,projected)}
    if main.Raw()==""{return nil,"",&Error{Code:"native.root",Format:Avro,Message:"root resource missing"}};annotations,err:=avroAnnotations(main.Root());if err!=nil{return nil,"",err};return &Document{format:Avro,version:"1.12.0",raw:main.Raw(),annotations:annotations},strings.Join(sources,"\n"),nil
}

// projectJSONResourceRoot resolves a chain of root-level external $ref values
// for the editable projection. Nested external references remain an explicit
// projection error; all are nevertheless validated and retained in the bundle.
func projectJSONResourceRoot(resources map[string][]byte,selector ResourceSelector,openAPI bool)(string,error){current:=selector;visited:=make(map[string]bool)
    for {key:=current.Resource+"#"+current.Pointer;if visited[key]{return "",&Error{Code:"native.resource",Pointer:key,Message:"cyclic root reference"}};visited[key]=true;input,ok:=resources[current.Resource];if !ok{return "",&Error{Code:"native.resource",Pointer:current.Resource,Message:"referenced resource is absent"}};var doc schemajson.Document;var err error;if openAPI{l,_:=limits(Options{});yamlRoot,e:=parseYAML(input,l);if e!=nil{return "",e};doc,err=yamlToJSONDocument(yamlRoot)}else{doc,err=schemajson.Parse(input,schemajson.Limits{})};if err!=nil{return "",err};node,err:=doc.At(current.Pointer);if err!=nil{return "",err};refNode,hasRef:=node.Lookup("$ref");if !hasRef{current.TypeName=selector.TypeName;return projectJSON(doc,current,openAPI)};ref,ok:=nodeString(refNode);if !ok{return "",errors.New("reference must be a string")};base,_:=url.Parse(current.Resource);relative,err:=url.Parse(ref);if err!=nil{return "",err};resolved:=base.ResolveReference(relative);pointer:="";if resolved.Fragment!=""{if !strings.HasPrefix(resolved.Fragment,"/"){return "",&Error{Code:"native.projection",Format:pFormat(openAPI),Pointer:ref,Message:"anchor references are retained but not yet projected; use a JSON Pointer root reference"}};pointer=resolved.Fragment};resolved.Fragment="";current=ResourceSelector{Resource:resolved.String(),Pointer:pointer,TypeName:selector.TypeName}}
}
func pFormat(openAPI bool)Format{if openAPI{return OpenAPI};return JSONSchema}
