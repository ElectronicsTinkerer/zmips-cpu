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


// Signals for IF STAGE
wire [31:0] pc_next_val;    // To be fed into the PC on the next NEGEDGE of CLK
wire [31:0] pc_inc_val;     // Selected if the next address is to be fetched
wire pc_src_sel;            // Low = INC PC, High = result from ID stage

reg [31:0] pc;              // Program Counter
reg [31:0] if_id_pipe_pc;   // Pipelined PC
reg [31:0] if_id_pipe_ir;   // Result from reading instruction memory

// Signals for ID STAGE
wire [31:0] d_reg_0, d_reg_1;
wire [31:0] ir_immediate_se; // Sign extension
wire [31:0] pc_id_val;      // For when the ID stage must modify the PC (branch, jump)

// Opcode fields 
wire [5:0] ir_opcode;
wire [4:0] ir_rs;
wire [4:0] ir_rt;
wire [4:0] ir_rd;
wire [4:0] ir_shamt;
wire [5:0] ir_funct;
wire [15:0] ir_immediate;
wire [25:0] ir_addr;

// Split IR into individual pieces
assign ir_opcode = if_id_pipe_ir[31:26];
assign ir_rs = if_id_pipe_ir[25:21];
assign ir_rt = if_id_pipe_ir[20:16];
assign ir_rd = if_id_pipe_ir[15:11];
assign ir_shamt = if_id_pipe_ir[10:6];
assign ir_funct = if_id_pipe_ir[5:0];
assign ir_immediate = if_id_pipe_ir[15:0];
assign ir_addr = if_id_pipe_ir[25:0];

// Signals for EX STAGE

// Signals for MEM STAGE

// Signals for WB STAGE


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
    if_id_pipe_ir <= i_data;
end

// ----------------- ID STAGE -----------------

// Reg file
zmips_regfile RF0(
        .addr_0(ir_rs), 
        .addr_1(ir_rt), 
        .wr_addr(????), 
        .wr_data(????), 
        .wr(????), 
        .clk(clk), 
        .data_0(d_reg_0), 
        .data_1(d_reg_1)
    );


endmodule