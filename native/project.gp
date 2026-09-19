package native

import (
    "fmt"
    "net/url"
    "strings"

    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
    "goforge.dev/refine/analysis"
    "goforge.dev/refine/language"
    "goforge.dev/refine/provenance"
    "goforge.dev/refine/schemajson"
)

type ResourceSelector struct { Resource string; Pointer string; TypeName string }
type ProjectOptions struct { ResourceID string; Root ResourceSelector; Metadata WireMetadata }
type Enforcement struct { Supported bool; Reason string }
type Resource struct { URI string; Source string }

// Project couples editable checked language source to an immutable native
// sidecar. The sidecar remains authoritative for constraints not represented by
// the language projection.
type Project struct { document *Document; target ProjectTarget; root ResourceSelector; source string; program *language.Program; metadata WireMetadata; releasePolicy *language.ReleasePolicy; resources []Resource; effectiveResources []Resource; languageEntry string; languageFiles []language.SourceFile; jsonOrigins map[string]*provenance.JSONSchema; nativeOrigins map[string]nativeConstraintOrigin; nativeUnitSources map[string]string; nativeUnitsInEditable map[string]bool; avroDefaultChecks []AvroDefaultCheck; schemaChecks analysis.SchemaReport; openAPIOperations *openAPIOperationIndex }

func (p *Project) Format()Format{if p==nil||p.document==nil{return ""};return p.document.Format()}
func (p *Project) Version()string{if p==nil||p.document==nil{return ""};return p.document.Version()}
func (p *Project) Root()ResourceSelector{if p==nil{return ResourceSelector{}};return p.root}
func (p *Project) EditableSource()string{if p==nil{return ""};return p.source}
func (p *Project) Metadata()WireMetadata{if p==nil{return WireMetadata{}};return copyMetadata(p.metadata)}
// ReleasePolicy is release authority carried by the version-controlled native
// bundle. It is deliberately separate from wire metadata.
func (p *Project) ReleasePolicy()*language.ReleasePolicy{if p==nil{return nil};return copyNativeReleasePolicy(p.releasePolicy)}
func (p *Project) Resources()[]Resource{if p==nil{return nil};return append([]Resource(nil),p.resources...)}
func (p *Project) LanguageEntry()string{if p==nil{return ""};return p.languageEntry}
func (p *Project) LanguageFiles()[]language.SourceFile{if p==nil{return nil};out:=append([]language.SourceFile(nil),p.languageFiles...);for i:=range out{out[i].Imports=append([]string(nil),out[i].Imports...)};return out}
func (p *Project) NativeDocument()*Document{if p==nil{return nil};return p.document}
type ResourceConstraint struct { Resource string; Constraint provenance.Constraint }
func (p *Project) NativeConstraints()[]ResourceConstraint{if p==nil{return nil};out:=[]ResourceConstraint{};for _,resource:=range p.resources{if origin:=p.constraintOrigin(resource.URI);origin!=nil{for _,constraint:=range origin.Constraints(){out=append(out,ResourceConstraint{Resource:resource.URI,Constraint:constraint})}}};return out}
func (p *Project) ResourceConstraintSource(resource string)string{if p==nil||p.constraintOrigin(resource)==nil{return ""};return p.constraintOrigin(resource).ConstraintSource()}
// NativeConstraintSources returns the independently editable, resource-scoped
// canonical constraint units. Unlike EditableSource, every resource is
// represented and colliding generated declaration names never share a module.
func (p *Project) NativeConstraintSources()[]Resource{if p==nil{return nil};out:=[]Resource{};for _,resource:=range p.resources{if _,ok:=p.nativeUnitSources[resource.URI];ok{out=append(out,Resource{URI:resource.URI,Source:p.nativeUnitSources[resource.URI]})}};return out}
// WithEditedNativeConstraintSource explicitly edits one resource's provenance
// units. Empty source is an authored removal; a missing call is never inferred
// as removal. The source is checked and audited before replacing project state.
func (p *Project) WithEditedNativeConstraintSource(resource,source string)(*Project,error){return p.withEditedNativeConstraintSources([]Resource{{URI:resource,Source:source}})}
func (p *Project)withEditedNativeConstraintSources(edits []Resource)(*Project,error){if p==nil{return nil,&Error{Code:"native.project",Message:"a project is required"}};if len(edits)==0{return p,nil};copy:=*p;copy.nativeUnitSources=copyStringMap(p.nativeUnitSources);copy.nativeUnitsInEditable=copyBoolMap(p.nativeUnitsInEditable);copy.resources=append([]Resource(nil),p.resources...);copy.metadata=copyMetadata(p.metadata);for _,edit:=range edits{origin:=p.constraintOrigin(edit.URI);if origin==nil{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:edit.URI,Message:"resource has no native constraint provenance"}};if _,editable:=p.nativeUnitSources[edit.URI];!editable{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:edit.URI,Message:"resource has no editable native constraint units"}};if _,err:=origin.AuditSource(edit.Source);err!=nil{return nil,wrap(p.Format(),"native.provenance",edit.URI,err)};copy.nativeUnitSources[edit.URI]=edit.Source;copy.nativeUnitsInEditable[edit.URI]=false};return validateProject(&copy)}
func (p *Project) AuditResourceSource(resource,source string)([]provenance.Finding,error){if p==nil||p.constraintOrigin(resource)==nil{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:resource,Message:"resource has no native constraint provenance"}};return p.constraintOrigin(resource).AuditSource(source)}
func (p *Project) RecoverResourceNative(resource,name,source string)(string,error){if p==nil||p.constraintOrigin(resource)==nil{return "",&Error{Code:"native.provenance",Format:p.Format(),Pointer:resource,Message:"resource has no native constraint provenance"}};return p.constraintOrigin(resource).RecoverNative(name,source)}
func (p *Project) PayloadType()(*language.PayloadType,error){if p==nil||p.program==nil{return nil,&Error{Code:"native.project",Message:"a checked project is required"}};if err:=p.requirePayloadRoot();err!=nil{return nil,err};return p.program.PayloadType(p.root.TypeName)}

