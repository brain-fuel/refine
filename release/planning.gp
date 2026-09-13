// Package release plans schema-family versions from caller-supplied evidence.
// It deliberately does not claim to prove schema compatibility.
package release

import (
    "crypto/sha256"
    "encoding/hex"
    "fmt"
    "sort"
    "strconv"
    "strings"
)

const maxInt=int(^uint(0)>>1)

// Version is a stable semantic version. Prerelease/build syntax is intentionally
// excluded: released schema identities are exact x.y.z versions.
type Version struct { Major int; Minor int; Patch int }
func (v Version) Valid()bool{return v.Major>=0&&v.Minor>=0&&v.Patch>=0}

func ParseVersion(text string)(Version,error){
    if strings.HasPrefix(text,"v"){text=text[1:]}
    parts:=strings.Split(text,".")
    if len(parts)!=3{return Version{},fmt.Errorf("release.version: %q is not x.y.z",text)}
    values:=[3]int{}
    for i,part:=range parts{
        if part==""||(len(part)>1&&part[0]=='0'){return Version{},fmt.Errorf("release.version: %q is not canonical",text)}
        for _,digit:=range part{if digit<'0'||digit>'9'{return Version{},fmt.Errorf("release.version: %q is not canonical",text)}}
        n,err:=strconv.Atoi(part);if err!=nil||n<0{return Version{},fmt.Errorf("release.version: %q is not canonical",text)}
        values[i]=n
    }
    return Version{Major:values[0],Minor:values[1],Patch:values[2]},nil
}
func (v Version) String()string{return fmt.Sprintf("%d.%d.%d",v.Major,v.Minor,v.Patch)}
func (v Version) Compare(other Version)int{
    if v.Major!=other.Major{if v.Major<other.Major{return -1};return 1}
    if v.Minor!=other.Minor{if v.Minor<other.Minor{return -1};return 1}
    if v.Patch!=other.Patch{if v.Patch<other.Patch{return -1};return 1}
    return 0
}
func (v Version) nextPatch()Version{return Version{Major:v.Major,Minor:v.Minor,Patch:v.Patch+1}}
func (v Version) nextMinor()Version{return Version{Major:v.Major,Minor:v.Minor+1}}
func (v Version) nextMajor()Version{return Version{Major:v.Major+1}}
func successor(v Version,change ChangeKind)(Version,bool){
    switch change{case DocumentationOnly,CompatibleFix:if v.Patch==maxInt{return Version{},false};return v.nextPatch(),true;case CompatibleFeature:if v.Minor==maxInt{return Version{},false};return v.nextMinor(),true;case BreakingChange:if v.Major==0{if v.Minor==maxInt{return Version{},false};return v.nextMinor(),true};if v.Major==maxInt{return Version{},false};return v.nextMajor(),true};return Version{},false
}

// ContentID is the lowercase SHA-256 of the exact bytes being compared.
type ContentID string
func Digest(content []byte)ContentID{sum:=sha256.Sum256(content);return ContentID(hex.EncodeToString(sum[:]))}
func (id ContentID) Valid()bool{raw,err:=hex.DecodeString(string(id));return err==nil&&len(raw)==sha256.Size&&string(id)==strings.ToLower(string(id))}

type Direction uint8
const (Backward Direction=iota+1; Forward)
func (d Direction) String()string{if d==Backward{return "backward"};if d==Forward{return "forward"};return "invalid-direction"}

// ComparisonResult is explicitly three-valued. Unknown is not compatibility.
type ComparisonResult uint8
const (ComparisonValid ComparisonResult=iota+1; ComparisonInvalid; ComparisonUnknown)
func (r ComparisonResult) String()string{switch r{case ComparisonValid:return "valid";case ComparisonInvalid:return "invalid";case ComparisonUnknown:return "unknown"};return "invalid-result"}

// ComparisonRef identifies a comparison by both versions' exact content. The
// candidate is a SNAPSHOT, so its eventual version is deliberately not part of
// the identity.
type ComparisonRef struct {
    Family string
    Baseline Version
    BaselineContent ContentID
    CandidateContent ContentID
    Direction Direction
}
func (r ComparisonRef) key()string{return strings.Join([]string{r.Family,r.Baseline.String(),string(r.BaselineContent),string(r.CandidateContent),strconv.Itoa(int(r.Direction))},"\x00")}

