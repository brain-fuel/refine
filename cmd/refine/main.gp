package main

import (
    "os"
    "goforge.dev/refine/cli"
)

func main() { os.Exit(cli.Run(os.Args[1:],os.Stdin,os.Stdout,os.Stderr)) }
