# Native artifact workflows

Native artifact commands emit their result on stdout and do not overwrite input
files. A Refine bundle contains the exact original resources, editable checked
source, root selector, and wire metadata; it is not an ordinary schema export.

```sh
refine native ingest --type Person json-schema person.schema.json > person.refined.json
refine native source person.refined.json > person.refine
refine native update person.refined.json person.refine > person.updated.refined.json
refine native original person.updated.refined.json > person.original.schema.json
```

The ingest formats are `json-schema`, `avro`, and `openapi`. OpenAPI selection
uses `--pointer /components/schemas/Person` and `--type Person`; a default
component pointer is derived from the selected type name. `--resource` supplies
an absolute URI identifying the input; it does not fetch that URI.

`--resources dependencies.json` accepts an explicit array of native resource
objects, each with `URI` and `Source`. The main input is appended after these
dependencies (important for Avro name-definition order). Duplicate IDs, missing
references, or resources that require network/filesystem resolution reject.
Only one explicit input may be `-` for stdin. Inputs are bounded to 16 MiB each.

`source` exposes the checked editable language. `update` checks its replacement
and retains the original native sidecar and metadata; invalid updates emit no
partial bundle. `original` means exactly the immutable original resource, not
an export of newly added rules. It deliberately makes no claim to carry edits.

JSON Schema and supported OpenAPI projects validate both layers by default:

```sh
refine native validate-payload --json person.refined.json payload.json
```

The native schema is enforced before exact type-directed decoding and evaluation
of the editable Refine predicates. Invalid or indeterminate results fail the
command. `--total-steps` and `--clause-steps` optionally cap refinement evaluation;
zero uses the standard defaults. An unsupported wire representation fails
closed. The result includes the complete refinement report but not the payload.

The explicit command below tests **only native constraints**, including supported
canonical native-unit edits, without evaluating additional Refine predicates:

```sh
refine native validate-payload --native-only --json person.refined.json payload.json
```

For Avro, the default input is one binary datum, not a container file. Both
native and refined validation run by default. Select Avro's JSON encoding
explicitly with `--avro-json`; `--json` independently selects the report format:

```sh
refine native validate-payload --avro-json --json event.refined.json event.json
```

The encoding is never guessed. `--avro-json` with a non-Avro bundle is a usage
error. Both Avro paths use the selected writer schema; they do not perform
reader-schema evolution. Generated Java adapters provide reader resolution.
With `--native-only`, the JSON report includes `nativeOnly: true`, and the
summary states that added predicates were not evaluated. Native-oracle failure
details are redacted to avoid accidental payload/example/default leakage.
