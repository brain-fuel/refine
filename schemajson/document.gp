// Package schemajson parses immutable, ordered JSON documents without losing
// native schema syntax, number precision, or escaped UTF-16 code units.
package schemajson

import (
    "encoding/json"
    "fmt"
    "strings"
    "unicode/utf8"

    "goforge.dev/refine/value"
)

type Kind enum { Object; Array; String; Number; Boolean; Null }

func KindName(kind Kind) string {
    match kind {
    case Object(): return "object"
    case Array(): return "array"
    case String(): return "string"
    case Number(): return "number"
    case Boolean(): return "boolean"
    case Null(): return "null"
    }
}

// Node retains an exact source slice. Its data cannot be mutated through public
// accessors, including ordered object members and array elements.
type Node struct {
    kind Kind
    raw string
    text value.Text
    members []Member
    elements []Node
}
type Member struct { Key value.Text; Value Node }

func (n Node) Kind() Kind { if n.kind == nil { return Null() }; return n.kind }
func (n Node) Raw() string { if n.raw == "" { return "null" }; return n.raw }
func (n Node) Members() []Member { return append([]Member(nil), n.members...) }
func (n Node) Elements() []Node { return append([]Node(nil), n.elements...) }
func (n Node) Text() (value.Text, bool) { return n.text, KindName(n.Kind()) == "string" }
func (n Node) Lookup(key string) (Node, bool) {
    text, err := value.TextFromUTF8(key)
    if err != nil { return Node{}, false }
    return n.LookupText(text)
}
func (n Node) LookupText(key value.Text) (Node, bool) {
    for _, member := range n.members { if member.Key.Equal(key) { return member.Value, true } }
    return Node{}, false
}

// Limits protect ingestion separately from predicate evaluation. Zero values
// select defaults; an explicit positive value configures each resource cap.
type Limits struct { Bytes int; Depth int; Nodes int }
const DefaultBytes = 16 * 1024 * 1024
const DefaultDepth = 256
const DefaultNodes = 1000000

type Error struct {
    Code string `json:"code"`
    Offset int `json:"offset"`
    Path string `json:"path"`
    Message string `json:"message"`
}
func (e *Error) Error() string { return fmt.Sprintf("%s at byte %d (%s): %s", e.Code, e.Offset, e.Path, e.Message) }

type Document struct { raw string; root Node }
func (d Document) Raw() string { return d.raw }
func (d Document) Root() Node { return d.root }

type parser struct { source string; offset int; count int; limits Limits }

// Parse rejects duplicate decoded keys at every nesting level. It preserves
// the original bytes for unmodified export and never resolves references or
// accesses the network/filesystem. This is syntax ingestion, not schema validity.
func Parse(input []byte, limits Limits) (Document, error) {
    if limits.Bytes < 0 || limits.Depth < 0 || limits.Nodes < 0 { return Document{}, &Error{Code: "json.limit", Message: "limits must be nonnegative"} }
    if limits.Bytes == 0 { limits.Bytes = DefaultBytes }
    if limits.Depth == 0 { limits.Depth = DefaultDepth }
    if limits.Nodes == 0 { limits.Nodes = DefaultNodes }
    if len(input) > limits.Bytes { return Document{}, &Error{Code: "json.limit", Message: "document byte limit exceeded"} }
    if !utf8.Valid(input) { return Document{}, &Error{Code: "json.encoding", Message: "document is not valid UTF-8"} }
    if !json.Valid(input) { return Document{}, &Error{Code: "json.syntax", Message: "invalid JSON document"} }
    p := parser{source: string(input), limits: limits}
    root, err := p.node(0, "")
    if err != nil { return Document{}, err }
    return Document{raw: p.source, root: root}, nil
}

func (p *parser) whitespace() {
    for p.offset < len(p.source) && strings.ContainsRune(" \t\r\n", rune(p.source[p.offset])) { p.offset++ }
}
func (p *parser) quoted() (value.Text, error) {
    start := p.offset
    p.offset++
    for p.source[p.offset] != '"' {
        if p.source[p.offset] == '\\' { p.offset++ }
        p.offset++
    }
    p.offset++
    return value.ReadText(p.source[start:p.offset])
}
func pointerKey(key value.Text) string {
    text, err := key.UTF8()
    if err != nil { text = key.Show() }
    return strings.ReplaceAll(strings.ReplaceAll(text, "~", "~0"), "/", "~1")
}
func (p *parser) node(depth int, path string) (Node, error) {
    p.whitespace()
    if depth > p.limits.Depth { return Node{}, &Error{Code: "json.limit", Offset: p.offset, Path: path, Message: "document depth limit exceeded"} }
    p.count++
    if p.count > p.limits.Nodes { return Node{}, &Error{Code: "json.limit", Offset: p.offset, Path: path, Message: "document node limit exceeded"} }
    start := p.offset
    var n Node
    switch p.source[p.offset] {
    case '{':
        n.kind = Object()
        p.offset++; p.whitespace()
        seen := make(map[string]bool)
        for p.source[p.offset] != '}' {
            keyOffset := p.offset
            key, err := p.quoted()
            if err != nil { return Node{}, err }
            keyPath := path + "/" + pointerKey(key)
            if seen[key.Show()] { return Node{}, &Error{Code: "json.duplicate-key", Offset: keyOffset, Path: keyPath, Message: "duplicate object key"} }
            seen[key.Show()] = true
            p.whitespace(); p.offset++ // colon, already checked by json.Valid
            child, err := p.node(depth+1, keyPath)
            if err != nil { return Node{}, err }
            n.members = append(n.members, Member{Key: key, Value: child})
            p.whitespace()
            if p.source[p.offset] == ',' { p.offset++; p.whitespace() } else { break }
        }
        p.offset++
    case '[':
        n.kind = Array()
        p.offset++; p.whitespace()
        for p.source[p.offset] != ']' {
            child, err := p.node(depth+1, fmt.Sprintf("%s/%d", path, len(n.elements)))
            if err != nil { return Node{}, err }
            n.elements = append(n.elements, child)
            p.whitespace()
            if p.source[p.offset] == ',' { p.offset++; p.whitespace() } else { break }
        }
        p.offset++
    case '"':
        n.kind = String()
        text, err := p.quoted()
        if err != nil { return Node{}, err }
        n.text = text
    default:
        for p.offset < len(p.source) && !strings.ContainsRune(" \t\r\n,]}", rune(p.source[p.offset])) { p.offset++ }
        token := p.source[start:p.offset]
        switch token { case "true", "false": n.kind = Boolean(); case "null": n.kind = Null(); default: n.kind = Number() }
    }
    n.raw = p.source[start:p.offset]
    return n, nil
}
