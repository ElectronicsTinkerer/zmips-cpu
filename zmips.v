/*
    CLOCK CYCLE:
                ______________
                |
       FIRST    |   SECOND
        HALF    |    HALF
    ____________|

*/

// TODO: 
// * Hazard detection
// * Forwarding unit
// * ALU OP decoding
// * shifting



module zmips(i_data, i_addr, d_data_o, d_data_i, d_addr, clk, d_wr, d_rd, rst);
input [31:0] i_data;
output [31:0] i_addr, d_addr, d_data_i;
inout [31:0] d_data_o;
input clk, rst; // Active HIGH reset
output d_wr, d_rd;

// Opcodes (See ID stage for how bits [5:4] determine the FORMAT)
//
// Layout of an R-Format instruction
// +------+-----+-----+-----+-----+------+
// |  op  |  rs |  rt |  rd |shamt| func |
// +------+-----+-----+-----+-----+------+
// 31   26/25 21/20 16/15 11/10  6/5     0
//
// Registers:
//   rs -> Source reg 1, can be shifted by setting appropiate bits in OP field
//   rt -> Source reg 2
//   rd -> Destination register of operation
//         Note that this is only written to if the write back flag
//         is set in the OP field
// 
// Layout of OP field (See CONTROL and ID stage for definitions)
// x x x x x x
// | | | | +-+-> 0 = No shift on ALU "A" input
// | | | |       1 = Shift ALU "A" input left (logical) by shamt
// | | | |       2 = Shift ALU "A" input right (logical) by shamt
// | | | |       3 = Shift ALU "A" input right (arithmetic) by shamt
// | | | +-----> 1 = Write back to reg rd, 0 = Don't save operation result
// | | +-------> 0
// | +---------> 0
// +-----------> 0
//
// Layout of FUNCT field (See ID stage for these definitions)
// x x x x x x
// | | | | | +-> 1 = update Z flag
// | | | | +---> 1 = update C flag
// | | | +-----> 1 = update N flag
// | | +-------> ALUOp0 (See ALU for details)
// | +---------> ALUOp1 (See ALU for details)
// +-----------> ALUOp2 (See ALU for details)
//
// Layout of BRANCH I-Format
// +------+-----+-----+----------------+
// |  op  |  rs |  rt |     SE_IMMD    |
// +------+-----+-----+----------------+
// 31   26/25 21/20 16/15              0
//
// Layout of OP field (See CONTROL and ID stage for definitions)
// x x x x x x
// | | | | +-+-> 0 = No shift on ALU "A" input
// | | | |       1 = Shift ALU "A" input left (logical) by shamt
// | | | |       2 = Shift ALU "A" input right (logical) by shamt
// | | | |       3 = Shift ALU "A" input right (arithmetic) by shamt
// | | | +-----> 1 = Write back to reg rd, 0 = Don't save operation result
// | | +-------> 1 = Branch on flag set, 0 = branch on flag clear
// | +---------> 1 = Branch operation
// +-----------> 0
//
// rs for branches is split as follows:
// x x x x x
// | | | +-+-> 0 = Branch on Z
// | | |       1 = Branch on C
// | | |       2 = Branch on N
// | | |       3 = Branch Always
// | | +-----> Unused
// | +-------> Unused
// +---------> Unused
//
// rt is unused for branches
//
// Layout of JUMP J-Format
// +-+-------------------------------+
// |o|            address            |
// +-+-------------------------------+
// 31/30                             0
//
// Layout of OP field (See CONTROL and ID stage for definitions)
// x x x x x x
// | +-+-+-+-+-> Top 5 bits of jump address
// +-----------> 1 = Jump operation
//

// R-FORMAT
localparam I_NOP   = 6'h00;
localparam I_AND   = 6'h00;    // Bitwise AND rd = rs & rt
localparam I_OR    = 6'h00;    // Bitwise OR rd = rs | rt
localparam I_EOR   = 6'h00;    // Bitwise XOR rd = rs ^ rt
localparam I_SUB   = 6'h00;    // Subtract rd = rs - rt
// localparam I_CMP   = 6'h00;    // Compare regs rs - rt
localparam I_ADD   = 6'h00;    // Add rd = rs + rt
        // Note that these use the lowest 2 bits for determining the shift direction
