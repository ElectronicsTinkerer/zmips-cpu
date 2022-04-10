; Test data file
    nop
    LI #0
    OR r0, r0, r0, ZCN ; Clear status flags
    LI #-1
    MOV r1, r0
    LI #9
    MOV r2, r0
    MOV r0, r1
:loop_start
    FFL C              ; Set carry
    SUB r1, r1, r0
    SW r1, r1          ; mem[r1] = r1
    CMP rs, rt, Z      ; Count == 9?
    BFC Z, loop_start  ; No, keep going

    FFL C              ; Set carry

    SUB r1, r1, r0
    MOV r3, r0
    LI #$a5            ; Test Load/Store pipeline forwarding
    SW r1, r0          ; mem[r1] = r0
    FFL C              ; Set carry
    SUB r1, r1, r3
    SW r1, r30         ; mem[r1] = r30 -> Test reading of PC shadow reg
    JPL $64            ; Checking to see if r30 is set by jump (should be $60 since that is the next instruction address)
    SW r1, r3          ; mem[r1] = r3 -> This should be skipped

    SW r1, r30         ; mem[r1] = r30 -> Test reading of PC shadow reg
    JPL $68            ; Spin
