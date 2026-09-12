# OpenAPI request and response context

The `openapi` package validates Refine predicates over an HTTP operation's
typed request and response values. It is a pure execution boundary: it does not
send requests, read files, choose routes, authenticate callers, or fetch state.

Operation metadata is explicitly versioned with
`refine.openapi.operations/v1`. Every binding retains its exact OpenAPI
`operationId`, HTTP method, and path-template string. Compilation rejects
duplicate operation IDs, duplicate method/path pairs, malformed HTTP tokens or
path templates, unsupported response selectors, and unclosed or incompatible
types.

```go
schema := openapi.Schema{
    Version: openapi.SchemaVersion,
    Operations: []openapi.OperationBinding{{
        OperationID: "getWidget",
        Method: "GET",
        Path: "/widgets/{id}",
        RequestType: "GetRequest",
        Responses: []openapi.ResponseBinding{{
            Status: "200", ResponseType: "GetResponse",
            ContextType: "GetResponseContext",
        }},
    }},
}
contract, err := openapi.Compile(program, &schema)
```

## Source binding

The schema language stays ordinary Haskell/ML-style declarations. A request
type has exactly `parameters`, `headers`, and `body` fields. Applications choose
the parameter record's path/query/cookie grouping rather than having Refine
guess it. A response has exactly `headers` and `body` fields.

```text
type PathParameters = { id :: Int }
type RequestHeaders = { trace :: Maybe String }
type EmptyBody = {}
type GetRequest = {
  parameters :: PathParameters,
  headers :: RequestHeaders,
  body :: EmptyBody
}

type Widget = { id :: Int }
type ResponseHeaders = { etag :: String }
type GetResponse = { headers :: ResponseHeaders, body :: Widget }

type GetResponseContext = {
  request :: GetRequest,
  response :: GetResponse
} where it.response.body.id == it.request.parameters.id
    @code "response.request.id"
```

A context type must have exactly `request` and `response` fields. Those fields
must directly reference the selected named request and response types, or reach
them through transparent named aliases. This check prevents a context predicate
from validating an unrelated response shape and accidentally bypassing the
selected response refinements. Inline structural roots and generic roots are
rejected in this first metadata version.

Metadata is bounded to 4,096 operations, 1,024 response bindings per
operation, and 4,096 responses overall. The Java facade currently accepts at
most 256 total response bindings and rejects larger generation atomically,
rather than emitting a class that can exceed JVM initialization limits.

## Validation

`ValidateRequest` accepts typed `Request{Parameters, Headers, Body}` data.
`ValidateResponse` accepts typed `Response{Headers, Body}` data plus the
original request when its selected response declares a context type. Exact
three-digit response bindings take priority over a class binding such as
`2XX`, which takes priority over `default`.

When a context-bound response has no original request, the response is still
validated independently. A valid response produces an indeterminate report
with `openapi.request_context.missing`. A conclusively invalid response remains
invalid while retaining the missing-context diagnostic and `Incomplete=true`.
Normal validating callers must reject both states. Supplying a request validates
the combined context once, including the request, response, and cross-value
predicates under the caller's deterministic `validation.Limits`.

Unknown operation IDs, malformed runtime statuses, and statuses without a
binding are typed API errors; they are not presented as proof about payload
validity. Returned metadata and diagnostics are immutable caller-owned copies.

`java.GenerateOpenAPIContext` emits the same checked targets and selection
rules as Java 25 `Request` and `Response` records with `validateRequest` and
`validateResponse` entry points. Its public operation descriptors retain the
method and path for later project/OpenAPI wiring. It generates no HTTP client,
server, router, or serde layer.

## Versioned native and project integration

`native.WireMetadata.OpenAPI` carries this schema in a native project bundle
and in refined-schema annotations. Ingest, edited-source replacement, bundle
parsing, and refined export all recompile the bindings against the checked
Refine types. Metadata is defensively copied, and an incompatible source edit
or conflicting configured/annotated schema is rejected before producing an
updated project. The exact native bundle bytes and configured wire policy are
part of release comparison identity, so an operation ID, method, path, type, or
response-binding change cannot reuse an earlier content-bound override.

`project.Generate` automatically emits `RefineOpenAPIOperations.java` when a
contract's versioned wire metadata contains operation bindings. The facade and
models share the same generated contract/runtime sources; generation requires
duplicate paths to have byte-identical content and otherwise fails with no
partial bundle. For a native contract, operation metadata must live inside the
native bundle. A `refine.project.json` wire override—even one containing only
OpenAPI metadata—is rejected instead of being ignored.

When a native OpenAPI project carries checked `NativeBindings`, project
generation instead emits a composed semantic-JSON facade. `ParameterJSON`,
`HeaderJSON`, and `MediaJSON` values are already-decoded JSON values; the facade
does not parse HTTP path, query, cookie, header, or media framing. Their byte
arrays and containing lists are snapshotted behind fixed per-value and part
caps. Every raw part is first parsed as exactly one bounded JSON value with
strict duplicate detection. A generated wrapper schema then references the
immutable operation index's trusted Schema Object locations and validates all
parts in one native request. This gives the operation one aggregate byte/node
budget and, for pattern-bearing schemas, one aggregate `RegexLimits` deadline
and evaluation budget rather than resetting limits per part. Runtime callers
never supply a schema URI or pointer.

Only after native validation succeeds does the facade assemble the selected
named request or response, perform canonical structural decoding with generated
Jackson codecs, and execute the full Refine request, response, or context
contract. Exact status has priority over class and then `default`. Successful
request validation returns an immutable, unforgeable `ValidatedRequest` tied to
that facade instance, generated project fingerprint, and operation ID. A
foreign token is rejected. A context response without a token remains
indeterminate with `openapi.request_context.missing`; it is never treated as
valid. Native `Limits` controls the aggregate wrapper parser (including nodes),
the facade's tighten-only `Limits` controls aggregate semantic parts/bytes, and
`Budget.Limits` controls Refine evaluation. Syntax, native validation,
structural decoding, and predicates are not bypassed or converted into one
another's outcomes.

Operation-aware native exports include the complete checked module explanation
alongside a deterministic rendering of every operation ID, method, path,
status, request type, response type, and context type. This deliberately
includes context declarations that are not reachable from the selected payload
root, including their predicates and author-defined messages. The explanation
also states that missing required original-request context is indeterminate.
Because an ordinary native schema does not structurally enforce these bindings,
ordinary export records an explicit loss and requires
`AllowDocumentedLoss=true`; refined export embeds the same explanation and the
versioned metadata.
