package native

import (
    "fmt"
    "strings"

    "goforge.dev/refine/language"
)

// appendNativeSourceDeclarations preserves the exact owned release footer at
// EOF. Generated declarations change the contract, not the existing approval
// hashes, and must never grant source metadata native-bundle authority.
func appendNativeSourceDeclarations(source,addition string)(string,error){
    if addition==""{return source,nil}
    base,_,present,err:=language.SplitReleasePolicyFooter(source);if err!=nil{return "",err}
    footer:="";if present{footer=source[len(base):]}
    if len(source)>16<<20||len(addition)>(16<<20)-len(source)-3{return "",fmt.Errorf("native source composition exceeds the 16 MiB language source limit")}
    if base!=""&&!strings.HasSuffix(base,"\n"){base+="\n"}
    return base+"\n"+addition+"\n"+footer,nil
}
