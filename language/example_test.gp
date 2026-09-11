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

func ExampleProgram_ReadData() {
    program,err:=language.Compile("type Positive = Int where it > 0")
    if err!=nil{panic(err)}
    input,err:=value.TextFromUTF8("21")
    if err!=nil{panic(err)}
    payload,report:=program.ReadData("Positive",input,validation.Limits{})
    fmt.Println(validation.StateName(report.State()))
    if validation.StateName(report.State())!="valid"{return}
    shown,err:=language.ShowDataWithoutValidation(payload,validation.Limits{})
    if err!=nil{panic(err)}
    text,err:=shown.UTF8();if err!=nil{panic(err)}
    fmt.Println(text)
    // Output:
    // valid
    // 21
}
