; Test data file
    nop
    nop
    nop
    li 0xc89e
    mov r1, r0
    li 0
    sw r0, r1
    lw r1, r0
    ffl X               ; Clear status flags
    jpl start
    jpl real_start
:start
    jmp R30
:real_start
    LI 0
    OR r0, r0, r0, ZCN ; Clear status flags
    LI 1
    MOV r1, r0
    LI 9
    MOV r2, r0
    ; MOV r0, r1
    li init_loop
    sll r0, r0, 0
    jmp r0
    li 0xaa55
    nop
    nop
:init_loop
    li 0
:loop_start
    FFL C              ; Clear carry
    ADD r1, r1, r0
    SW r1, r1          ; mem[r1] = r1
    CMP r2, r1, Z      ; Count == 9?
    BFC Z, loop_start  ; No, keep going

    FFL C              ; Set carry

    SUB r1, r1, r0
    MOV r3, r0
    LI 0xa5            ; Test Load/Store pipeline forwarding
    SW r1, r0          ; mem[r1] = r0
    FFL C              ; Set carry
    SUB r1, r1, r3
    SW r1, r30         ; mem[r1] = r30 -> Test reading of PC shadow reg
    JPL shadow         ; Checking to see if r30 is set by jump (should be $60 since that is the next instruction address)
    SW r1, r3          ; mem[r1] = r3 -> This should be skipped

:shadow
    SW r1, r30         ; mem[r1] = r30 -> Test reading of PC shadow reg
:spin
    JPL spin           ; Spin
