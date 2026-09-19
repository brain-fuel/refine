package language

// OpenAPIDeclaration defines a complete API in the same source as its checked
// request/response types. It is not a payload root or an executable predicate.
type OpenAPIDeclaration struct {
    Version string
    Title string
    APIVersion string
    Operations []OpenAPIOperationDeclaration
    At Span
}
type OpenAPIOperationDeclaration struct {
    OperationID string
    Method string
    Path string
    Request OpenAPIRequestDeclaration
    Responses []OpenAPIResponseDeclaration
    At Span
}
type OpenAPIRequestDeclaration struct {
    TypeName string
    Parameters []OpenAPIParameterDeclaration
    Body *OpenAPIBodyDeclaration
    At Span
}
type OpenAPIParameterDeclaration struct {
    In string
    Name string
    FieldPath []string
    // Nil infers native presence from the checked field type. A nonnil value
    // is an explicit required/optional assertion, not permission to drop data.
    Required *bool
    At Span
}
type OpenAPIBodyDeclaration struct {
    MediaType string
    FieldPath []string
    Required *bool
    At Span
}
type OpenAPIResponseDeclaration struct {
    Status string
    TypeName string
    Description string
    Headers []OpenAPIHeaderDeclaration
    Body *OpenAPIBodyDeclaration
    ContextType string
    At Span
}
type OpenAPIHeaderDeclaration struct {
    Name string
    FieldPath []string
    Required *bool
    At Span
}

func copyOpenAPIRequired(input *bool) *bool { if input == nil { return nil }; copy := *input; return &copy }
func copyOpenAPIBody(input *OpenAPIBodyDeclaration) *OpenAPIBodyDeclaration {
    if input == nil { return nil }
    copy := *input; copy.FieldPath = append([]string(nil), input.FieldPath...); copy.Required = copyOpenAPIRequired(input.Required); return &copy
}
func copyOpenAPI(input *OpenAPIDeclaration) *OpenAPIDeclaration {
    if input == nil { return nil }
    copy := *input
    copy.Operations = append([]OpenAPIOperationDeclaration(nil), input.Operations...)
    for i := range copy.Operations {
        operation := &copy.Operations[i]
        operation.Request.Parameters = append([]OpenAPIParameterDeclaration(nil), operation.Request.Parameters...)
        for j := range operation.Request.Parameters { item := &operation.Request.Parameters[j]; item.FieldPath = append([]string(nil), item.FieldPath...); item.Required = copyOpenAPIRequired(item.Required) }
        operation.Request.Body = copyOpenAPIBody(operation.Request.Body)
        operation.Responses = append([]OpenAPIResponseDeclaration(nil), operation.Responses...)
        for j := range operation.Responses {
            response := &operation.Responses[j]
            response.Headers = append([]OpenAPIHeaderDeclaration(nil), response.Headers...)
            for k := range response.Headers { item := &response.Headers[k]; item.FieldPath = append([]string(nil), item.FieldPath...); item.Required = copyOpenAPIRequired(item.Required) }
            response.Body = copyOpenAPIBody(response.Body)
        }
    }
    return &copy
}

// OpenAPI returns a detached source declaration. Native assembly separately
// validates protocol, field binding, and wire-representation semantics.
func (p *Program) OpenAPI() *OpenAPIDeclaration {
    if p == nil || p.module == nil { return nil }
    return copyOpenAPI(p.module.OpenAPI)
}