localparam I_SLL   = 6'h08;    // Shift Locgical Left rd = rd << shamt
localparam I_SRL   = 6'h0A;    // Shift Locgical Right rd = rd >>> shamt
localparam I_SRA   = 6'h0B;    // Shift Arithmetic Right rd = rd >> shamt

// I_FORMAT
localparam I_SUBI  = 6'h10;    // Subtract signed immediate rt = rs - #se_immd
localparam I_ADDI  = 6'h11;    // Add rt = rs + #se_immd
localparam I_BFC   = 6'h12;    // Branch on flag "F" clear (format: BFS F, label ; where F is Z, C, N)
localparam I_BFS   = 6'h13;    // Branch on flag "F" set
localparam I_LW    = 6'h16;    // Load rt with value at rs + #se_immd
localparam I_SW    = 6'h17;    // Store rt to rs + #se_immd

// J-FORMAT
localparam I_JRE   = 6'h18;    // Jump to reg
localparam I_JMP   = 6'h19;    // Jump to {PC[31:26], addr}
localparam I_JAL   = 6'h1A;    // Jump to {PC[31:26], addr}, storing the current PC to 


// Signals for HAZARD DETECTION UNIT
    // EXTERNAL
wire hd_if_id_flush;            // Set to clear the IR to be a NOP
wire hd_id_ex_flush;            // Set to disable stages following ID (this particular cycle as it moves through)
wire hd_if_pc_wr;               // Set to enable updating of PC

    // INTERNAL
reg hw_reg_conflict;            // High when rt(ID/EX) == rs(IF/ID) or rt(ID/EX) == rt(IF/ID)


// Signals for FORWARDING UNIT
    // EXTERNAL
reg [1:0] fw_ex_rs_src;         // Mux select for ALU "a" input
reg [1:0] fw_ex_rt_src;         // Mux select for ALU "b" input
reg fw_ex_z;                    // Mux select for Z flag (Between Z FF and ALU Z ouptut)
reg fw_ex_c;                    // Mux select for C flag (Between C FF and ALU C ouptut)
reg fw_ex_n;                    // Mux select for N flag (Between N FF and ALU N ouptut)
reg fw_mem_ldsw;                // Mux select for consecutive mem load/store operation (WB->MEM)

    // INTERNAL
// [none]


// Signals for IF STAGE
wire [31:0] pc_next_val;        // To be fed into the PC on the next NEGEDGE of CLK
wire [31:0] pc_inc_val;         // Selected if the next address is to be fetched
wire pc_src_sel;                // Low = INC PC, High = result from ID stage

reg [31:0] pc;                  // Program Counter
reg [31:0] if_id_pipe_pc;       // Pipelined PC
reg [31:0] if_id_pipe_ir;       // Result from reading instruction memory

// Signals for ID STAGE
wire [31:0] d_reg_0, d_reg_1;
wire [31:0] ir_imm_se;          // Sign extension
wire [31:0] ir_imm_se_sh;       // Shifted sign extend (left, 2)
wire [31:0] pc_id_val;          // For when the ID stage must modify the PC (branch, jump)
 
wire [5:0] ir_opcode;           // Opcode fields
wire [4:0] ir_rs;
wire [4:0] ir_rt;
wire [4:0] ir_rd;
wire [4:0] ir_shamt;
wire [5:0] ir_funct;
wire [15:0] ir_imm;
wire [25:0] ir_addr;

