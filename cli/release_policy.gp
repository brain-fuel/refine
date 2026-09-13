package cli

import (
    "fmt"

    "goforge.dev/refine/language"
    "goforge.dev/refine/release"
)

func languagePolicyRef(family string,comparison language.ReleaseComparison)(release.ComparisonRef,error){return policyRef(family,releaseComparisonPolicy{Baseline:comparison.Baseline,BaselineSHA256:comparison.BaselineSHA256,SnapshotSHA256:comparison.SnapshotSHA256,Direction:comparison.Direction})}

// planningReleasePolicy makes the SNAPSHOT schema the sole approval authority.
// Legacy project-config records remain parse-compatible only when an identical
// schema-carried record backs them; they cannot independently approve a result.
func planningReleasePolicy(family string,snapshot *releaseSchemaEntry,legacy releaseFamilyPolicy)([]release.CompatibilityOverride,[]release.BreakingFix,error){
    policy:=snapshot.releasePolicy;schemaOverrides:=map[release.ComparisonRef]string{};schemaFixes:=map[release.ComparisonRef]string{};overrides:=[]release.CompatibilityOverride{};fixes:=[]release.BreakingFix{}
    if policy!=nil{for _,item:=range policy.Overrides{ref,err:=languagePolicyRef(family,item.ReleaseComparison);if err!=nil{return nil,nil,fmt.Errorf("family %s schema compatibility override: %w",family,err)};if prior,exists:=schemaOverrides[ref];exists{if prior!=item.Reason{return nil,nil,fmt.Errorf("family %s schema carries conflicting compatibility reasons for one comparison",family)};continue};schemaOverrides[ref]=item.Reason;overrides=append(overrides,release.CompatibilityOverride{Comparison:ref,Reason:item.Reason})};for _,item:=range policy.BreakingFixes{ref,err:=languagePolicyRef(family,item.ReleaseComparison);if err!=nil{return nil,nil,fmt.Errorf("family %s schema breaking fix: %w",family,err)};if prior,exists:=schemaFixes[ref];exists{if prior!=item.Justification{return nil,nil,fmt.Errorf("family %s schema carries conflicting breaking-fix justifications for one comparison",family)};continue};schemaFixes[ref]=item.Justification;fixes=append(fixes,release.BreakingFix{Comparison:ref,Justification:item.Justification})}}
    migration:=func(kind string,ref release.ComparisonRef,available map[release.ComparisonRef]string)error{for candidate:=range available{if candidate.Baseline==ref.Baseline&&candidate.Direction==ref.Direction{return fmt.Errorf("release.policy_conflict: family %s %s for %s %s has different content identities in SNAPSHOT schema and refine.project.json",family,kind,ref.Baseline.String(),ref.Direction.String())}};return fmt.Errorf("release.policy_migration: family %s %s for %s %s in refine.project.json is not backed by an identical SNAPSHOT schema @releasePolicy record (or native bundle releasePolicy); move compatibility authority into the version-controlled schema",family,kind,ref.Baseline.String(),ref.Direction.String())}
    for _,item:=range legacy.Overrides{ref,err:=policyRef(family,item.releaseComparisonPolicy);if err!=nil{return nil,nil,fmt.Errorf("family %s override: %w",family,err)};reason,exists:=schemaOverrides[ref];if !exists{return nil,nil,migration("compatibility override",ref,schemaOverrides)};if reason!=item.Reason{return nil,nil,fmt.Errorf("release.policy_conflict: family %s compatibility override conflicts between SNAPSHOT schema and refine.project.json",family)}}
    for _,item:=range legacy.BreakingFixes{ref,err:=policyRef(family,item.releaseComparisonPolicy);if err!=nil{return nil,nil,fmt.Errorf("family %s breaking fix: %w",family,err)};justification,exists:=schemaFixes[ref];if !exists{return nil,nil,migration("breaking fix",ref,schemaFixes)};if justification!=item.Justification{return nil,nil,fmt.Errorf("release.policy_conflict: family %s breaking fix conflicts between SNAPSHOT schema and refine.project.json",family)}}
    return overrides,fixes,nil
}
