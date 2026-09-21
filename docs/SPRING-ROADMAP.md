# Spring integration priorities

This is a proposed roadmap, not a list of features already shipped. It starts
from the Maven 0.3.0 distribution: JVM ingestion and generation, versioned models,
validated JSON/Avro adapters, generated property suites, and Google formatting.
Offscript demonstrates component imports and a handwritten HTTP client.

## Packaging recommendation

Keep compiler/import/ownership logic in `refine-maven-plugin` and add optional
Spring generation targets there. Publish a `refine-spring-boot-starter` backed by
an auto-configuration module for runtime integration. Add an optional Kafka
starter separately so HTTP applications do not acquire Kafka dependencies.

A Maven plugin runs during the build; it cannot by itself configure application
runtime converters, error handling, or consumer recovery. A separate
`refine-spring-boot-maven-plugin` is useful only if it supplies Boot-specific
scaffolding/verification goals; it should delegate to the same engine rather than
fork ingestion or generation. Proposed artifact names here are not published.

## P0: Trustworthy generated tests

Implemented in Maven `0.4.0`; `0.3.0` contains the earlier generator. See
[generated test evidence](GENERATED-TESTS.md#execution-evidence-and-coverage-limits)
for the reporting contract and its limits. The reusable consumer mutation harness
also lives in Refine, as the Maven `refine:mutate` goal; Offscript supplies its
acceptance-fixture configuration. See [mutation verification](MUTATION-TESTING.md).

This is the prerequisite for every Spring milestone below. A green generated
suite must describe executed evidence rather than imply coverage from helper
names or successful no-ops.

- Omit inapplicable codec checks and their call sites; never emit constant-pass
  substitutes for a missing codec.
- Identify executed properties and examples, actual evaluated case counts, replay
  mode, and explicit coverage gaps. A helper's presence is not execution evidence.
- Report native-schema rejection separately from refinement rejection. Do not
  describe valid-only round trips as negative-path coverage.
- Fail if a required property has no cases, exhausts its generation budget, throws,
  or cannot execute. A coverage gap must never be reported as a passing property.
- Exercise deliberately broken model validators and JSON/Avro codecs and require
  the relevant generated suite to fail; keep these mutations in the test harness.

Done when: generated payload and OpenAPI operation suites report their actual
execution, format-inapplicable helpers are absent, exhaustion/zero-execution
failures are covered, and executable mutation tests distinguish the healthy
implementation from broken validators/codecs. Offscript's JSON-only contracts
must show no Avro checks and must explicitly disclose missing negative coverage.

## P1: Establish the supported platform and executable acceptance fixture

Start with Java 25, Spring Boot 4, and Jackson 3, matching today's generated code
and Offscript. Publish exact tested versions and a dependency BOM. Java 21 and
Boot 3/Jackson 2 require an explicit compatibility project; do not imply that
changing a Maven compiler property makes current artifacts compatible.

Create a checked-in sample with an HTTP client, MVC server, and Kafka event
boundary, using pinned specs and local test servers/brokers. Every subsequent
milestone must pass from a fresh Maven repository with no Go installed. Keep the
compiler out of the deployed application's dependency tree. Test generated
property suites through normal Maven test execution, without requiring users to
copy the current launcher setup by hand.

Done when: a documented Java/Maven-only command builds and tests the fixture,
and dependency assertions prove the engine/formatter are build-only dependencies.

## P2: Make import plus refinement a single reproducible build declaration

Add an `imports` declaration naming input, origin format, resource identity,
payload selector or operation selection, family/version, and refinement source.
Support root JSON Schema, Avro, and full OpenAPI operations, not only components.
Include OpenAPI JSON/YAML fixtures and inline as well as referenced schemas.
Expose the engine's explicit external-resource map in Maven. Keep fetching in a
separate explicit update goal with URI/digest pinning; ordinary builds must not
silently fetch changing remote references.

Expose bundle source extraction and checked update through Maven, or provide an
equivalent declarative refinement workflow. An edited predicate must retain the
original native constraints and wire metadata. Reimport must detect conflicts
with existing refinements rather than erase them. Give unsupported constructs
actionable file/pointer diagnostics; do not silently approximate them.

Done when: one declaration imports a spec, applies a business predicate absent
from it, and generates code; tests reject both native-schema violations and
predicate violations, and reimport preserves the predicate or reports a conflict.

## P3: Ship a Spring Boot runtime starter

Generate discoverable contract metadata and auto-register contract JSON modules
with the appropriate MVC/client converters. Give modules stable, distinct
family/version identities: the current generated Country and Holiday modules
both declare the name `RefineJSONModule`, while Offscript uses separate mappers.
Test multiple families and versions on one mapper. Avoid replacing application-wide
mapper configuration. Preserve strict duplicate-key, trailing-data, and parser
size/depth checks: registering a Jackson module alone is not sufficient to impose
all parser limits on an existing mapper.

Provide a stable structured violation API and a Jakarta Validation bridge for
`@Valid` where appropriate. Map invalid inbound payloads to a configurable 400
or 422 `ProblemDetail`, upstream contract failures to a distinct client failure,
and invalid application responses to a server error before bytes are committed.
Keep invalid and indeterminate validation distinguishable internally; neither
should be accepted. Do not include secrets or entire payloads in error bodies.

Done when: a controller with generated request/response types works with the
starter and no manual mapper; MockMvc tests exercise native, structural,
refinement, and parser-limit failures as well as successful round trips.

## P4: Generate OpenAPI HTTP clients

Generate typed Spring HTTP service interfaces (`@HttpExchange` and friends) plus
the binding needed for validated codecs. Start with synchronous `RestClient`.
Use operation IDs, parameter locations, style/explode, request bodies, content
types, response statuses, and declared security schemes. Preserve optional versus
nullable semantics and model non-success responses explicitly. Fail generation
for unsupported bindings rather than generating plausible but incorrect calls.

Let Spring configuration provide base URLs, credentials, timeouts, observations,
and optional retry policy. Do not infer retries for non-idempotent operations.

Done when: Offscript's handwritten request construction and decoding can be
replaced with a generated Nager.Date service, tested against recorded/local
responses including query/path encoding, errors, and invalid upstream payloads.

## P5: Generate Spring MVC server bindings

Generate controller adapters and service interfaces, leaving business
implementations in handwritten files. Reuse the checked OpenAPI operation model
for parameter/header/body validation and response selection. Enforce
request-to-response predicates with the original request context available.
Validate responses before HTTP output starts. Surface auth integration points;
an OpenAPI security declaration alone is not an authorization implementation.

Done when: implementing the generated service interface exposes an endpoint and
integration tests verify request bindings, statuses/content types, error responses,
and cross-request/response refinements. Regeneration never overwrites business code.

## P6: Add Kafka producer/consumer integration

Provide JSON and Avro Kafka `Serializer`/`Deserializer` implementations around
the generated validated codecs, plus Spring configuration. Add explicit key/value
contracts and configuration for topic, group, tombstones, and validation limits.
Support writer-schema lookup/evolution and the selected schema registry's actual
wire framing; raw Avro encoding alone is not registry integration.

Integrate invalid-message handling with Spring Kafka recovery/dead-letter handling
and make acknowledgement, replay, ordering, and transaction behavior explicit.
Use AsyncAPI or application configuration for topology that Avro/JSON Schema
does not describe. Test against an actual broker/registry fixture.

Done when: producer and consumer need no handwritten codecs, invalid messages
follow a tested recovery path, tombstones have deliberate semantics, and old/new
writer schemas interoperate according to the selected compatibility policy.

## P7: Broaden adoption and production confidence

Add Java 21/Boot 3 compatibility if demanded, WebFlux after the blocking path is
stable, and Spring AOT/native-image hints with actual native build tests. Add
contract compatibility checks to `verify`, reproducibility checks, upgrade
fixtures, and observations with bounded labels and no payload leakage.

Done when: each advertised platform has its own CI coverage and an upgrade test;
unsupported platform combinations fail with useful diagnostics.

## Suggested first delivery

Complete P0 before any Spring integration work. Deliver P1-P3 as the first Spring integration release, using an inbound MVC
boundary in the fixture to prove the starter. Follow with P4 to remove Offscript's
manual HTTP glue, then P5 and P6. This makes imports and refinements useful in
existing Spring applications before attempting full application scaffolding.

## Primary references

- [Spring Boot custom auto-configuration and starters](https://docs.spring.io/spring-boot/reference/features/developing-auto-configuration.html)
- [Spring Boot HTTP service clients](https://docs.spring.io/spring-boot/reference/io/rest-client.html)
- [Spring Framework REST clients](https://docs.spring.io/spring-framework/reference/integration/rest-clients.html)
- [Spring MVC error responses](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-ann-rest-exceptions.html)
- [Spring Kafka serializers and deserializers](https://docs.spring.io/spring-kafka/reference/kafka/serdes.html)
- [Confluent schema registry serialization formats](https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/index.html)
