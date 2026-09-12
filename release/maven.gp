package release

import (
    "fmt"
    "sort"
)

type ArtifactChange uint8
const (ArtifactNoChange ArtifactChange=iota; ArtifactPatchChange; ArtifactFeatureChange; ArtifactBreakingChange)
type GeneratedVersion struct { Family string; SchemaVersion Version; Generated bool }
type MavenPlanningInput struct { Current Version; Intended *Version; PreviouslyPublished []GeneratedVersion; Next []GeneratedVersion; OtherChange ArtifactChange }
type MavenPlan struct { Ready bool; NoPendingVersion bool; Suggested Version; Accepted *Version; RequiredChange ArtifactChange; Removed []GeneratedVersion; Issues []Issue }

func maxArtifactChange(a,b ArtifactChange)ArtifactChange{if a>b{return a};return b}

// PlanMavenVersion applies the explicitly schema-family-major-based no-codegen
// policy. It does not inspect Java bytecode or claim general API compatibility.
func PlanMavenVersion(input MavenPlanningInput)MavenPlan{
    result:=MavenPlan{RequiredChange:input.OtherChange}
    previous:=map[string]GeneratedVersion{};next:=map[string]GeneratedVersion{};currentMajor:=map[string]int{}
    key:=func(v GeneratedVersion)string{return releaseKey(v.Family,v.SchemaVersion)}
    for _,v:=range input.PreviouslyPublished{
        if !validFamily(v.Family){issueMaven(&result,"maven.family","invalid schema family");continue};k:=key(v);if _,ok:=previous[k];ok{issueMaven(&result,"maven.duplicate","duplicate previously published schema version")};previous[k]=v
        if v.SchemaVersion.Major>currentMajor[v.Family]{currentMajor[v.Family]=v.SchemaVersion.Major}
    }
    for _,v:=range input.Next{
        if !validFamily(v.Family){issueMaven(&result,"maven.family","invalid schema family");continue};k:=key(v);if _,ok:=next[k];ok{issueMaven(&result,"maven.duplicate","duplicate next schema version")};next[k]=v
        if v.SchemaVersion.Major>currentMajor[v.Family]{currentMajor[v.Family]=v.SchemaVersion.Major}
    }
    for k,old:=range previous{
        if !old.Generated{continue};replacement,ok:=next[k];if ok&&replacement.Generated{continue}
        result.Removed=append(result.Removed,old)
        if old.SchemaVersion.Major<currentMajor[old.Family]{result.RequiredChange=maxArtifactChange(result.RequiredChange,ArtifactBreakingChange)}else{result.RequiredChange=maxArtifactChange(result.RequiredChange,ArtifactFeatureChange)}
    }
    sort.Slice(result.Removed,func(i,j int)bool{if result.Removed[i].Family!=result.Removed[j].Family{return result.Removed[i].Family<result.Removed[j].Family};return result.Removed[i].SchemaVersion.Compare(result.Removed[j].SchemaVersion)<0})
    if !input.Current.Valid(){issueMaven(&result,"maven.version","current artifact version contains a negative component")}
    switch result.RequiredChange{case ArtifactNoChange:result.Suggested=input.Current;result.NoPendingVersion=true;case ArtifactPatchChange:if input.Current.Patch==maxInt{issueMaven(&result,"maven.version_overflow","cannot represent next patch")}else{result.Suggested=input.Current.nextPatch()};case ArtifactFeatureChange:if input.Current.Minor==maxInt{issueMaven(&result,"maven.version_overflow","cannot represent next minor")}else{result.Suggested=input.Current.nextMinor()};case ArtifactBreakingChange:if input.Current.Major==maxInt{issueMaven(&result,"maven.version_overflow","cannot represent next major")}else{result.Suggested=input.Current.nextMajor()};default:issueMaven(&result,"maven.change","invalid artifact change")}
    if result.NoPendingVersion{if input.Intended!=nil{issueMaven(&result,"maven.unneeded_intended","unchanged artifact has no pending version")};result.Ready=len(result.Issues)==0;return result}
    if input.Intended==nil{issueMaven(&result,"maven.intended","explicitly accept the suggested artifact version")}else if input.Intended.Compare(result.Suggested)!=0{issueMaven(&result,"maven.intended_mismatch",fmt.Sprintf("intended artifact version %s is inappropriate; accept %s",input.Intended.String(),result.Suggested.String()))}else{result.Accepted=cloneVersion(*input.Intended)}
    result.Ready=len(result.Issues)==0&&result.Accepted!=nil;return result
}
func issueMaven(result *MavenPlan,code,message string){result.Issues=append(result.Issues,Issue{Code:code,Message:message})}
