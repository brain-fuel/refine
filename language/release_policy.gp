package language

import (
    "encoding/json"
    "fmt"
    "strconv"
    "strings"
    "unicode/utf8"

    "goforge.dev/refine/schemajson"
    "goforge.dev/refine/value"
)

// ReleaseComparison identifies one exact, directional release comparison.
// It is metadata, never a predicate or a source of runtime authority.
type ReleaseComparison struct {
    Baseline string `json:"baseline"`
    BaselineSHA256 string `json:"baselineSha256"`
    SnapshotSHA256 string `json:"snapshotSha256"`
    Direction string `json:"direction"`
}
type CompatibilityApproval struct { ReleaseComparison; Reason string `json:"reason"` }
type BreakingFixApproval struct { ReleaseComparison; Justification string `json:"justification"` }
type ReleasePolicy struct {
    Version int `json:"version"`
    Overrides []CompatibilityApproval `json:"overrides,omitempty"`
    BreakingFixes []BreakingFixApproval `json:"breakingFixes,omitempty"`
}

const releasePolicyBytes = 1 << 20
const releasePolicyRecords = 4096
const releasePolicyExplanationBytes = 8192

func releasePolicyError(message string) error { return fmt.Errorf("language.release_policy: %s", message) }
func copyReleasePolicy(policy *ReleasePolicy) *ReleasePolicy {
    if policy == nil { return nil }
    copy := *policy
    copy.Overrides = append([]CompatibilityApproval(nil), policy.Overrides...)
    copy.BreakingFixes = append([]BreakingFixApproval(nil), policy.BreakingFixes...)
    return &copy
}
// ReleasePolicy returns detached entry-file metadata, not imported approvals.
func (p *Program) ReleasePolicy() *ReleasePolicy {
    if p == nil || p.module == nil { return nil }
    return copyReleasePolicy(p.module.ReleasePolicy)
}
func (b *SourceBundle) ReleasePolicy() *ReleasePolicy {
    if b == nil { return nil }
    return b.program.ReleasePolicy()
}

