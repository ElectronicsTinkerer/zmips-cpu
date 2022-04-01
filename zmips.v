/*
    CLOCK CYCLE:
                ______________
                |
       FIRST    |   SECOND
        HALF    |    HALF
    ____________|

*/

module zmips(i_data, i_addr, d_data, d_addr, clk, d_wr, d_rd, rst);
input [31:0] i_data;
output [31:0] i_addr, d_addr;
inout [31:0] d_data;
input clk, rst; // Active HIGH reset
output d_wr, d_rd;

// Opcodes (See ID stage for how bits [5:4] determine the FORMAT)
//
// Layout of FUNCT field (See ID stage for these definitions)
// x x x x x x x
// | | | | | | +-> 1 = write Z flag
// | | | | | +---> 1 = write C flag
// | | | | +-----> 1 = write N flag
// | | | +-------> Unused
// | | +---------> Unused
// | +-----------> Unused
//
// Layout of BRANCH I-Format
// +-----+-----+-----+------------------+
// |  op |  rs |  rt |      SE_IMMD     |
// +-----+-----+-----+------------------+
//
// op = 12h to branch on set flag
// op = 13h to branch on clear flag
//
// rs for branches is split as follows:
// x x x x x
// | | | +-+-> 0 = Branch on Z
// | | |       1 = Branch on C
// | | |       2 = Branch on N
// | | |       3 = RESERVED
// | | +-----> Unused
// | +-------> Unused
// +---------> Unused

// R-FORMAT
localparam I_NOP   = 32'h00;
localparam I_AND   = 32'h01;    // Bitwise AND rd = rs & rt
localparam I_OR    = 32'h02;    // Bitwise OR rd = rs | rt
localparam I_EOR   = 32'h03;    // Bitwise XOR rd = rs ^ rt
localparam I_SUB   = 32'h04;    // Subtract rd = rs - rt
// localparam I_CMP   = 32'h05;    // Compare regs rs - rt
localparam I_ADD   = 32'h06;    // Add rd = rs + rt
localparam I_SLL   = 32'h08;    // Shift Locgical Left rd = rd << shamt
localparam I_SRL   = 32'h0A;    // Shift Locgical Right rd = rd >>> shamt
localparam I_SRA   = 32'h0B;    // Shift Arithmetic Right rd = rd >> shamt

// I_FORMAT
localparam I_SUBI  = 32'h10;    // Subtract signed immediate rt = rs - #se_immd
localparam I_ADDI  = 32'h11;    // Add rt = rs + #se_immd
localparam I_BFC   = 32'h12;    // Branch on flag "F" clear (format: BFS F, label ; where F is Z, C, N)
localparam I_BFS   = 32'h13;    // Branch on flag "F" set
localparam I_LW    = 32'h16;    // Load rt with value at rs + #se_immd
localparam I_SW    = 32'h17;    // Store rt to rs + #se_immd

// J-FORMAT
localparam I_JRE   = 32'h18;    // Jump to reg
localparam I_JMP   = 32'h19;    // Jump to {PC[31:26], addr}
localparam I_JAL   = 32'h1A;    // Jump to {PC[31:26], addr}, storing the current PC to 


// Signals for HAZARD DETECTION UNIT
wire hd_if_id_flush;            // Set to clear the IR to be a NOP
wire hd_id_ex_flush;            // Set to disable stages following ID (this particular cycle as it moves through)
wire hd_if_pc_wr;               // Set to enable updating of PC

// Signals for FORWARDING UNIT
wire [1:0] fw_ex_rs_src;        // Mux select for ALU "a" input
wire [1:0] fw_ex_rt_src;        // Mux select for ALU "b" input
wire fw_ex_z;                   // Mux select for Z flag (Between Z FF and ALU Z ouptut)
wire fw_ex_c;                   // Mux select for C flag (Between C FF and ALU C ouptut)
wire fw_ex_n;                   // Mux select for N flag (Between N FF and ALU N ouptut)

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
reg [31:0] id_ex_pipe_imm_se
reg id_ex_pipe_rfmt;            // 1 on R-format instruction
reg id_ex_pipe_branch;          // 1 on branch
reg id_ex_pipe_alusrc;          // 1 on SE IMMD, 0 on REG_1
reg id_ex_pipe_memrd;           // 1 on read from mem
reg id_ex_pipe_memwr;           // 1 on write to mem
reg id_ex_pipe_wrreg;           // 1 on write to reg
reg id_ex_pipe_wrzf;            // 1 to enable writing to Z flag
reg id_ex_pipe_wrcf;            // 1 to enable writing to C flag
reg id_ex_pipe_wrnf;            // 1 to enable writing to N flag


