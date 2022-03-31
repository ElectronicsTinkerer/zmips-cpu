/*
    CLOCK CYCLE:
                ______________
                |
       FIRST    |   SECOND
        HALF    |    HALF
    ____________|

*/

module zmips(i_data, i_addr, d_data, d_addr, clk, d_wr, d_rd);
input [31:0] i_data;
output [31:0] i_addr, d_addr;
inout [31:0] d_data;
input clk;
output d_wr, d_rd;


// Registers 
reg [31:0] ir;
reg [31:0] pc;

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
assign ir_opcode = ir[31:26];
assign ir_rs = ir[25:21];
assign ir_rt = ir[20:16];
assign ir_rd = ir[15:11];
assign ir_shamt = it[10:6];
assign ir_funct = ir[5:0];
assign ir_immediate = ir[15:0];
assign ir_addr = ir[25:0];

// Reg file
zmips_regfile RF0();


endmodule