package language_test

import (
    "fmt"
    "goforge.dev/refine/language"
    "goforge.dev/refine/validation"
    "goforge.dev/refine/value"
)

func ExampleProgram_ValidateData() {
    program,err:=language.Compile(`
type Person = { age :: Int where it >= 0 }
type Child = Person
  where it.age < 18
    @code "person.child_age"
    @message "Age must be less than 18"
`)
    if err!=nil{panic(err)}
    payload,err:=value.Record([]value.DataField{{Name:"age",Value:value.OfNumber(value.Integer(21))}})
    if err!=nil{panic(err)}
    report:=program.ValidateData("Child",payload,validation.Limits{})
    fmt.Println(validation.StateName(report.State()))
    for _,diagnostic:=range report.Diagnostics(){fmt.Println(diagnostic.Code+": "+diagnostic.Message)}
    // Output:
    // invalid
    // person.child_age: Age must be less than 18
}
