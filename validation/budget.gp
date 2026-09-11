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

type Meter struct { parent *Budget; enclosing *Meter; remaining uint64; used uint64; exhausted bool }

// BeginClause accepts an optional schema-declared per-where override. A caller
// cap remains effective even when the schema overrides its default clause cap.
func (b *Budget) BeginClause(schemaOverride uint64) *Meter {
    cap := b.clause
    if schemaOverride != 0 { cap = schemaOverride }
    return &Meter{parent: b, remaining: tighter(cap, b.callerClause)}
}

// BeginStructure charges traversal/transfer work to the validation total, not
// to any individual where clause. Its allowance can never exceed that total.
func (b *Budget) BeginStructure() *Meter { return &Meter{parent:b,remaining:b.remaining} }
func (b *Budget) Used() uint64 { return b.used }
func (m *Meter) Used() uint64 { return m.used }

// Nested gives a refinement invoked during another predicate its own local
// limit while charging every enclosing meter. It cannot reset/relax a caller's
// allowance. Failure exhausts only this scope, leaving cheaper enclosing work
// possible when the enclosing budget still has room.
func (m *Meter) Nested(schemaOverride uint64) *Meter {
    cap:=schemaOverride;if cap==0{cap=m.parent.clause}
    cap=tighter(cap,m.parent.callerClause)
    return &Meter{parent:m.parent,enclosing:m,remaining:cap}
}

// Step charges before an operation. An unaffordable operation is not executed;
// the exhausted meter stays exhausted, but does not consume another clause's
// allowance. Integer subtraction avoids overflow even at uint64 maximum.
func (m *Meter) Step(cost uint64) error {
    permitted:=cost<=m.parent.remaining
    for scope:=m;scope!=nil;scope=scope.enclosing{if scope.exhausted || cost>scope.remaining{permitted=false;break}}
    if !permitted {
        m.exhausted = true
        return errors.New("validation step budget exhausted")
    }
    for scope:=m;scope!=nil;scope=scope.enclosing{scope.remaining-=cost;scope.used+=cost}
    m.parent.remaining -= cost
    m.parent.used += cost
    return nil
}
