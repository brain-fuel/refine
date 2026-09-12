# Native Avro JSON validation

`Project.ValidateAvroJSON` checks native rules only.
`Project.DecodeAndValidateAvroJSON` additionally decodes exact `value.Data` and
runs the selected Refine predicates. Both accept `AvroPayloadLimits`; the latter
also accepts `validation.Limits`. Neither performs I/O or reader-schema resolution.
Generated Java adapters support reader resolution separately.

This is [Avro JSON encoding](https://avro.apache.org/docs/1.12.0/specification/#json-encoding),
not the ordinary JSON representation of the semantic Java model. Non-null unions
require one native type tag (the fullname for named types); null is unwrapped.
Bytes and fixed values use string code points 0–255, not base64. Record members
may be reordered, but every writer field is required even when it has a default.

JSON parsing rejects duplicate decoded keys and trailing data. A schema-guided
bounded transcode produces binary Avro, then uses the existing native binary
validator and, when requested, the checked exact decoder. JSON syntax-tree and
Avro datum value counts are separately capped by `Values`; input and transcoded
bytes are separately capped by `Bytes`. Depth and decoded string/byte lengths
are also bounded. Resource failures use `native.limit`, never an ordinary invalid
candidate result.

Integer inputs must be in-range integer tokens: `1.0` and `1e0` are rejected,
even though [Apache Java's decoder](https://github.com/apache/avro/blob/release-1.12.0/lang/java/avro/src/main/java/org/apache/avro/io/JsonDecoder.java)
also accepts some integral floating tokens. Float/double inputs use their native
binary precision; overflow and non-finite JSON forms reject. Byte strings outside
0–255 and unpaired string surrogates reject instead of silently replacing units.
These strict input checks are not claims of accepting every permissive ecosystem
decoder extension. Native binary NaN/infinity handling remains unchanged.

The seeded integer property checks exact binary agreement with Hamba; a single
Apache Avro 1.12 Java oracle harness compares exact decoded results for numeric,
bytes/fixed, enum, array, union and recursive named-record inputs. Go tables also
cover map encoding, logical-type rejection, malformed tags, defaults, and limits.
