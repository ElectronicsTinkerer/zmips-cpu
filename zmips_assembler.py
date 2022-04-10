

import sys, getopt

from colorama import Fore

# Message Levels
INFO = 0
WARN = 10
ERROR = 20


def pmsg(level, msg, line=None, apass=False):
    if level == INFO:
        print(f"{Fore.CYAN}[INFO]{Fore.RESET} {msg}", end="")
    elif level == WARN:
        print(f"{Fore.YELLOW}[WARN]{Fore.RESET} {msg}", end="")
    elif level == ERROR:
        print(f"{Fore.RED}[ERROR]{Fore.RESET} {msg}", end="")

    if line:
        print(f" on line {line.line_num} of '{line.filename}':\n{line.line}")
        if apass:
            print(" Going for another pass ...")

    print()

    if level == ERROR:
        exit(-1)


def printhelp():
    print(" **** ZIPS Assembler ****")
    print("  Zach Baldwin Spring 2022")
    print("")
    print(" USAGE:")
    print("$ python zmips_assembler.py input_file.asm")
    print("")

if __name__ == "__main__":
    argv = sys.argv[1:]

    print(" **** ZIPS Assembler ****")
    print("  Zach Baldwin Spring 2022")
    print("")

    if len(sys.argv) == 1:
        printhelp()
        exit(-1)

    infile = ""
    try:
        infile = argv[0]
    except:
        printhelp()
        pmsg(ERROR, "I need an input file!")
    
    pmsg(INFO, f"Assembling {infile}")

    src = ""

    with open(infile, "r") as file:
        src= file.read()

    print(src)
