package java

import (
    "strings"

    "goforge.dev/refine/language"
)

type modelFrame struct { declaration language.TypeDecl; types map[string]string; witnesses map[string]string; arguments []string; typeArguments []string }
func (m *modelEmitter) modelRoot(name string)string{
    seen:=map[string]bool{}
    for m.parents[name]!=""{if seen[name]{unsupported(m.declarations[name].At,"cyclic nominal model hierarchy")};seen[name]=true;name=m.parents[name]};return name
}
func (m *modelEmitter) useFrame(frame modelFrame){m.parameters=frame.types;m.witnesses=frame.witnesses}
func (m *modelEmitter) modelFrames(decl language.TypeDecl)[]modelFrame{
    m.genericContext(decl);types,_,arguments:=m.genericParts(decl)
    result:=[]modelFrame{{decl,m.parameters,m.witnesses,arguments,types}}
    for m.parents[decl.Name]!=""{
        _,args:=applied(unrefined(decl.Body));parent:=m.declarations[m.parents[decl.Name]]
        frame:=modelFrame{declaration:parent,types:map[string]string{},witnesses:map[string]string{}}
        for i,arg:=range args{typ,witness:=m.javaType(arg),m.witness(arg);frame.types[parent.Parameters[i]]=typ;frame.witnesses[parent.Parameters[i]]=witness;frame.arguments=append(frame.arguments,witness);frame.typeArguments=append(frame.typeArguments,typ)}
        result=append(result,frame);m.useFrame(frame);decl=parent
    }
    return result
}
func (m *modelEmitter) modelFactoryName()string{
    used:=map[string]bool{sourceNameKey(m.contract):true}
    for name:=range m.declarations{used[sourceNameKey(name)]=true}
    name:="Factory";for used[sourceNameKey(name)]{name+="_"};return name
}
func (m *modelEmitter) factoryInstance(decl language.TypeDecl,arguments []string)string{
    types,_,_:=m.genericParts(decl)
    return "new "+m.qualified(decl.Name)+"."+m.modelFactoryName()+genericSuffix(types)+"("+strings.Join(arguments,",")+")"
}

const genericEvidenceJava = `
    static final class GenericEvidence {
        private final ModelType<?> root;
        private final Data raw;
        private GenericEvidence(ModelType<?> root,Data raw) { this.root=root;this.raw=raw; }
        Data dataFor(ModelType<?> expected) {
            for(ModelType<?> current=root;current!=null;current=current.parent())if(current.sameType(expected))return raw;
            throw new IllegalArgumentException("validation evidence does not belong to this instantiated nominal type");
        }
    }
    static GenericEvidence validate(ModelType<?> target,Data raw,Budget.Limits caller) {
        target.validateData(raw,caller).orThrow();return new GenericEvidence(target,raw);
    }
    static GenericEvidence withoutValidation(ModelType<?> target,Data raw,Budget.Limits caller) {
        @CONTRACT@.modelValidate(target.type,raw,caller,false).orThrow();return new GenericEvidence(target,raw);
    }
    static GenericEvidence read(ModelType<?> target,String text,Budget.Limits caller) {
        return new GenericEvidence(target,@CONTRACT@.modelRead(target.type,text,caller).orThrow());
    }
`
