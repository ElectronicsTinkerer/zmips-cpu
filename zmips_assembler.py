# Assembler for ZMIPS ISA
#
# MIF file format: https://www.intel.com/content/www/us/en/programmable/quartushelp/13.0/mergedProjects/reference/glossary/def_mif.htm
#
# (C) Zach Baldwin Spring 2022
# Course: ECSE 314
#
# Updated:
# 2023-02-01 -> EQUates not evaluated on R2FS inst types
# 2023-02-13 -> Add @addr org relocation syntax


import re
import sys
import os
import traceback
from colorama import Fore
from enum import Enum

# Column to place listing source in output
LISTING_COMMENT_COL = 42

class ListingLine:
    def __init__(self, src, pc, fbin="", rbin="", nocode=False):
        self.src = src   # Source line
        self.pc = pc     # Program Counter location of the instruction
        self.fbin = fbin # Formatted binary
        self.rbin = rbin # Raw binary
        self.nocode = nocode # True on lines without an instruction (comments, labels)

# Flags
FLAG_BITS = {"Z":4,"C":2,"N":1,"X":0}

# Opcodes
CONDITIONCODES = {"Z":0, "C":1, "N":2, "A":3}

class OpType(Enum):
    RFMT = 0, # R-format
    IFRT = 1, # I-format load (R-type)
    IFBR = 2, # I-format branch
    JFMT = 3  # J-format
    RAW  = 4  # .WORD directive


class MneType(Enum):
    R3F  = 0,  # rd, rs, rt, [flags]
    R2FC = 1,  # rs, rt, [flags]
    R2FN = 2,  # rd, rs, [flags]
    R2FS = 3,  # rd, rs, shamt, [flags]
    R2FD = 4,  # rd, rs
    R2FT = 5,  # rs, rt
    ADDR = 6,  # label/address
    IMMD = 7,  # se_immd
    BADR = 8,  # flag, label/address
    FLAG = 9,  # flag
    JREG = 10, # rs
    NOP  = 11  # <nothing>

class Opcode:
    def __init__(self, mne:str, opcode:int, op_type:OpType, mne_type:MneType, shamt=0, funct=0, rs=0, rt=0, rd=0, immd=0, jaddr=0, flags=0, cc=0):
        self.mne = mne
        self.opcode = opcode
        self.op_type = op_type
        self.mne_type = mne_type
        self.shamt = shamt
        self.funct = funct
        self.rs = rs
        self.rt = rt
        self.rd = rd
        self.immd = immd
        self.jaddr = jaddr
        self.flags = flags # Individual bits
        self.cc = cc # Condition Code

OPS = {
    "NOP" : Opcode("NOP", 0b000000, OpType.RFMT, MneType.NOP,  funct = 0b000000),
    "ADD" : Opcode("ADD", 0b000100, OpType.RFMT, MneType.R3F,  funct = 0b000000),
    "SUB" : Opcode("SUB", 0b000100, OpType.RFMT, MneType.R3F,  funct = 0b001000),
    "CMP" : Opcode("CMP", 0b000000, OpType.RFMT, MneType.R2FC, funct = 0b001000),
    "AND" : Opcode("AND", 0b000100, OpType.RFMT, MneType.R3F,  funct = 0b010000),
    "OR"  : Opcode("OR",  0b000100, OpType.RFMT, MneType.R3F,  funct = 0b100000),
    "EOR" : Opcode("EOR", 0b000100, OpType.RFMT, MneType.R3F,  funct = 0b110000),
    "SLL" : Opcode("SLL", 0b000101, OpType.RFMT, MneType.R2FS, funct = 0b010000),
    "SRL" : Opcode("SRL", 0b000101, OpType.RFMT, MneType.R2FS, funct = 0b110000),
    "SRA" : Opcode("SRA", 0b000101, OpType.RFMT, MneType.R2FS, funct = 0b100000),
    "MOV" : Opcode("MOV", 0b000101, OpType.RFMT, MneType.R2FN, funct = 0b000000),
    "JMP" : Opcode("JMP", 0b000000, OpType.RFMT, MneType.JREG, funct = 0b111111),
    "LW"  : Opcode("LW",  0b001101, OpType.RFMT, MneType.R2FD, funct = 0b000000),
    "SW"  : Opcode("SW",  0b001001, OpType.RFMT, MneType.R2FT, funct = 0b000000),
    "LI"  : Opcode("LI",  0b010101, OpType.IFRT, MneType.IMMD),
    "BFC" : Opcode("BFC", 0b100000, OpType.IFBR, MneType.BADR),
    "BFS" : Opcode("BFS", 0b101000, OpType.IFBR, MneType.BADR),
    "JPL" : Opcode("JPL", 0b110000, OpType.JFMT, MneType.ADDR),
    "FFL" : Opcode("FFL", 0b000011, OpType.RFMT, MneType.FLAG, funct = 0b000000),
    ".WORD" : Opcode(".WORD", 0,    OpType.RAW,  MneType.IMMD)
}