// GeneratedEnforcement is deliberately conservative. Generated language-only
// validators do not yet execute the opaque native sidecar.
func (p *Project) GeneratedEnforcement()Enforcement{return Enforcement{Supported:false,Reason:"generated validators must compose the bundled native validator before claiming enforcement of opaque native keywords"}}

func normalizeProjectOptions(format Format,options ProjectOptions)(ProjectOptions,error){if options.ResourceID==""{if options.Root.Resource!=""{options.ResourceID=options.Root.Resource}else{options.ResourceID="urn:refine:root"}};uri,err:=url.Parse(options.ResourceID);if err!=nil||!uri.IsAbs()||uri.Fragment!=""{return options,&Error{Code:"native.resource",Format:format,Message:"ResourceID must be an absolute URI without a fragment"}};if options.Root.Resource==""{options.Root.Resource=options.ResourceID};if options.Root.Resource!=options.ResourceID{return options,&Error{Code:"native.root",Format:format,Message:"external root resources require IngestProjectResources"}};if !checkedTypeName(options.Root.TypeName){if options.Root.TypeName==""{options.Root.TypeName="ImportedRoot"}else{return options,&Error{Code:"native.root",Format:format,Message:"root TypeName must begin uppercase and contain identifiers"}}};return options,nil}

func IngestProject(format Format,input []byte,options ProjectOptions)(*Project,error){
    options,err:=normalizeProjectOptions(format,options);if err!=nil{return nil,err};var document *Document;source:="";selectedAnnotation:=Annotation{};hasSelectedAnnotation:=false
    switch format{
    case JSONSchema:
        document,err=ParseJSONSchema(input,Options{});if err==nil{if annotated,_,ok:=rootAnnotation(document,options.Root);ok{source=annotated}else{doc,_:=schemajson.Parse(input,Options{}.Limits);source,err=projectJSON(doc,options.Root,false);if err==nil&&document.ConstraintSource()!=""{source+="\n"+document.ConstraintSource()}}}
    case Avro:
        if options.Root.Pointer!=""{return nil,&Error{Code:"native.root",Format:Avro,Pointer:options.Root.Pointer,Message:"Avro root selector pointer must be empty"}};document,err=ParseAvro(input,Options{});if err==nil{doc,_:=schemajson.Parse(input,Options{}.Limits);source,err=projectAvro(doc,options.Root)}
    case OpenAPI:
        if options.Root.Pointer==""{options.Root.Pointer="/components/schemas/"+escapePointer(options.Root.TypeName)};if !strings.HasPrefix(options.Root.Pointer,"/components/schemas/"){return nil,&Error{Code:"native.root",Format:OpenAPI,Pointer:options.Root.Pointer,Message:"selected OpenAPI root must be a Schema Object under /components/schemas"}};document,err=ParseOpenAPI(input,Options{});if err==nil{selectedAnnotation,hasSelectedAnnotation,err=selectedOpenAPISchemaAnnotation(document,map[string][]byte{options.ResourceID:input},options.Root);if err==nil&&hasSelectedAnnotation{source=selectedAnnotation.Source}else if err==nil{l,_:=limits(Options{});rootNode,parseErr:=parseYAML(input,l);if parseErr!=nil{err=parseErr}else{jsonDoc,convertErr:=yamlToJSONDocument(rootNode);if convertErr!=nil{err=convertErr}else{source,err=projectJSON(jsonDoc,options.Root,true)}}}}
    default:return nil,&Error{Code:"native.format",Format:format,Message:"unsupported project format"}
    }
    if err!=nil{return nil,err};if format!=OpenAPI{selectedAnnotation,hasSelectedAnnotation=selectedRootAnnotation(document,options.Root)};if hasSelectedAnnotation{source=selectedAnnotation.Source;if selectedAnnotation.Root!=options.Root.TypeName{source,err=appendNativeSourceDeclarations(source,"type "+options.Root.TypeName+" = "+selectedAnnotation.Root);if err!=nil{return nil,wrap(format,"native.projection",options.Root.Pointer,err)}};options.Metadata,err=mergeAnnotationMetadata(format,options.Metadata,selectedAnnotation);if err!=nil{return nil,err}}
    resourceSet:=[]Resource{{URI:options.ResourceID,Source:document.Original()}};if err:=auditProjectExecutableAnnotations(format,resourceSet,options.Root,hasSelectedAnnotation);err!=nil{return nil,err};nativeOrigins:=map[string]nativeConstraintOrigin{};avroUnits:=map[string]string{};if format==Avro{nativeOrigins,avroUnits=discoverAvroConstraintOrigins(resourceSet);if !hasSelectedAnnotation{source,err=appendAvroConstraintDeclarations(source,resourceSet,avroUnits);if err!=nil{return nil,err}}}
    program,err:=language.Compile(source);if err!=nil{return nil,wrap(format,"native.projection","",err)};if _,err:=program.PayloadType(options.Root.TypeName);err!=nil{return nil,wrap(format,"native.root",options.Root.Pointer,err)};if err:=validateMetadata(program,options.Metadata);err!=nil{return nil,wrap(format,"native.metadata","",err)}
    origins:=make(map[string]*provenance.JSONSchema);units:=make(map[string]string);linked:=make(map[string]bool);if document.jsonProvenance!=nil{origins[options.ResourceID]=document.jsonProvenance;canonical:=document.ConstraintSource();if canonical!=""{units[options.ResourceID]=canonical;linked[options.ResourceID]=nativeConstraintUnitsUnchanged(document.jsonProvenance,source)}};for resource,unit:=range avroUnits{units[resource]=unit;linked[resource]=nativeConstraintUnitsUnchanged(nativeOrigins[resource],source)};project:=&Project{document:document,root:options.Root,source:source,program:program,metadata:copyMetadata(options.Metadata),resources:resourceSet,jsonOrigins:origins,nativeOrigins:nativeOrigins,nativeUnitSources:units,nativeUnitsInEditable:linked};if format==OpenAPI{installOpenAPIConstraintOrigins(project,options.ResourceID)};return validateProject(project)
}

