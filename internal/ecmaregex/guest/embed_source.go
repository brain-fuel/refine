//go:build ignore

// Command embed_source converts one fixed JavaScript source into a C byte array.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: embed_source input.js output.inc")
		os.Exit(2)
	}
	input, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	output, err := os.Create(os.Args[2])
	if err != nil {
		panic(err)
	}
	defer output.Close()
	fmt.Fprintln(output, "unsigned char regexpp_init_js[] = {")
	for index, value := range input {
		if index%12 == 0 {
			fmt.Fprint(output, "  ")
		}
		if index+1 == len(input) {
			fmt.Fprintf(output, "0x%02x", value)
		} else {
			fmt.Fprintf(output, "0x%02x,", value)
		}
		if index%12 == 11 || index+1 == len(input) {
			fmt.Fprintln(output)
		} else {
			fmt.Fprint(output, " ")
		}
	}
	fmt.Fprintln(output, "};")
	fmt.Fprintf(output, "unsigned int regexpp_init_js_len = %d;\n", len(input))
}