def op2bin(opcode:Opcode):
    if opcode.op_type == OpType.RFMT:
        return f"{opcode.opcode:06b}_{opcode.rs:05b}_{opcode.rt:05b}_{opcode.rd:05b}_{opcode.shamt:05b}_{(opcode.funct|opcode.flags):06b}"
    elif opcode.op_type == OpType.IFRT:
        return f"{opcode.opcode:06b}_{((1 << 26) - 1) & opcode.immd:026b}"
    elif opcode.op_type == OpType.IFBR:
        return f"{opcode.opcode|opcode.cc:06b}_{((1 << 26) - 1) & opcode.immd:026b}"
    elif opcode.op_type == OpType.JFMT:
        return f"11_{opcode.jaddr:030b}"
    elif opcode.op_type == OpType.RAW:
        return f"{opcode.immd:032b}"

# Get the register number from a string.
# Definitely could use some error handling
def getReg(reg_str):
    if len(reg_str) < 2:
        pmsg(ERROR, f"Unexpected designator '{reg_str}'", line_num)
    if reg_str[0].upper() != 'R' or not reg_str[1].isdigit():
        pmsg(ERROR, f"Expected register, got '{reg_str}'", line_num)
    i = int(reg_str[1:], base=10)
    if i < 0 or i > 31:
        pmsg(ERROR, f"Invalid register number '{reg_str}'", line_num)
    return i

# Message Levels
INFO = 0
WARN = 10
ERROR = 20

def pmsg(level, msg, line_num = -1):
    if level == INFO:
        print(f"{Fore.CYAN}[INFO]{Fore.RESET} {msg}", end="")
    elif level == WARN:
        print(f"{Fore.YELLOW}[WARN]{Fore.RESET} {msg}", end="")
    elif level == ERROR:
        print(f"{Fore.RED}[ERROR]{Fore.RESET} {msg}", end="")

    if line_num > 0:
        print(f" on line {line_num}", end="")

    print()

    if level == ERROR:
        exit(-1)


def parseorg(line):
    addr = line[1:]
    pc = 0
    if addr == '':
        pmsg(ERROR, "Encountered '@' without expression for address", line_num)
    else:
        try:
            val = eval(addr, globals(), labels) #Again, "definitely" "souper-dooper" secure
            if val < 0:
                pmsg(ERROR, "Encountered '@' with negative operand", line_num)
            else:
                pc = val
        except NameError:
            pmsg(ERROR, f"Unknown symbol in expression '{addr}'", line_num)
    return pc
            
        
def printhelp():
    print("")
    print(" USAGE:")
    print("$ python zmips_assembler.py input_file.asm outputfile")
    print("")