reg [31:0] id_ex_pipe_reg_0, id_ex_pipe_reg_1;  // Outputs from reg file
reg [4:0] id_ex_pipe_rs, id_ex_pipe_rt, id_ex_pipe_rd;
reg [31:0] id_ex_pipe_immd_se
reg [1:0] id_ex_pipe_shop;      // Shift operation type
reg id_ex_pipe_rfmt;            // 1 on R-format instruction
// reg id_ex_pipe_branch;          // 1 on branch
reg id_ex_pipe_alusrc;          // 1 on SE IMMD, 0 on REG_1
reg id_ex_pipe_memrd;           // 1 on read from mem
reg id_ex_pipe_memwr;           // 1 on write to mem
reg id_ex_pipe_wrreg;           // 1 on write to reg
    // Flag control lines:
    // Do not need to be separate signals from id_ex_pipe_immd_se, but makes it more readable
reg id_ex_pipe_wrzf;            // 1 to enable writing to Z flag
reg id_ex_pipe_wrcf;            // 1 to enable writing to C flag
reg id_ex_pipe_wrnf;            // 1 to enable writing to N flag


// Signals for EX STAGE
wire [31:0] ex_alu_a;           // ALU "a" input value
wire [31:0] ex_alu_pre_a;       // ALU "a" input value before the barrel shifter
wire [31:0] ex_alu_b;           // ALU "b" input value
wire [31:0] ex_alu_pre_b;       // ALU "b" input value before the ALUSrc mux
wire [2:0] ex_alu_op;           // ALU internal operation code
wire [31:0] ex_alu_rslt;        // ALU result
wire ex_zf, ex_cf, ex_nf;       // Zero, Carry, Negative flags input lines
wire [4:0] ex_wb_reg;           // Muxed reg to send to next stage for write-back
wire [5:0] ex_funct;            // Function code
wire [4:0] ex_shamt;            // Barrel shifter amount

                                // For instructions which affect the flags:
reg flag_zero;                  // Zero flag (1 = previous operation was 0)
reg flag_carry;                 // Carry flag (1 = previous op resulted in a carry)
reg flag_negative;              // Negative flag (bit 31 of the previous ALU result)

reg [31:0] ex_mem_pipe_alu_rslt;    // ALU result (Also used as address in a MEMory access op)
reg [31:0] ex_mem_pipe_data;    // Data to be written to memory in a SW operation
reg [4:0] ex_mem_pipe_wb_reg;   // Reg to which to write back
reg ex_mem_pipe_memrd;          // High on a memory read
reg ex_mem_pipe_memwr;          // High on a memory write
reg ex_mem_pipe_wrreg;          // High when the reg in ex_mem_pipe_wb_reg needs to be written

// Signals for MEM STAGE
reg [31:0] mem_wb_pipe_memd;    // Data from memory
reg [31:0] mem_wb_pipe_alud;    // Data from ALU
reg [4:0] mem_wb_pipe_wb_reg;   // Register to which to write back
reg mem_wb_pipe_memrd;          // High when reading from memory
reg mem_wb_pipe_wrreg;          // High when writing back to a reg

// Signals for WB STAGE
wire [4:0] wb_addr;             // Register number to which to write back
wire [31:0] wb_data;            // Data to write to a register
wire wb_wr;                     // 1 = write, 0 = don't write


