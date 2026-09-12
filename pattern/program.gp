package pattern

import (
    "regexp/syntax"
    "unicode"
)

// InstructionProfile versions the execution semantics, not the source syntax
// parser or its optimization choices. This development snapshot is not a native
// schema format or an unversioned cross-toolchain serialization guarantee.
const InstructionProfile = "refine.regex.instructions.v1"

type Opcode enum { Alt; AltMatch; Capture; EmptyWidth; Accept; Fail; Nop; Rune; Rune1; RuneAny; RuneAnyNotNL }
type Instruction struct { Opcode Opcode; Out uint32; Arg uint32; Runes []rune }
type Program struct { Profile string; UnicodeVersion string; Start int; Instructions []Instruction }

// Adding a second enum makes GoPlus qualify its generated fold helpers. Retain
// the original Mode helper API for existing plain-Go consumers.
func Fold[R any](mode Mode,cases ModeCases[R])R { return ModeFold(mode,cases) }

func OpcodeName(op Opcode)string {
    match op {
    case Alt():return "ALT";case AltMatch():return "ALT_MATCH";case Capture():return "CAPTURE"
    case EmptyWidth():return "EMPTY_WIDTH";case Accept():return "MATCH";case Fail():return "FAIL";case Nop():return "NOP"
    case Rune():return "RUNE";case Rune1():return "RUNE1";case RuneAny():return "RUNE_ANY";case RuneAnyNotNL():return "RUNE_ANY_NOT_NL"
    }
}

// Program returns a detached instruction snapshot for other runtime backends.
// Mutating the snapshot, including any rune range, cannot affect this Regex or
// any subsequent snapshot. Character folding uses the declared Unicode version.
func (r Regex) Program()(Program,error) {
    if r.program==nil{return Program{},&Error{Code:"regex.uncompiled",Message:"regular expression has not been compiled"}}
    result:=Program{Profile:InstructionProfile,UnicodeVersion:unicode.Version,Start:r.program.Start,Instructions:make([]Instruction,len(r.program.Inst))}
    for i,instruction:=range r.program.Inst {
        var op Opcode
        switch instruction.Op {
        case syntax.InstAlt:op=Alt();case syntax.InstAltMatch:op=AltMatch();case syntax.InstCapture:op=Capture()
        case syntax.InstEmptyWidth:op=EmptyWidth();case syntax.InstMatch:op=Accept();case syntax.InstFail:op=Fail();case syntax.InstNop:op=Nop()
        case syntax.InstRune:op=Rune();case syntax.InstRune1:op=Rune1();case syntax.InstRuneAny:op=RuneAny();case syntax.InstRuneAnyNotNL:op=RuneAnyNotNL()
        default:return Program{},&Error{Code:"regex.program",Message:"unsupported regular expression instruction"}
        }
        result.Instructions[i]=Instruction{Opcode:op,Out:instruction.Out,Arg:instruction.Arg,Runes:append([]rune(nil),instruction.Rune...)}
    }
    return result,nil
}