// Signals for EX STAGE
wire [31:0] ex_alu_a;           // ALU "a" input value
wire [31:0] ex_alu_b;           // ALU "b" input value
wire [31:0] ex_alu_pre_b;       // ALU "b" input value before the ALUSrc mux
wire [3:0] ex_alu_op;           // ALU internal operation code
wire [31:0] ex_alu_rslt;        // ALU result
wire ex_zf, ex_cf, ex_nf;       // Zero, Carry, Negative flags input lines
wire [4:0] ex_wb_reg;           // Muxed reg to send to next stage for write-back

                                // For instructions which affect the flags:
reg flag_zero;                  // Zero flag (1 = previous operation was 0)
reg flag_carry;                 // Carry flag (1 = previous op resulted in a carry)
reg flag_negative;              // Negative flag (bit 31 of the previous ALU result)

reg [31:0] ex_mem_pipe_alu_rslt;    // ALU result (Also used as address in a MEMory access op)
reg [31:0] ex_mem_pipe_addr;    // Data to be written to memory in a SW operation
reg [4:0] ex_mem_pipe_wb_reg;   // Reg to which to write back
reg ex_mem_memrd;               // High on a memory read
reg ex_mem_memwr;               // High on a memory write
reg ex_mem_wrreg;               // High when the reg in ex_mem_pipe_wb_reg needs to be written

// Signals for MEM STAGE

// Signals for WB STAGE
wire [4:0] wb_addr;
wire [31:0] wb_data;


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
        .wr(????),  //////////////////////////////////////////////////////////////////////////////////// Finish after WB
        .clk(clk), 
        .data_0(d_reg_0), 
        .data_1(d_reg_1)
    );

// ID/EX connection pipeline register(s)
always @(negedge clk)
begin
    id_ex_pipe_reg_0 <= d_reg_0;    // Pass along reg file outputs
    id_ex_pipe_reg_1 <= d_reg_1;
    id_ex_pipe_rs <= ir_rs;         // Pass along which regs are in use
    id_ex_pipe_rt <= ir_rt;
    id_ex_pipe_rd <= ir_rd;
    id_ex_pipe_imm_se <= ir_imm_se; // Pass along sign extended immediate
    
    if (hd_id_ex_flush == 1'b1)     // If a hazard is detected, knock out the next stage
    begin
        id_ex_pipe_rfmt <= 1'b0;
        id_ex_pipe_branch <= 1'b0;
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
        id_ex_pipe_rfmt <= (ir_opcode[5] == 1'b0) ? 1'b1 : 1'b0;     // Set R-Format if R-Format
        id_ex_pipe_branch <= (ir_opcode[5:4] == 2'b11) ? 1b'1 : 1'b0;   // Set branch flag if this is J-Format
        id_ex_pipe_alusrc <= (ir_opcode[5:4] == 2'b10) ? 1'b1 : 1'b0;   // Set ALU b source to SE_IMMD if I-Format
        id_ex_pipe_memrd <= (ir_opcode == I_LW) ? 1'b1 : 1'b0;          // Set mem read on LOAD instruction
        id_ex_pipe_memwr <= (ir_opcode == I_SW) ? 1'b1 : 1'b0;          // Set mem write on STORE instruction
        id_ex_pipe_wrreg <= (ir_opcode[5] == 1'b0 || ir_opcode == I_LW) ? 1'b1 : 1'b0;   // Write back to reg
        id_ex_pipe_wrzf <= (ir_opcode[5] == 1'b0 && funct[0]) ? 1b'1 : 1'b0; // Only change Z flag for R-Format instructions
        id_ex_pipe_wrcf <= (ir_opcode[5] == 1'b0 && funct[1]) ? 1b'1 : 1'b0; // Only change C flag for R-Format instructions
        id_ex_pipe_wrnf <= (ir_opcode[5] == 1'b0 && funct[2]) ? 1b'1 : 1'b0; // Only change N flag for R-Format instructions
    end
end

// ----------------- EX STAGE -----------------

// ALU "a" input mux
zmips_mux432 ALU_A_MUX(
        .a(id_ex_pipe_reg_0),
        .b(wb_data),
        .c(ex_mem_pipe_alu_rslt),
        .d(32'bXX), // DEBUG
        .sel(fw_ex_rs_src),
        .y(ex_alu_a)
    );

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
zmips_mux232 ALU_SRC_MUX(.a(ex_alu_pre_b), .b(id_ex_pipe_imm_se), .sel(id_ex_pipe_alusrc), .y(ex_alu_b));

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
    ex_mem_pipe_addr <= ex_alu_pre_b;       // Also the pre-immediate muxed B input (to be used as the data to write if doing a SW instructions)
    ex_mem_pipe_wb_reg <= ex_wb_reg;        // Save the reg which is to be used for WB stage
    ex_mem_memrd <= id_ex_pipe_memrd;
    ex_mem_memwr <= id_ex_pipe_memwr;
    ex_mem_wrreg <= id_ex_pipe_wrreg;
end



endmodule