// ----------------- IF STAGE -----------------
// PC
always @(negedge clk)
begin
    if (rst)
    begin
        pc <= 32'b0;
    end
    else if (hd_if_pc_wr == 1'b1)
    begin
        pc <= pc_next_val;
    end
end

// PC Incrementer
zmips_n_adder #(.W(32)) PC_ADD(.a(pc), .b(32'h4), .sum(pc_inc_val));
zmips_mux232 PC_MUX(.a(pc_inc_val), .b(pc_id_val), .sel(pc_src_sel), .y(pc_next_val));

// Instruction Memory Interface
assign i_addr = pc;

// IF/ID connection pipeline register(s)
always @(negedge clk)
begin
    if_id_pipe_pc <= pc_inc_val;

    if (hd_if_id_flush)
    begin
        if_id_pipe_ir <= I_NOP;
    end
    else
    begin
        if_id_pipe_ir <= i_data;
    end
end

// ----------------- ID STAGE -----------------

assign ir_opcode = if_id_pipe_ir[31:26]; // Split IR into individual pieces
assign ir_rs = if_id_pipe_ir[25:21];
assign ir_rt = if_id_pipe_ir[20:16];
assign ir_rd = if_id_pipe_ir[15:11];
assign ir_shamt = if_id_pipe_ir[10:6];
assign ir_funct = if_id_pipe_ir[5:0];
assign ir_immd = if_id_pipe_ir[15:0];
assign ir_addr = if_id_pipe_ir[25:0];

// Sign extend
assign ir_immd_se = {16{ir_immd[15]}, ir_immd};

// Shift immediate
assign ir_imm_se_sh = ir_imm_se << 2;

// Calculate branch address
zmips_n_adder #(.W(32)) PC_ADD(.a(if_id_pipe_pc), .b(ir_imm_se_sh), .sum(pc_id_val)); // Feedback to IF

// Reg file
zmips_regfile RF0(
        .addr_0(ir_rs), 
        .addr_1(ir_rt), 
        .wr_addr(wb_addr), 
        .wr_data(wb_data), 
        .wr(wb_wr)),
        .clk(clk), 
        .data_0(d_reg_0), 
        .data_1(d_reg_1)
    );

// Various bits of instruction decoding
always @(*)
begin
    case (ir_opcode)

    default:
    endcase
end