func copyStringMap(in map[string]string)map[string]string{out:=make(map[string]string,len(in));for key,item:=range in{out[key]=item};return out}
func copyBoolMap(in map[string]bool)map[string]bool{out:=make(map[string]bool,len(in));for key,item:=range in{out[key]=item};return out}
// nativeConstraintUnitsUnchanged uses checked declarations and source spans
// from provenance. Lexical lookalikes in comments or strings never establish
// editable authority over the immutable native units.
func nativeConstraintUnitsUnchanged(origin nativeConstraintOrigin,source string)bool{if origin==nil{return false};findings,err:=origin.AuditSource(source);if err!=nil||len(findings)==0{return false};for _,finding:=range findings{if provenance.StatusName(finding.Status)!="unchanged"{return false}};return true}
func (p *Project) editedUnitSources(source string)map[string]string{result:=copyStringMap(p.nativeUnitSources);for resource,linked:=range p.nativeUnitsInEditable{if linked{result[resource]=source}};return result}

func rootAnnotation(document *Document,root ResourceSelector)(string,string,bool){if document==nil{return "","",false};wanted:=root.Pointer+"/x-refine";if document.Format()==OpenAPI{wanted="/x-refine"};for _,annotation:=range document.Annotations(){if annotation.Pointer==wanted&&annotation.Root!=""&&checkedTypeName(annotation.Root){return annotation.Source,annotation.Root,true}};return "","",false}
func selectedRootAnnotation(document *Document,root ResourceSelector)(Annotation,bool){if document==nil{return Annotation{},false};wanted:=root.Pointer+"/x-refine";if document.Format()==OpenAPI{wanted="/x-refine"};for _,annotation:=range document.Annotations(){if annotation.Pointer==wanted&&annotation.Root!=""&&checkedTypeName(annotation.Root){return annotation,true}};return Annotation{},false}
func mergeAnnotationMetadata(format Format,configured WireMetadata,annotation Annotation)(WireMetadata,error){if !annotation.HasMetadata{return configured,nil};if metadataEmpty(configured){return annotation.Metadata,nil};if !metadataEqual(configured,annotation.Metadata){return WireMetadata{},&Error{Code:"native.metadata",Format:format,Pointer:annotation.Pointer+"/metadata",Message:"configured wire metadata conflicts with the embedded refined metadata"}};return configured,nil}

