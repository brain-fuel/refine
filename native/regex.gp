package native

import (
    "time"

    "github.com/dlclark/regexp2"
    "github.com/getkin/kin-openapi/openapi3"
    jsonoracle "github.com/santhosh-tekuri/jsonschema/v6"
)

// regexp2 is substantially closer to JSON Schema/OpenAPI's ECMA-262 pattern
// syntax than Go regexp. It is still an implementation oracle, not a proof of
// parity with every edition/host behavior of ECMAScript RegExp.
type ecmaRegexp struct { compiled *regexp2.Regexp }
func (r *ecmaRegexp) MatchString(input string)bool{matched,err:=r.compiled.MatchString(input);return err==nil&&matched}
func (r *ecmaRegexp) String()string{return r.compiled.String()}

func compileECMA(source string)(*ecmaRegexp,error){compiled,err:=regexp2.Compile(source,regexp2.ECMAScript);if err!=nil{return nil,err};compiled.MatchTimeout=250*time.Millisecond;return &ecmaRegexp{compiled:compiled},nil}
func jsonRegexp(source string)(jsonoracle.Regexp,error){return compileECMA(source)}
func openAPIRegexp(source string)(openapi3.RegexMatcher,error){return compileECMA(source)}
