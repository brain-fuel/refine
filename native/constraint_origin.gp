package native

import "goforge.dev/refine/provenance"

// nativeConstraintOrigin is a checked, immutable resource-scoped adapter.
// Format-specific discovery retains original tokens; project edit/export
// machinery only depends on the common correspondence and audit operations.
type nativeConstraintOrigin interface {
    Constraints() []provenance.Constraint
    ConstraintSource() string
    AuditSource(string) ([]provenance.Finding,error)
    RecoverNative(string,string) (string,error)
}

func (p *Project)constraintOrigin(resource string)nativeConstraintOrigin{
    if p==nil{return nil}
    if origin:=p.nativeOrigins[resource];origin!=nil{return origin}
    // Check the concrete pointer before converting to an interface, so a
    // missing JSON resource never becomes a non-nil typed-nil origin.
    if origin:=p.jsonOrigins[resource];origin!=nil{return origin}
    return nil
}