// WithEditedSource checks an author's refinements while retaining the exact
// immutable native sidecar, root selector, and wire metadata.
func (p *Project) WithEditedSource(source string)(*Project,error){return p.WithEditedSourceAndNativeConstraintSources(source,nil)}

// WithEditedSourceAndNativeConstraintSources changes the checked source and
// explicitly selected resource-scoped native units in one atomic validation.
// This is required when an embedded x-refine source deliberately keeps the
// canonical native units separate and both sides of an exact correspondence
// (for example Avro enum constructor order) must change together.
func (p *Project)WithEditedSourceAndNativeConstraintSources(source string,edits []Resource)(*Project,error){if p==nil{return nil,&Error{Code:"native.project",Message:"a project is required"}};program,err:=language.Compile(source);if err!=nil{return nil,wrap(p.Format(),"native.refinement","",err)};return p.withEditedProgramAndNativeConstraintSources(source,program,"",nil,edits)}

// WithEditedSources resolves imports only from the supplied map through the
// language package's bounded, immutable source bundle.
func (p *Project) WithEditedSources(entry string,sources map[string]string)(*Project,error){if p==nil{return nil,&Error{Code:"native.project",Message:"a project is required"}};bundle,err:=language.CompileSources(entry,sources);if err!=nil{return nil,wrap(p.Format(),"native.refinement","",err)};return p.withEditedProgramAndNativeConstraintSources(bundle.Program().Source(),bundle.Program(),bundle.Entry(),bundle.Files(),nil)}

func (p *Project)withEditedProgramAndNativeConstraintSources(source string,program *language.Program,entry string,files []language.SourceFile,edits []Resource)(*Project,error){
    if err:=p.validateEditedProgram(program);err!=nil{return nil,err};copy:=*p;copy.source=source;copy.program=program;copy.languageEntry=entry;copy.languageFiles=append([]language.SourceFile(nil),files...);copy.metadata=copyMetadata(p.metadata);copy.resources=append([]Resource(nil),p.resources...);copy.nativeUnitSources=p.editedUnitSources(source);copy.nativeUnitsInEditable=copyBoolMap(p.nativeUnitsInEditable)
    seen:=map[string]bool{};for _,edit:=range edits{if seen[edit.URI]{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:edit.URI,Message:"duplicate native constraint source edit"}};seen[edit.URI]=true;origin:=p.constraintOrigin(edit.URI);if origin==nil{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:edit.URI,Message:"resource has no native constraint provenance"}};if _,editable:=p.nativeUnitSources[edit.URI];!editable{return nil,&Error{Code:"native.provenance",Format:p.Format(),Pointer:edit.URI,Message:"resource has no editable native constraint units"}};if _,err:=origin.AuditSource(edit.Source);err!=nil{return nil,wrap(p.Format(),"native.provenance",edit.URI,err)};copy.nativeUnitSources[edit.URI]=edit.Source;copy.nativeUnitsInEditable[edit.URI]=false}
    return validateProject(&copy)
}

