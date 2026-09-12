# Worked contracts

These examples are executable Refine source, not promises that every native
backend can represent every example's wire shape. The GoPlus test suite checks
positive and negative payloads and English generation for each contract.

| File | Root | Contract illustrated |
| --- | --- | --- |
| `booking.refine` | `Booking` | Ordered timestamps and explicitly fallible civil duration |
| `invoice.refine` | `Invoice` | Exact prices, ties-to-even per-line cents, whole-record totals |
| `batch.refine` | `Batch` | Unique identifiers and references within a collection |
| `deployment.refine` | `Deployment` | Missing dependencies and recursive cycle detection |
| `payment.refine` | `Payment` | Named alternatives and alternative-specific constraints |
| `expression.refine` | `Expression` | Recursive expression-tree type consistency |
| `polygon.refine` | `Polygon` | Exact geometry, closure, area, and crossing checks |
| `evolution/` | `Age` | A backward-compatible widening with a forward counterexample |

Run from the repository root:

```sh
go run ./cmd/refine typecheck examples/invoice.refine
go run ./cmd/refine explain examples/invoice.refine
printf '%s\n' '{lines = [{price = 1.005, quantity = 1}], totalCents = 100}' | \
  go run ./cmd/refine validate examples/invoice.refine Invoice -
go run ./cmd/refine compare-payload \
  examples/evolution/v1.0.0.refine Age examples/evolution/SNAPSHOT.refine Age
go test ./examples
```

`validate` takes canonical Refine payload notation, not JSON wire data. Named
unions do not implicitly add JSON discriminator fields: those require explicit
wire metadata when generating JSON serde. The polygon contract is an authored
example, not a substitute for a general geospatial specification: it uses a
planar coordinate system and excludes repeated non-closing vertices.

Generated English includes the algorithms behind named helper functions and
the programmer's custom messages. Editing a message does not change a predicate.