type CompatibilityEvidence struct { Comparison ComparisonRef; Result ComparisonResult; Detail string }
// CompatibilityOverride acknowledges invalid or unknown evidence. It does not
// assert that a breaking change is a fix.
type CompatibilityOverride struct { Comparison ComparisonRef; Reason string }
// BreakingFix is separate even when it targets the same comparison.
type BreakingFix struct { Comparison ComparisonRef; Justification string }

type ChangeKind uint8
const (
    NoChange ChangeKind=iota
    DocumentationOnly
    CompatibleFix
    CompatibleFeature
    BreakingChange
)

type ImportPin struct { Family string; Version Version; Content ContentID; AffectsContract bool }
type ReleaseBaseline struct { Version Version; Content ContentID; Imports []ImportPin }

type PlanningInput struct {
    Family string
    SnapshotContent ContentID
    SnapshotImports []ImportPin
    Intended *Version
    Change ChangeKind
    Releases []ReleaseBaseline
    Comparisons []CompatibilityEvidence
    Overrides []CompatibilityOverride
    BreakingFixes []BreakingFix
    EnforceForward bool
}

type Issue struct { Code string; Message string }
type PlanResult struct {
    Ready bool
    NoPendingVersion bool
    Suggested *Version
    Accepted *Version
    Issues []Issue
}

func issue(result *PlanResult,code,message string){result.Issues=append(result.Issues,Issue{Code:code,Message:message})}
func cloneVersion(v Version)*Version{copy:=v;return &copy}
func validFamily(name string)bool{
    if name==""||name=="."||name==".."||strings.ContainsAny(name,"/\\\x00"){return false}
    return true
}
func samePins(a,b []ImportPin)bool{
    if len(a)!=len(b){return false}
    key:=func(p ImportPin)string{return p.Family+"\x00"+p.Version.String()+"\x00"+string(p.Content)}
    left:=make([]string,len(a));right:=make([]string,len(b));for i,p:=range a{left[i]=key(p)};for i,p:=range b{right[i]=key(p)}
    sort.Strings(left);sort.Strings(right);for i:=range left{if left[i]!=right[i]{return false}};return true
}
func compatibilityBoundary(candidate,baseline Version)bool{
    if candidate.Major!=baseline.Major{return false}
    if candidate.Major==0{return candidate.Minor==baseline.Minor}
    return true
}

