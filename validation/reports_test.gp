package validation

import "testing"

func TestMergeReportsPreservesInvalidAndIncomplete(t *testing.T){
    invalid:=Collect([]Check{Violated(Diagnostic{Code:"bad"})});unknown:=Collect([]Check{Undecided(Diagnostic{Code:"missing"})});merged:=MergeReports(invalid,unknown)
    if StateName(merged.State())!="invalid"||!merged.Incomplete()||len(merged.Diagnostics())!=2{t.Fatalf("merge lost state: %+v",merged)}
    if got:=MergeReports(Report{},unknown);StateName(got.State())!="indeterminate"||len(got.Diagnostics())!=1{t.Fatalf("valid/unknown merge: %+v",got)}
}