func releasePolicyString(node schemajson.Node) (string, error) {
    text, ok := node.Text()
    if !ok { return "", releasePolicyError("expected a string") }
    result, err := text.UTF8()
    if err != nil { return "", releasePolicyError("metadata strings must contain Unicode scalar values") }
    return result, nil
}
func releasePolicyObject(node schemajson.Node, allowed []string) (map[string]schemajson.Node, error) {
    if schemajson.KindName(node.Kind()) != "object" { return nil, releasePolicyError("expected an object") }
    fields := map[string]schemajson.Node{}
    for _, member := range node.Members() {
        key, err := member.Key.UTF8(); if err != nil { return nil, releasePolicyError("invalid object key") }
        known := false; for _, name := range allowed { if key == name { known = true; break } }
        if !known { return nil, releasePolicyError("unknown field " + key) }
        fields[key] = member.Value
    }
    return fields, nil
}
func releasePolicyVersion(text string) bool {
    parts := strings.Split(text, "."); if len(parts) != 3 { return false }
    for _, part := range parts {
        n, err := strconv.Atoi(part)
        if err != nil || n < 0 || strconv.Itoa(n) != part { return false }
    }
    return true
}
func releasePolicyDigest(text string) bool {
    if len(text) != 64 { return false }
    for _, r := range text { if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') { return false } }
    return true
}
func releasePolicyRecord(node schemajson.Node, explanation string) (ReleaseComparison, string, error) {
    comparison := ReleaseComparison{}
    fields, err := releasePolicyObject(node, []string{"baseline", "baselineSha256", "snapshotSha256", "direction", explanation})
    if err != nil { return comparison, "", err }
    values := map[string]string{}
    for _, key := range []string{"baseline", "baselineSha256", "snapshotSha256", "direction", explanation} {
        node, ok := fields[key]; if !ok { return comparison, "", releasePolicyError("missing field " + key) }
        text, err := releasePolicyString(node); if err != nil { return comparison, "", err }; values[key] = text
    }
    comparison = ReleaseComparison{Baseline:values["baseline"], BaselineSHA256:values["baselineSha256"], SnapshotSHA256:values["snapshotSha256"], Direction:values["direction"]}
    if !releasePolicyVersion(comparison.Baseline) { return comparison, "", releasePolicyError("baseline must be canonical x.y.z") }
    if !releasePolicyDigest(comparison.BaselineSHA256) || !releasePolicyDigest(comparison.SnapshotSHA256) { return comparison, "", releasePolicyError("comparison digests must be lowercase SHA-256") }
    if comparison.Direction != "backward" && comparison.Direction != "forward" { return comparison, "", releasePolicyError("direction must be backward or forward") }
    text := values[explanation]
    if strings.TrimSpace(text) == "" || len(text) > releasePolicyExplanationBytes { return comparison, "", releasePolicyError("explanation must be nonblank and at most 8192 UTF-8 bytes") }
    return comparison, text, nil
}

// ParseReleasePolicyJSON rejects duplicate/unknown keys, noncanonical identities,
// null containers and unbounded metadata. It does not approve a comparison;
// the release planner must bind every record to its actual comparison identity.
func ParseReleasePolicyJSON(input []byte) (*ReleasePolicy, error) {
    document, err := schemajson.Parse(input, schemajson.Limits{Bytes:releasePolicyBytes, Depth:8, Nodes:40000})
    if err != nil { return nil, releasePolicyError(err.Error()) }
    fields, err := releasePolicyObject(document.Root(), []string{"version", "overrides", "breakingFixes"})
    if err != nil { return nil, err }
    version, ok := fields["version"]
    if !ok || schemajson.KindName(version.Kind()) != "number" || version.Raw() != "1" { return nil, releasePolicyError("version must be 1") }
    policy := &ReleasePolicy{Version:1}
    count := 0
    for _, key := range []string{"overrides", "breakingFixes"} {
        entries, exists := fields[key]; if !exists { continue }
        if schemajson.KindName(entries.Kind()) != "array" { return nil, releasePolicyError(key + " must be an array") }
        if entries.ElementCount() > releasePolicyRecords-count { return nil, releasePolicyError("at most 4096 approval records are allowed") }; count += entries.ElementCount()
        seen := map[string]bool{}
        explanation := "reason"; if key == "breakingFixes" { explanation = "justification" }
        for _, node := range entries.Elements() {
            comparison, text, err := releasePolicyRecord(node, explanation); if err != nil { return nil, err }
            // Length framing keeps arbitrary explanation text unambiguous.
            identity := comparison.Baseline + ":" + comparison.BaselineSHA256 + ":" + comparison.SnapshotSHA256 + ":" + comparison.Direction + ":" + strconv.Itoa(len(text)) + ":" + text
            if seen[identity] { return nil, releasePolicyError("duplicate approval record") }; seen[identity] = true
            if key == "overrides" { policy.Overrides = append(policy.Overrides, CompatibilityApproval{ReleaseComparison:comparison, Reason:text})
            } else { policy.BreakingFixes = append(policy.BreakingFixes, BreakingFixApproval{ReleaseComparison:comparison, Justification:text}) }
        }
    }
    return policy, nil
}

// FormatReleasePolicyJSON emits stable field order and preserves approval order.
func FormatReleasePolicyJSON(policy *ReleasePolicy) ([]byte, error) {
    if policy == nil { return nil, releasePolicyError("policy must not be nil") }
    if len(policy.Overrides) > releasePolicyRecords || len(policy.BreakingFixes) > releasePolicyRecords-len(policy.Overrides) { return nil, releasePolicyError("at most 4096 approval records are allowed") }
    // Preflight authored strings before JSON escaping allocates its output.
    bytes := 0
    add := func(text string) bool { if !utf8.ValidString(text) || len(text) > releasePolicyBytes-bytes { return false }; bytes += len(text); return true }
    for _, item := range policy.Overrides { if !add(item.Baseline) || !add(item.BaselineSHA256) || !add(item.SnapshotSHA256) || !add(item.Direction) || !add(item.Reason) { return nil, releasePolicyError("metadata exceeds 1 MiB") } }
    for _, item := range policy.BreakingFixes { if !add(item.Baseline) || !add(item.BaselineSHA256) || !add(item.SnapshotSHA256) || !add(item.Direction) || !add(item.Justification) { return nil, releasePolicyError("metadata exceeds 1 MiB") } }
    input, err := json.Marshal(policy); if err != nil { return nil, err }
    if _, err := ParseReleasePolicyJSON(input); err != nil { return nil, err }
    return input, nil
}

// splitReleasePolicyTokens recognizes only real lexer tokens, never annotations
// hidden in comments or strings. The footer owns exactly its leading and final
// LF, so removing it preserves every preexisting contract byte and source span.
func splitReleasePolicyTokens(source string, tokens []token) (string, *ReleasePolicy, bool, []token, error) {
    index := -1
    for i := 0; i+1 < len(tokens); i++ {
        if tokens[i].kind == "@" && tokens[i+1].kind == "name" && tokens[i+1].text == "releasePolicy" {
            if index >= 0 { return "", nil, false, nil, releasePolicyError("duplicate footer") }; index = i
        }
    }
    if index < 0 { return source, nil, false, tokens, nil }
    at := tokens[index].at.Start
    if at.Offset < 1 || at.Column != 1 || source[at.Offset-1] != '\n' || index+5 != len(tokens) || tokens[index+2].kind != "text" || tokens[index+3].kind != "newline" || tokens[index+4].kind != "eof" {
        return "", nil, false, nil, releasePolicyError("releasePolicy must be a single final footer with exact LF delimiters")
    }
    raw := tokens[index+2].text
    if source[at.Offset:] != "@releasePolicy " + raw + "\n" { return "", nil, false, nil, releasePolicyError("footer must use exact @releasePolicy text and LF delimiters") }
    decoded, err := value.ReadText(raw); if err != nil { return "", nil, false, nil, releasePolicyError("invalid footer literal") }
    text, err := decoded.UTF8(); if err != nil { return "", nil, false, nil, releasePolicyError("footer must contain Unicode scalar values") }
    policy, err := ParseReleasePolicyJSON([]byte(text)); if err != nil { return "", nil, false, nil, err }
    base := source[:at.Offset-1]
    // The owned LF must itself be outside a comment. Replacing it with EOF
    // leaves all declaration offsets untouched; the original token prefix is
    // retained for body parsing without a second lex of the whole source.
    if index == 0 || tokens[index-1].kind != "newline" || tokens[index-1].at.Start.Offset != at.Offset-1 { return "", nil, false, nil, releasePolicyError("footer requires a leading LF") }
    end := tokens[index-1].at.Start
    bodyTokens := append([]token(nil), tokens[:index-1]...)
    bodyTokens = append(bodyTokens, token{kind:"eof", at:Span{Start:end, End:end}})
    return base, policy, true, bodyTokens, nil
}

// SplitReleasePolicyFooter masks only the owned suffix, not contract bytes.
// Malformed or misplaced real annotations fail rather than becoming authority.
func SplitReleasePolicyFooter(source string) (base string, policy *ReleasePolicy, present bool, failure error) {
    defer recoverSyntax(&failure)
    base, policy, present, _, failure = splitReleasePolicyTokens(source, lex(source))
    return
}

// AppendReleasePolicyFooter appends to exact bytes; it never replaces an
// existing footer or rewrites contract formatting.
func AppendReleasePolicyFooter(base string, policy *ReleasePolicy) (string, error) {
    if _, _, present, err := SplitReleasePolicyFooter(base); err != nil { return "", err } else if present { return "", releasePolicyError("source already has a release-policy footer") }
    input, err := FormatReleasePolicyJSON(policy); if err != nil { return "", err }
    result := base + "\n@releasePolicy " + quote(string(input)) + "\n"
    if len(result) > 16 << 20 { return "", releasePolicyError("source exceeds 16 MiB") }
    return result, nil
}
