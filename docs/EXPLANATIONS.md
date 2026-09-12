# Generated English contract requirements

`explain.Generate(program)` consumes a checked language program and returns an
immutable document. `Markdown()` includes nominal definitions, one entry per
`where`, custom message expressions, clause budgets, pattern-matched function
equations, and demand-driven English evaluation instructions. Structured getters
return detached copies for native documentation/resource integrations.

Recursive calls reference their function equations rather than expanding them.
Every expression form has an instruction, including short-circuit conditions,
local bindings, exhaustive cases, higher-order calls and collection operations.
The instructions are entered on demand, not executed in numeric order. This
distinction preserves eager arguments and lazy Boolean/conditional branches.
Documentation generation never evaluates predicates or custom messages.

Lexical bindings and user-defined functions take precedence over builtin
descriptions. Author messages remain separate from the predicate algorithm:
their wording does not change the constraint. Escaping protects rendered prose
and code fences from author text, without changing the executable source.

The current exporter describes all declared constraints. A native backend must
select/embed the relevant descriptions without claiming native enforcement of
an arbitrary predicate. Locations identify checked syntax, not a concrete
runtime payload path; automatic runtime error codes may vary by payload path.

Generation is bounded to 100,000 instructions and 16 MiB of stored textual
content. Exceeding the limit returns an error with no partial document. Output
formatting adds headings and escaping to that stored content. Wider source
forms require an explicit future resource-profile extension, not silent omission.

# Conservative analysis

`analysis.Satisfiable` proves contradictions in direct numeric bounds, or checks
candidate values through the complete interpreter to prove existence. Failure
to find a candidate is **unknown**, not unsatisfiable. Supported bound operators
are `<`, `<=`, `>`, `>=`, `==`, literal true/false, and conjunction; named scalar
parents and explicit fixed-width ranges are retained. Other predicates remain
opaque, although recognized necessary bounds can still prove impossibility.

`analysis.Compare` reports backward (old accepted payloads remain accepted by
new) and forward inclusion independently. Recognized numeric source constraints
form a conservative superset; inclusion is proved only into a fully recognized
target interval. A reported break requires an actual candidate validated against
both complete contracts. Identical source and target selections prove identity.
Reports omit candidate payloads and include content-bound comparison fingerprints.

These are logical payload-set proofs with sufficient evaluation resources, not
proofs of matching runtime costs, native wire compatibility, HTTP context or Java
ABI compatibility. Generic/structural/recursive proofs, richer arithmetic and
native constraints remain required analysis work. Unknown results must remain
unknown at release-policy boundaries. Explicit proof limits on numeric literals
avoid expanding unbounded exponents merely to discover constraints.