if __name__ == "__main__":
    argv = sys.argv[1:]

    print(" **** ZIPS Assembler ****")
    print(" (C) Zach Baldwin 2022 - 2023")
    print("")

    if len(sys.argv) != 3:
        printhelp()
        exit(-1)

    infile = ""
    try:
        infile = argv[0]
    except:
        printhelp()
        pmsg(ERROR, "I need an input file!")
    
    outfile = ""
    try:
        outfile = argv[1]
    except:
        printhelp()
        pmsg(ERROR, "I need an output file!")
    
    pmsg(INFO, f"Assembling {infile}")

    src = []

    with open(infile, "r") as file:
        for line in file.readlines():
            line = line.strip()
            src.append(line)

    pc = 0
    line_num = 0
    labels = {}

    # Resolve forward labels
    for line in src:
        line_num += 1
        line = line.strip()

        if len(line) < 1 or line.startswith("//") or line.startswith(";"):
            continue

        line = line.split(';')[0]
        line = line.split('//')[0]

        if line[0] == ':':
            parts = line.split(maxsplit=1)
            label = parts[0][1:].strip()
            if label == '':
                pmsg(WARN, "Ignoring empty label", line_num)
            elif label not in labels:
                labels[label] = pc << 2 # word size = 4 bytes
            else:
                pmsg(ERROR, f"Multiple define label '{label}'", line_num)
        elif line[0] == '=': #Can't forward resolve equates
            parts = line.split(maxsplit=1)
            equate = parts[0][1:].strip()
            if equate == '':
                pmsg(WARN, "Ignoring empty equate", line_num)
            elif equate not in labels:
                if len(parts) > 1:
                    try:
                        labels[equate] = eval(parts[1], globals(), labels) #Again, "definitely" secure
                    except NameError:
                        pmsg(ERROR, f"Unknown symbol in expression '{equate}'", line_num)
                else:
                    pmsg(ERROR, f"Encountered equate without value '{equate}'", line_num)
            else:
                pmsg(ERROR, f"Multiple define equate '{equate}'", line_num)
        elif line[0] == '@':
            parseorg(line)
        else:
            pc += 1

    listing:ListingLine = []
    line_num = 0
    pc = 0

    for line in src:

        line_num += 1

        line = line.strip()
            
        if len(line) < 2:
            continue

        # Ignore comments and labels
        if line.startswith(("//", ":", ";", "=")):
            listing.append(ListingLine(line, pc, nocode=True))
            continue

        if line.startswith(("@")):
            newpc = parseorg(line)
            while pc < newpc:
                opbin = "00000000"
                listing.append(ListingLine(
                    line,
                    pc,
                    f"{opbin}{' '*(40-len(opbin))}",
                    re.sub('_', '', opbin) # Remove '_'s from the line so it is just binary
                ))

                pc += 1
            continue


        subline = line
        if "//" in line:
            subline = line[:line.index("//")]
        if ";" in line:
            subline = line[:line.index(";")]

        # Separate opcode from arguments
        parts = subline.split(maxsplit=1)
        for i in range(len(parts)):
            parts[i] = parts[i].strip()

        # Split the arguments
        args = []
        if len(parts) > 1:
            args = parts[1].split(",")
            for i in range(len(args)):
                args[i] = args[i].strip()

        opcode = parts[0].upper()

        op:Opcode = None
        try:
            op = OPS[opcode]
        except KeyError as e:
            pmsg(ERROR, f"Unknown opcode {opcode}", line_num)
            print(traceback.format_exception())
            exit(-1)

        if op.mne_type == MneType.NOP:
            pass
        elif op.mne_type == MneType.FLAG:
            try:
                op.flags = 0
                for c in args[0]:
                    op.flags |= FLAG_BITS[c.upper()]
            except IndexError:
                pmsg(ERROR, f"Missing flag", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown flag", line_num)

        elif op.mne_type == MneType.JREG:
            try:
                op.rs = getReg(args[0])
            except IndexError:
                pmsg(ERROR, f"Expected address or label", line_num)

        elif op.mne_type == MneType.R2FD:
            try:
                op.rs = getReg(args[1])
                op.rd = getReg(args[0])
            except IndexError:
                pmsg(ERROR, f"Missing register", line_num)

        elif op.mne_type == MneType.R2FT:
            try:
                op.rt = getReg(args[1])
                op.rs = getReg(args[0])
            except IndexError:
                pmsg(ERROR, f"Missing register", line_num)

        elif op.mne_type == MneType.R2FC:
            try:
                op.rt = getReg(args[1])
                op.rs = getReg(args[0])

                op.flags = 0
                if len(args) > 2:
                    for c in args[2]:
                        op.flags |= FLAG_BITS[c.upper()]

            except IndexError:
                pmsg(ERROR, f"Missing register", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown flag", line_num)

        elif op.mne_type == MneType.R2FS:
            try:
                op.shamt = eval(args[2], globals(), labels)
                op.rs = getReg(args[1])
                op.rd = getReg(args[0])

                op.flags = 0
                if len(args) > 3:
                    for c in args[3]:
                        op.flags |= FLAG_BITS[c.upper()]

            except IndexError:
                pmsg(ERROR, f"Missing register or shift amount", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown flag", line_num)
            except ValueError:
                pmsg(ERROR, f"Expected integer, got: '{args[2]}'", line_num)

        elif op.mne_type == MneType.R2FN:
            try:
                op.rs = getReg(args[1])
                op.rd = getReg(args[0])

                op.flags = 0
                if len(args) > 2:
                    for c in args[2]:
                        op.flags |= FLAG_BITS[c.upper()]

            except IndexError:
                pmsg(ERROR, f"Missing register", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown flag", line_num)
                
        elif op.mne_type == MneType.R3F:
            try:
                op.rt = getReg(args[2])
                op.rs = getReg(args[1])
                op.rd = getReg(args[0])

                op.flags = 0
                if len(args) > 3:
                    for c in args[3]:
                        op.flags |= FLAG_BITS[c.upper()]

            except IndexError:
                pmsg(ERROR, f"Missing register", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown flag", line_num)

        elif op.mne_type == MneType.ADDR:
            try:
                # "Very Secure"
                op.jaddr = eval(args[0], globals(), labels) >> 2 # >> 2 since the immediate value is the word address, not the full address
            except SyntaxError:
                pmsg(ERROR, f"Syntax error", line_num)
            except IndexError:
                pmsg(ERROR, f"Expected target", line_num)
            except NameError:
                pmsg(ERROR, f"Unknown symbol in expression '{args[0]}'", line_num)
                
        elif op.mne_type == MneType.BADR:
            try:
                op.cc = CONDITIONCODES[args[0].upper()]
                # "Even more Very Secure"
                op.immd = (eval(args[1], globals(), labels) - (pc << 2) - 4) >> 2 # -4 since PC is the (current PC - 4) in the IF pipeline regs
            except SyntaxError:
                pmsg(ERROR, f"Syntax error", line_num)
            except IndexError:
                pmsg(ERROR, f"Expected flag and target or unknown flag", line_num)
            except KeyError:
                pmsg(ERROR, f"Unknown condition '{args[0]}'", line_num)
            except NameError:
                pmsg(ERROR, f"Unknown symbol in expression '{args[1]}'", line_num)

        elif op.mne_type == MneType.IMMD:
            try:
                # "Considerably Even more Very Secure"
                op.immd = eval(args[0], globals(), labels)
            except SyntaxError:
                pmsg(ERROR, f"Syntax error", line_num)
            except IndexError:
                pmsg(ERROR, f"Expected value", line_num)
            except NameError:
                pmsg(ERROR, f"Unknown symbol in expression '{args[0]}'", line_num)

        opbin = op2bin(op)
        listing.append(ListingLine(
            line,
            pc,
            f"{opbin}{' '*(40-len(opbin))}",
            re.sub('_', '', opbin) # Remove '_'s from the line so it is just binary
        ))

        pc += 1

        


    mif_output = ""
    mif_output += f"DEPTH = {pc}; -- Memory size in words\n"
    mif_output += f"WIDTH = 32; -- Data width in bits\n"
    mif_output += f"ADDRESS_RADIX = HEX;\n"
    mif_output += f"DATA_RADIX = BIN;\n"
    mif_output += f"CONTENT\n"
    mif_output += f"BEGIN\n"

    pc = 0
    for line in listing:
        if not line.nocode:
            line_start = f"{pc:4x} : {line.rbin}"
            mif_output += f"{line_start};{' '*(LISTING_COMMENT_COL-len(line_start))} -- {line.src}\n"
            pc += 1
        else:
            mif_output += f"{' '*(LISTING_COMMENT_COL-4)}  -- {line.src}\n"

    mif_output += f"END;\n"

    # Write results
    with open(f"{outfile}.mif", "w") as file:
        file.write(mif_output)

    # Write file for use in simulation
    with open(f"{outfile}.dat", "w") as file:
        for line in listing:
            file.write(f"{line.fbin}{' '*(LISTING_COMMENT_COL-len(line.fbin))} // {line.src}\n")

    # Write listing for user
    with open(f"{outfile}.lst", "w") as file:
        for line in listing:
            line_start = f"{line.pc*4:08x} : {line.fbin}"
            file.write(f"{line_start}{' '*(LISTING_COMMENT_COL-len(line_start))} -- {line.src}\n")

    pmsg(INFO, "Done")