func (p *Project)validateEditedProgram(program *language.Program)error{if p.HasPayloadRoot(){if _,err:=program.PayloadType(p.root.TypeName);err!=nil{return wrap(p.Format(),"native.root",p.root.Pointer,err)}};if err:=validateMetadata(program,p.metadata);err!=nil{return wrap(p.Format(),"native.metadata","",err)};return nil}

func (p *Project) WithMetadata(metadata WireMetadata)(*Project,error){if p==nil||p.program==nil{return nil,&Error{Code:"native.project",Message:"a checked project is required"}};if err:=validateMetadata(p.program,metadata);err!=nil{return nil,wrap(p.Format(),"native.metadata","",err)};if p.Kind()==OpenAPIOperationsProject&&(metadata.OpenAPI==nil||metadata.OpenAPI.Native==nil){return nil,&Error{Code:"native.metadata",Format:OpenAPI,Pointer:p.EntryResource(),Message:"an OpenAPI operations project must retain authoritative checked native operation bindings"}};copy:=*p;copy.metadata=copyMetadata(metadata);copy.resources=append([]Resource(nil),p.resources...);copy.nativeUnitSources=copyStringMap(p.nativeUnitSources);copy.nativeUnitsInEditable=copyBoolMap(p.nativeUnitsInEditable);return validateProject(&copy)}

// ValidateJSON performs native-only validation at a JSON Schema or supported
// OpenAPI Schema Object root. It does not run the editable language refinements.
func (p *Project) ValidateJSON(input []byte)(failure error){defer recoverRegexEvaluation(p.Format(),&failure);if p==nil||p.document==nil{return &Error{Code:"native.project",Message:"a project is required"}};if err:=p.requirePayloadRoot();err!=nil{return err};if p.Format()==OpenAPI{return p.validateOpenAPIJSON(input)};if p.Format()!=JSONSchema{return &Error{Code:"native.enforcement",Format:p.Format(),Message:"JSON payload validation is not implemented for this format"}}
    instance,err:=schemajson.Parse(input,schemajson.Limits{});if err!=nil{return wrap(JSONSchema,"native.payload","",err)};if err:=scalarJSONWithNumericExpansion(instance.Root(),"",p.metadata.NumericExpansionLimit());err!=nil{return wrap(JSONSchema,"native.limit","",err)};value,err:=jsonoracle.UnmarshalJSON(strings.NewReader(instance.Raw()));if err!=nil{return wrap(JSONSchema,"native.payload","",err)}
    resources,err:=p.CanonicalJSONResources();if err!=nil{return err};catalog,err:=newJSONProjectionCatalog(resources);if err!=nil{return err};scope:=newRegexScope();err=scope.run(JSONSchema,false,func()error{compiler:=newOfflineJSONCompiler();compiler.DefaultDraft(jsonoracle.Draft2020);compiler.UseRegexpEngine(scope.jsonRegexp);compiler.UseLoader(jsonProjectionLoader{catalog:catalog});for _,resource:=range resources{schemaValue,parseErr:=jsonoracle.UnmarshalJSON(strings.NewReader(resource.Source));if parseErr!=nil{return wrap(JSONSchema,"native.structure",resource.URI,parseErr)};if addErr:=compiler.AddResource(resource.URI,schemaValue);addErr!=nil{return wrap(JSONSchema,"native.structure",resource.URI,addErr)}};location:=p.root.Resource;if p.root.Pointer!=""{location+="#"+p.root.Pointer};schema,compileErr:=compiler.Compile(location);if compileErr!=nil{return wrap(JSONSchema,"native.structure",p.root.Pointer,compileErr)};if validateErr:=schema.Validate(value);validateErr!=nil{return wrap(JSONSchema,"native.payload",p.root.Pointer,validateErr)};return nil});if err!=nil{return wrapRegexResult(JSONSchema,"native.enforcement",p.root.Pointer,err)};return nil
}

func (p *Project) Summary()string{if p==nil{return ""};if p.Kind()==OpenAPIOperationsProject{return fmt.Sprintf("%s %s, operations %s",p.Format(),p.Version(),p.EntryResource())};return fmt.Sprintf("%s %s, root %s",p.Format(),p.Version(),p.root.TypeName)}
