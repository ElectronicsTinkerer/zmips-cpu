/**
 * Reg file, 32bits x 32 registers
 * Dual read port
 * Single write port
 * Write enable (active high), writes on rising edge of CLK
 *
 * Zach Baldwin 2022-03
 */


module zmips_regfile(addr_0, addr_1, pc_val, pc_wr, wr_addr, wr_data, wr, clk, data_0, data_1);
input [4:0] addr_0, addr_1, wr_addr;
input [31:0] wr_data, pc_val;
input pc_wr, wr, clk;
output [31:0] data_0, data_1;

// The internal register file
reg [31:0] regfile [0:30];

assign data_0 = regfile[addr_0];
assign data_1 = regfile[addr_1];

always @(posedge clk)
begin
    if (wr)
    begin
        regfile[wr_addr] = wr_data;
    end
end


endmodule
