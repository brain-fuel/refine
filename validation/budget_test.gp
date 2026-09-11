package validation

import (
    "testing"
    "testing/quick"
)

func TestBudgetTighteningAndClauseIsolation(t *testing.T) {
    budget := NewBudget(Limits{Total: 10, Clause: 4}, Limits{Total: 100, Clause: 100})
    first := budget.BeginClause(0)
    if first.Step(4) != nil || first.Step(1) == nil { t.Fatal("caller relaxed schema limit") }
    if first.Step(0) == nil { t.Fatal("exhausted meter revived") }
    second := budget.BeginClause(0)
    if second.Step(4) != nil { t.Fatal("clause exhaustion incorrectly exhausted total") }
    third := budget.BeginClause(0)
    if third.Step(2) != nil || third.Step(1) == nil || budget.Used() != 10 { t.Fatal("overall budget not enforced") }

    tighterBudget := NewBudget(Limits{Total: 100, Clause: 100}, Limits{Total: 3, Clause: 2})
    if tighterBudget.BeginClause(1000).Step(3) == nil { t.Fatal("schema clause override escaped caller cap") }
    if tighterBudget.BeginClause(0).Step(2) != nil { t.Fatal("failed operation was incorrectly charged") }
    if tighterBudget.BeginClause(0).Step(2) == nil { t.Fatal("caller total cap escaped") }
}

func TestBudgetOverflowAndDefaults(t *testing.T) {
    budget := NewBudget(Limits{}, Limits{})
    if budget.BeginClause(0).Step(DefaultClauseSteps+1) == nil { t.Fatal("missing default clause budget") }
    if budget.BeginClause(DefaultTotalSteps+1).Step(DefaultTotalSteps+1) == nil { t.Fatal("missing default total budget") }
    maxUint := ^uint64(0)
    unlimited := NewBudget(Limits{Total: maxUint, Clause: maxUint}, Limits{})
    meter := unlimited.BeginClause(0)
    if meter.Step(maxUint) != nil || meter.Step(1) == nil || unlimited.Used() != maxUint { t.Fatal("budget overflow") }
}

func TestBudgetNeverExceedsCaps(t *testing.T) {
    property := func(total, clause uint16, costs []uint16) bool {
        tcap, ccap := uint64(total)+1, uint64(clause)+1
        budget := NewBudget(Limits{Total: tcap, Clause: ccap}, Limits{})
        for _, cost := range costs {
            meter := budget.BeginClause(0)
            _ = meter.Step(uint64(cost))
            if meter.Used() > ccap || budget.Used() > tcap { return false }
        }
        return true
    }
    if err := quick.Check(property, &quick.Config{MaxCount: 2000}); err != nil { t.Fatal(err) }
}

func TestStructureSharesTotalButNotClauseAllowance(t *testing.T) {
    budget:=NewBudget(Limits{Total:20,Clause:10},Limits{Clause:2})
    structure:=budget.BeginStructure()
    if err:=structure.Step(15);err!=nil{t.Fatal("structural work incorrectly used per-clause cap")}
    clause:=budget.BeginClause(0)
    if err:=clause.Step(2);err!=nil{t.Fatal(err)}
    if clause.Step(1)==nil{t.Fatal("caller clause cap escaped")}
    if structure.Step(4)==nil{t.Fatal("structural meter escaped shared total")}
    if budget.BeginClause(0).Step(2)!=nil || budget.Used()!=19{t.Fatal("failed work consumed another clause allowance")}
}

func TestNestedMetersCannotResetEnclosingAllowance(t *testing.T) {
    budget:=NewBudget(Limits{Total:100,Clause:10},Limits{})
    outer:=budget.BeginClause(0);child:=outer.Nested(1000);grandchild:=child.Nested(1000)
    if grandchild.Step(7)!=nil || outer.Used()!=7 || child.Used()!=7 || grandchild.Used()!=7 || budget.Used()!=7{t.Fatal("nested cost not charged exactly once to total and every ancestor")}
    if grandchild.Step(4)==nil{t.Fatal("nested override relaxed outer cap")}
    if outer.Step(3)!=nil || outer.Used()!=10 || budget.Used()!=10{t.Fatal("failed child consumed parent allowance")}
    if outer.Nested(1000).Step(1)==nil{t.Fatal("new child reset exhausted ancestor")}
    if budget.BeginClause(0).Step(10)!=nil{t.Fatal("unrelated clause lost allowance")}
}