// Plan validates evidence and computes exactly the minimum permitted version.
// Policy rejection is returned as issues rather than an opaque error so a CLI
// can display the suggestion and every failed comparison together.
func Plan(input PlanningInput)PlanResult{
    result:=PlanResult{}
    if !validFamily(input.Family){issue(&result,"release.family","family must be a nonempty path-free name")}
    if !input.SnapshotContent.Valid(){issue(&result,"release.snapshot_digest","snapshot content must be a lowercase SHA-256")}
    if input.Change>BreakingChange{issue(&result,"release.change","invalid change classification")}
    releases:=append([]ReleaseBaseline(nil),input.Releases...)
    sort.Slice(releases,func(i,j int)bool{return releases[i].Version.Compare(releases[j].Version)<0})
    seenVersions:=map[string]ContentID{}
    for _,baseline:=range releases{
        if !baseline.Version.Valid(){issue(&result,"release.baseline_version","baseline contains a negative version component")}
        if !baseline.Content.Valid(){issue(&result,"release.baseline_digest","baseline "+baseline.Version.String()+" has an invalid SHA-256")}
        for _,pin:=range baseline.Imports{if !validFamily(pin.Family)||!pin.Version.Valid()||!pin.Content.Valid(){issue(&result,"release.baseline_import","baseline imports require family, exact version, and SHA-256 content")}}
        key:=baseline.Version.String();if prior,ok:=seenVersions[key];ok{if prior!=baseline.Content{issue(&result,"release.immutable","released version "+key+" has conflicting contents")}else{issue(&result,"release.duplicate_baseline","released version "+key+" is duplicated")}};seenVersions[key]=baseline.Content
    }
    for _,pin:=range input.SnapshotImports{if !validFamily(pin.Family)||!pin.Version.Valid()||!pin.Content.Valid(){issue(&result,"release.import_pin","snapshot imports require family, exact version, and SHA-256 content")}}
    if len(releases)==0{
        suggested:=Version{Major:0,Minor:1,Patch:0};result.Suggested=cloneVersion(suggested)
        if input.Change==NoChange{issue(&result,"release.initial_change","an initial release cannot be classified as no change")}
        finishIntended(&result,input.Intended,suggested);result.Ready=len(result.Issues)==0;return result
    }
    latest:=releases[len(releases)-1]
    unchanged:=input.SnapshotContent==latest.Content&&samePins(input.SnapshotImports,latest.Imports)
    if unchanged{
        result.NoPendingVersion=true
        if input.Intended!=nil{issue(&result,"release.unneeded_intended","unchanged snapshot has no pending version; remove the stale intended version")}
        if input.Change!=NoChange{issue(&result,"release.false_change","unchanged snapshot must be classified as no change")}
        result.Ready=len(result.Issues)==0;return result
    }
    if input.Change==NoChange{issue(&result,"release.unclassified_change","changed snapshot requires a change classification")}
    dependencyContractChange:=false
    latestByFamily:=map[string]ImportPin{};for _,p:=range latest.Imports{latestByFamily[p.Family]=p}
    for _,p:=range input.SnapshotImports{if old,ok:=latestByFamily[p.Family];p.AffectsContract&&(!ok||old.Content!=p.Content){dependencyContractChange=true}}
    snapshotByFamily:=map[string]ImportPin{};for _,p:=range input.SnapshotImports{snapshotByFamily[p.Family]=p};for _,old:=range latest.Imports{if _,ok:=snapshotByFamily[old.Family];old.AffectsContract&&!ok{dependencyContractChange=true}}
    if dependencyContractChange&&input.Change==DocumentationOnly{issue(&result,"release.dependency_contract","effective dependency-contract changes cannot be documentation-only")}

    baselineRefs:=map[string]bool{};for _,b:=range releases{baselineRefs[b.Version.String()+"\x00"+string(b.Content)]=true}
    evidence:=map[string]CompatibilityEvidence{};for _,e:=range input.Comparisons{key:=e.Comparison.key();if _,ok:=evidence[key];ok{issue(&result,"release.duplicate_comparison","comparison evidence is duplicated")};evidence[key]=e;if e.Comparison.Family!=input.Family||e.Comparison.CandidateContent!=input.SnapshotContent||!e.Comparison.BaselineContent.Valid()||!baselineRefs[e.Comparison.Baseline.String()+"\x00"+string(e.Comparison.BaselineContent)]{issue(&result,"release.comparison_identity","comparison does not identify this family, snapshot, and an exact released baseline")};if e.Comparison.Direction!=Backward&&e.Comparison.Direction!=Forward{issue(&result,"release.comparison_direction","comparison has invalid direction")};if e.Result!=ComparisonValid&&e.Result!=ComparisonInvalid&&e.Result!=ComparisonUnknown{issue(&result,"release.comparison_result","comparison has an invalid result")}}
    overrides:=map[string]CompatibilityOverride{};for _,o:=range input.Overrides{key:=o.Comparison.key();if strings.TrimSpace(o.Reason)==""{issue(&result,"release.override_reason","compatibility override requires a human-written reason")};if _,ok:=overrides[key];ok{issue(&result,"release.duplicate_override","compatibility override is duplicated")};overrides[key]=o}
    fixes:=map[string]BreakingFix{};for _,f:=range input.BreakingFixes{key:=f.Comparison.key();if strings.TrimSpace(f.Justification)==""{issue(&result,"release.fix_justification","breaking fix requires its own written justification")};if _,ok:=fixes[key];ok{issue(&result,"release.duplicate_fix","breaking-fix annotation is duplicated")};fixes[key]=f}

    // Begin at the nonbreaking/fix line. Enforced proven breaks raise that line
    // unless each is separately annotated as a breaking fix.
    baseChange:=input.Change;if baseChange==BreakingChange{baseChange=CompatibleFix};if baseChange==NoChange{baseChange=CompatibleFix}
    suggested,advanced:=successor(latest.Version,baseChange);if !advanced{issue(&result,"release.version_overflow","cannot represent the next semantic version");return result}
    unexcusedBreak:=false;hasProvenBreak:=false
    for _,e:=range input.Comparisons{
        exact:=e.Comparison.Family==input.Family&&e.Comparison.CandidateContent==input.SnapshotContent&&baselineRefs[e.Comparison.Baseline.String()+"\x00"+string(e.Comparison.BaselineContent)]
        enforced:=exact&&compatibilityBoundary(suggested,e.Comparison.Baseline)&&(e.Comparison.Direction==Backward||(e.Comparison.Direction==Forward&&input.EnforceForward))
        if enforced&&e.Result==ComparisonInvalid{hasProvenBreak=true;if _,fixed:=fixes[e.Comparison.key()];!fixed{unexcusedBreak=true}}
    }
    if input.Change==BreakingChange&&!hasProvenBreak{unexcusedBreak=true}
    if unexcusedBreak{suggested,advanced=successor(latest.Version,BreakingChange);if !advanced{issue(&result,"release.version_overflow","cannot represent the required compatibility-boundary version");return result}}
    result.Suggested=cloneVersion(suggested)
    finishIntended(&result,input.Intended,suggested)

    // Evidence is required against every prior release in the candidate major,
    // in both directions, including pre-1.0 releases across minor boundaries.
    for _,baseline:=range releases{
        if baseline.Version.Major!=suggested.Major{continue}
        for _,direction:=range []Direction{Backward,Forward}{
            ref:=ComparisonRef{Family:input.Family,Baseline:baseline.Version,BaselineContent:baseline.Content,CandidateContent:input.SnapshotContent,Direction:direction}
            e,ok:=evidence[ref.key()];if !ok{issue(&result,"release.missing_comparison",fmt.Sprintf("missing %s comparison with %s",direction.String(),baseline.Version.String()));continue}
            if e.Result!=ComparisonValid&&e.Result!=ComparisonInvalid&&e.Result!=ComparisonUnknown{issue(&result,"release.comparison_result","comparison has an invalid result");continue}
            enforced:=direction==Backward||(direction==Forward&&input.EnforceForward)
            if !compatibilityBoundary(suggested,baseline.Version){enforced=false}
            if !enforced{continue}
            if e.Result==ComparisonUnknown{
                if _,ok:=overrides[ref.key()];!ok{issue(&result,"release.unknown",fmt.Sprintf("enforced %s comparison with %s is unknown and has no content-bound override",direction.String(),baseline.Version.String()))}
            }
            if e.Result==ComparisonInvalid{
                if _,ok:=overrides[ref.key()];!ok{issue(&result,"release.breaking_override",fmt.Sprintf("enforced %s break with %s lacks a content-bound override",direction.String(),baseline.Version.String()))}
                if direction==Backward{if _,ok:=fixes[ref.key()];!ok{issue(&result,"release.breaking_fix",fmt.Sprintf("in-major backward break with %s lacks a separately justified breaking-fix annotation",baseline.Version.String()))}}
            }
        }
    }
    for key:=range overrides{e,ok:=evidence[key];if !ok{issue(&result,"release.orphan_override","override does not identify supplied comparison evidence")}else if e.Result==ComparisonValid{issue(&result,"release.unneeded_override","valid comparison must not carry an override")}}
    for key,fix:=range fixes{e,ok:=evidence[key];if !ok||e.Result!=ComparisonInvalid{issue(&result,"release.orphan_fix","breaking-fix annotation must identify invalid comparison evidence")};override,hasOverride:=overrides[key];if !hasOverride{issue(&result,"release.fix_without_override","breaking fix also requires a distinct compatibility override")}else if strings.TrimSpace(override.Reason)==strings.TrimSpace(fix.Justification){issue(&result,"release.fix_reason_distinct","breaking-fix justification must be distinct from the compatibility acknowledgement")}}
    result.Ready=len(result.Issues)==0&&result.Accepted!=nil
    return result
}

func finishIntended(result *PlanResult,intended *Version,suggested Version){
    if intended==nil{issue(result,"release.intended_required","snapshot must explicitly accept the suggested version");return}
    if !intended.Valid(){issue(result,"release.intended_version","intended version contains a negative component");return}
    if intended.Compare(suggested)!=0{issue(result,"release.intended_mismatch","intended version "+intended.String()+" is inappropriate; explicitly accept suggested "+suggested.String());return}
    result.Accepted=cloneVersion(*intended)
}
