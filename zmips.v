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
// R-FORMAT
localparam I_NOP   = 32'h00;
localparam I_AND   = 32'h01;    // Bitwise AND rd = rs & rt
localparam I_OR    = 32'h02;    // Bitwise OR rd = rs | rt
localparam I_EOR   = 32'h03;    // Bitwise XOR rd = rs ^ rt
localparam I_SUB   = 32'h04;    // Subtract rd = rs - rt
// localparam I_CMP   = 32'h05;    // Compare regs rs - rt
localparam I_ADD   = 32'h06;    // Add rd = rs + rt

// I_FORMAT
localparam I_SUBI  = 32'h10;    // Subtract signed immediate rt = rs - #se_immd
localparam I_ADDI  = 32'h11;    // Add rt = rs + #se_immd
localparam I_BNE   = 32'h12;    // Branch on rs != rt
localparam I_BEQ   = 32'h13;    // Branch on rs == rt
// localparam I_BCC   = 32'h14;    // Branch on C = 1'b0
// localparam I_BCS   = 32'h15;    // Branch on C = 1'b1
localparam I_LW    = 32'h16;    // Load rt with value at rs + #se_immd
localparam I_SW    = 32'h17;    // Store rt to rs + #se_immd

// J-FORMAT
localparam I_JRE   = 32'h18;    // Jump to reg
localparam I_JMP   = 32'h19;    // Jump to {PC[31:26], addr}
localparam I_JAL   = 32'h1A;    // Jump to {PC[31:26], addr}, storing the current PC to 


// Signals for HAZARD DETECTION UNIT
wire hd_flush_if_id;            // Set to clear the IR to be a NOP

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


// Signals for EX STAGE

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
    else
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

    if (hd_flush_if_id)
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
    id_ex_pipe_rfmt; <= (ir_opcode[5:4] == 2'b00) ? 1'b1 : 1'b0;  // Set R-Format if R-Format
    id_ex_pipe_branch <= (ir_opcode[5:4] == 2'b11) ? 1b'1 : 1'b0; // Set branch flag if this is J-Format
    id_ex_pipe_alusrc <= (ir_opcode[5:4] == 2'b10) ? 1'b1 : 1'b0; // Set ALU b source to SE_IMMD if I-Format
end


endmodule