// Package validation supplies deterministic, payload-private validation results.
package validation

import "encoding/json"

// State has three distinct outcomes. Invalid dominates unknown when aggregating
// separate where clauses, while predicate combinators have their own truth rules.
type State enum { Valid; Invalid; Indeterminate }

func StateName(state State) string {
    match state {
    case Valid(): return "valid"
    case Invalid(): return "invalid"
    case Indeterminate(): return "indeterminate"
    }
}

// Diagnostic deliberately has no payload field. A caller must explicitly
// implement the schema's opt-in message expression to include a payload value.
type Diagnostic struct {
    Code string `json:"code"`
    Paths []string `json:"paths"`
    Predicate string `json:"predicate"`
    Message string `json:"message"`
}

// Check is one evaluated where clause, not one diagnostic per Boolean operand.
type Check enum {
    Satisfied
    Violated(Detail Diagnostic)
    Undecided(Detail Diagnostic)
}

// Report is immutable to callers. Accessors copy diagnostics and nested paths.
type Report struct {
    state State
    incomplete bool
    details []Diagnostic
}

func cloneDiagnostic(d Diagnostic) Diagnostic { d.Paths = append([]string(nil), d.Paths...); return d }
func (r Report) State() State {
    if r.state == nil { return Valid() }
    return r.state
}
func (r Report) Incomplete() bool { return r.incomplete }
func (r Report) Diagnostics() []Diagnostic {
    result := make([]Diagnostic, len(r.details))
    for i, d := range r.details { result[i] = cloneDiagnostic(d) }
    return result
}

type reportJSON struct {
    State string `json:"state"`
    Incomplete bool `json:"incomplete"`
    Diagnostics []Diagnostic `json:"diagnostics"`
}

func (r Report) MarshalJSON() ([]byte, error) {
    return json.Marshal(reportJSON{State: StateName(r.State()), Incomplete: r.incomplete, Diagnostics: r.Diagnostics()})
}

// Collect aggregates independent clauses without discarding a known violation
// when another predicate cannot finish. Input order is diagnostic order.
func Collect(checks []Check) Report {
    r := Report{state: Valid()}
    invalid := false
    for _, check := range checks {
        match check {
        case Satisfied():
        case Violated(detail): invalid = true; r.details = append(r.details, cloneDiagnostic(detail))
        case Undecided(detail): r.incomplete = true; r.details = append(r.details, cloneDiagnostic(detail))
        }
    }
    if invalid { r.state = Invalid() } else if r.incomplete { r.state = Indeterminate() }
    return r
}

// Combination operates on already evaluated predicates. The expression
// evaluator separately controls short-circuiting and deterministic budgets.
type Combination enum { All; AtLeastOne; OnlyOne }

func Combine(mode Combination, checks []Check, detail Diagnostic) Check {
    yes, no, unknown := 0, 0, 0
    for _, check := range checks {
        match check {
        case Satisfied(): yes++
        case Violated(_): no++
        case Undecided(_): unknown++
        }
    }
    match mode {
    case All():
        if no > 0 { return Violated(cloneDiagnostic(detail)) }
        if unknown > 0 { return Undecided(cloneDiagnostic(detail)) }
        return Satisfied()
    case AtLeastOne():
        if yes > 0 { return Satisfied() }
        if unknown > 0 { return Undecided(cloneDiagnostic(detail)) }
        return Violated(cloneDiagnostic(detail))
    case OnlyOne():
        if yes > 1 { return Violated(cloneDiagnostic(detail)) }
        if unknown > 0 { return Undecided(cloneDiagnostic(detail)) }
        if yes == 1 { return Satisfied() }
        return Violated(cloneDiagnostic(detail))
    }
}