// ID/EX connection pipeline register(s)
always @(negedge clk)
begin
    id_ex_pipe_reg_0 <= d_reg_0;    // Pass along reg file outputs
    id_ex_pipe_reg_1 <= d_reg_1;
    id_ex_pipe_rs <= ir_rs;         // Pass along which regs are in use
    id_ex_pipe_rt <= ir_rt;
    id_ex_pipe_rd <= ir_rd;
    id_ex_pipe_immd_se <= ir_imm_se; // Pass along sign extended immediate
    id_ex_pipe_shop <= ir_opcode[1:0]; // Pass along amount to shift ALU A input
    
    if (hd_id_ex_flush == 1'b1)     // If a hazard is detected, knock out the next stage
    begin
        id_ex_pipe_rfmt <= 1'b0;
        // id_ex_pipe_branch <= 1'b0;
        id_ex_pipe_alusrc <= 1'b0;
        id_ex_pipe_memrd <= 1'b0;
        id_ex_pipe_memwr <= 1'b0; 
        id_ex_pipe_wrreg <= 1'b0;
        id_ex_pipe_wrzf <= 1'b0;
        id_ex_pipe_wrcf <= 1'b0;
        id_ex_pipe_wrnf <= 1'b0;
    end
    else                            // Otherwise, we are good to go
    begin
        id_ex_pipe_rfmt <= (ir_opcode[5:4] == 2'b00) ? 1'b1 : 1'b0;     // Set R-Format if R-Format
        // id_ex_pipe_branch <= (ir_opcode[5:4] == 2'b11) ? 1b'1 : 1'b0;   // Set branch flag if this is J-Format
        id_ex_pipe_alusrc <= (ir_opcode[5:4] == 2'b01) ? 1'b1 : 1'b0;   // Set ALU b source to SE_IMMD if I-Format
        id_ex_pipe_memrd <= (ir_opcode == I_LW) ? 1'b1 : 1'b0;          // Set mem read on LOAD instruction
        id_ex_pipe_memwr <= (ir_opcode == I_SW) ? 1'b1 : 1'b0;          // Set mem write on STORE instruction
        id_ex_pipe_wrreg <= (ir_opcode[5] == 1'b0 || ir_opcode == I_LW) ? 1'b1 : 1'b0;   // Write back to reg
        id_ex_pipe_wrzf <= (ir_opcode[5] == 1'b0 && funct[0]) ? 1b'1 : 1'b0; // Only change Z flag for R-Format instructions
        id_ex_pipe_wrcf <= (ir_opcode[5] == 1'b0 && funct[1]) ? 1b'1 : 1'b0; // Only change C flag for R-Format instructions
        id_ex_pipe_wrnf <= (ir_opcode[5] == 1'b0 && funct[2]) ? 1b'1 : 1'b0; // Only change N flag for R-Format instructions
    end
end

// ----------------- EX STAGE -----------------

assign ex_funct = id_ex_pipe_immd_se[5:0];
assign ex_shamt = id_ex_pipe_immd_se[10:6];
assign ex_alu_op = ex_funct[5:3];

// ALU "a" input mux
zmips_mux432 ALU_A_MUX(
        .a(id_ex_pipe_reg_0),
        .b(wb_data),
        .c(ex_mem_pipe_alu_rslt),
        .d(32'bXX), // DEBUG
        .sel(fw_ex_rs_src),
        .y(ex_alu_pre_a)
    );

zmips_barrel_shift BARREL_SFT(.a(ex_alu_pre_a), .shift(ex_shamt), .op(id_ex_pipe_shop), .y(ex_alu_a));

// ALU "b" input mux
zmips_mux432 ALU_B_MUX(
        .a(id_ex_pipe_reg_1),
        .b(wb_data),
        .c(ex_mem_pipe_alu_rslt),
        .d(32'bXX), // DEBUG
        .sel(fw_ex_rt_src),
        .y(ex_alu_pre_b)
    );

// ALUSrc mux for "b" input
// Selects between reg/forwarded data and the SE IMMD data
zmips_mux232 ALU_SRC_MUX(.a(ex_alu_pre_b), .b(id_ex_pipe_immd_se), .sel(id_ex_pipe_alusrc), .y(ex_alu_b));

zmips_alu ALU0(.a(ex_alu_a), .b(ex_alu_b), .op(ex_alu_op), .y(ex_alu_rslt), .zero(ex_zf), .cout(ex_cf));

// Handle negative flag input line
assign ex_nf = ex_alu_rslt[31];

// Not a pipeline reg, just state flags for the EX stage (and ID)
always @(negedge clk)
begin
    // Only update flags when their ID/EX enable line is active
    if (id_ex_pipe_wrzf == 1'b1)
    begin
        flag_zero <= ex_zf;
    end
    if (id_ex_pipe_wrcf == 1'b1)
    begin
        flag_carry <= ex_cf;
    end
    if (id_ex_pipe_wrnf == 1'b1)
    begin
        flag_negative <= ex_nf;
    end
end

zmips_mux205 WR_REG_MUX(.a(id_ex_pipe_rt), .b(id_ex_pipe_rd), .sel(id_ex_pipe_rfmt), .y(ex_wb_reg));

// Pipeline regs for EX/MEM stage
always @(negedge clk)
begin
    ex_mem_pipe_alu_rslt <= ex_alu_rslt;    // Save ALU result for stage (to be used as the address in a MEMory access)
    ex_mem_pipe_data <= ex_alu_pre_b;       // Also the pre-immediate muxed B input (to be used as the data to write if doing a SW instructions)
    ex_mem_pipe_wb_reg <= ex_wb_reg;        // Save the reg which is to be used for WB stage
    ex_mem_pipe_memrd <= id_ex_pipe_memrd;
    ex_mem_pipe_memwr <= id_ex_pipe_memwr;
    ex_mem_pipe_wrreg <= id_ex_pipe_wrreg;
end


// ----------------- MEM STAGE -----------------

// Data memory interface
assign d_addr = ex_mem_pipe_alu_rslt;
assign d_wr = ex_mem_pipe_memwr;
assign d_rd = ex_mem_pipe_memrd;

// For forwarding from WB stage (consecutive LW/SW on same reg)
zmips_mux232 MUX_DATA_O(.a(ex_mem_pipe_data), .b(mem_wb_pipe_memd), .sel(fw_mem_ldsw), .y(d_data_o));

// MEM/WB pipeline regs
always @(negedge clk)
begin
    mem_wb_pipe_memd <= d_data_i;               // Data in from the data memory
    mem_wb_pipe_alud <= ex_mem_pipe_alu_rslt;   // Data from ALU in EX stage
    mem_wb_pipe_memrd <= ex_mem_pipe_memrd;     // Reading from memory
    mem_wb_pipe_wrreg <= ex_mem_pipe_wrreg;     // Writing to a reg
    mem_wb_pipe_wb_reg <= ex_mem_pipe_wb_reg;   // Reg to which to write back
end


// ----------------- WB STAGE -----------------

// Select the data source to write back
zmips_mux232 WB_MUX(.a(mem_wb_pipe_alud), .b(mem_wb_pipe_memd), .sel(mem_wb_pipe_memrd), .y(wb_data));

assign wb_addr = mem_wb_pipe_wb_reg;

assign wb_wr = mem_wb_pipe_wrreg;


// ----------------- HAZARD DETECTION -----------------


// wire hd_if_id_flush;            // Set to clear the IR to be a NOP
// wire hd_id_ex_flush;            // Set to disable stages following ID (this particular cycle as it moves through)
// wire hd_if_pc_wr;               // Set to enable updating of PC

// Check for LD register use conflicts
always @(*)
begin
    hw_reg_conflict = 1'b0;
    if (id_ex_pipe_memrd == 1'b1 && ((id_ex_pipe_rt == if_id_pipe_rs) || (id_ex_pipe_rt == if_id_pipe_rt))
    begin
        hw_reg_conflict = 1'b1;
    end
end

// Signal pipeline stages
assign hd_id_ex_flush = hw_reg_conflict;
assign hd_if_pc_wr = ~hw_reg_conflict;
// TODO: assign hd_if_id_flush when branch is taken


// ----------------- FORWARDING CONTROL -----------------


// wire [1:0] fw_ex_rs_src;        // Mux select for ALU "a" input
// wire [1:0] fw_ex_rt_src;        // Mux select for ALU "b" input
// wire fw_ex_z;                   // Mux select for Z flag (Between Z FF and ALU Z ouptut)
// wire fw_ex_c;                   // Mux select for C flag (Between C FF and ALU C ouptut)
// wire fw_ex_n;                   // Mux select for N flag (Between N FF and ALU N ouptut)


// Check for forwarding hazards
always @(*)
begin
    fw_ex_rs_src = 2'b00;           // Default to just reading directly from the reg file
    fw_ex_rt_src = 2'b00;
    fw_mem_ldsw = 1'b0;             // Default: don't forward memory data read in the last cycle to memory stage

    // Check for forwarding of EX rs
    // EX hazard (forward from previous ALU result)
    if (ex_mem_pipe_wrreg == 1'b1 && (ex_mem_pipe_wb_reg == id_ex_pipe_rs))
    begin
        fw_ex_rs_src = 2'b10;
    end
    // MEM hazard (forward from memory or previous previous ALU result)
    else if (mem_wb_pipe_wrreg == 1'b1 && (mem_wb_pipe_wb_reg == id_ex_pipe_rs))
    begin
        fw_ex_rs_src = 2'b01;
    end

    // Check for forwarding of EX rt
    // EX hazard (forward from previous ALU result)
    if (ex_mem_pipe_wrreg == 1'b1 && (ex_mem_pipe_wb_reg == id_ex_pipe_rt))
    begin
        fw_ex_rt_src = 2'b10;
    end
    // MEM hazard (forward from memory or previous previous ALU result)
    else if (mem_wb_pipe_wrreg == 1'b1 && (mem_wb_pipe_wb_reg == id_ex_pipe_rt))
    begin
        fw_ex_rt_src = 2'b01;
    end

    // Check for consecutive LW/SW on the same reg
    if (mem_wb_pipe_wb_reg == ex_mem_pipe_wb_reg && mem_wb_pipe_memrd == 1'b1 && ex_mem_pipe_wrreg == 1'b1)
    begin
        fw_mem_ldsw = 1'b1;
    end
end

endmodule