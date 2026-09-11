package validation

import "errors"

const DefaultTotalSteps uint64 = 1000000
const DefaultClauseSteps uint64 = 100000

// Limits use zero for unspecified, never to request unlimited execution.
type Limits struct { Total uint64; Clause uint64 }

// Budget belongs to one validation execution. It is not shared across threads.
// Each clause has an independent meter and draws from this common total.
type Budget struct {
    remaining uint64
    used uint64
    clause uint64
    callerClause uint64
}

func tighter(a, b uint64) uint64 { if b != 0 && b < a { return b }; return a }

func NewBudget(schema Limits, caller Limits) *Budget {
    total, clause := schema.Total, schema.Clause
    if total == 0 { total = DefaultTotalSteps }
    if clause == 0 { clause = DefaultClauseSteps }
    return &Budget{remaining: tighter(total, caller.Total), clause: clause, callerClause: caller.Clause}
}

type Meter struct { parent *Budget; remaining uint64; used uint64; exhausted bool }

// BeginClause accepts an optional schema-declared per-where override. A caller
// cap remains effective even when the schema overrides its default clause cap.
func (b *Budget) BeginClause(schemaOverride uint64) *Meter {
    cap := b.clause
    if schemaOverride != 0 { cap = schemaOverride }
    return &Meter{parent: b, remaining: tighter(cap, b.callerClause)}
}
func (b *Budget) Used() uint64 { return b.used }
func (m *Meter) Used() uint64 { return m.used }

// Step charges before an operation. An unaffordable operation is not executed;
// the exhausted meter stays exhausted, but does not consume another clause's
// allowance. Integer subtraction avoids overflow even at uint64 maximum.
func (m *Meter) Step(cost uint64) error {
    if m.exhausted || cost > m.remaining || cost > m.parent.remaining {
        m.exhausted = true
        return errors.New("validation step budget exhausted")
    }
    m.remaining -= cost
    m.parent.remaining -= cost
    m.used += cost
    m.parent.used += cost
    return nil
}
