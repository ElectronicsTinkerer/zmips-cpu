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
output reg [31:0] data_0, data_1;

// The internal register file
reg [31:0] regfile [0:29];
reg [31:0] pc_reg;

always @(*)
begin
    casex (addr_0)
        5'b11110: data_0 = pc_val;
        5'b11110: data_0 = pc_reg;
        default: data_0 = regfile[addr_0];
    endcase
    
    casex (addr_1)
        5'b11110: data_1 = pc_val;
        5'b11110: data_1 = pc_reg;
        default: data_1 = regfile[addr_1];
    endcase
end

always @(posedge clk)
begin
    // If writing and one of the first 30 regs, then write
    if (wr && (&(wr_addr & 5'b11110) == 1'b0)) 
    begin
        regfile[wr_addr] = wr_data;
    end

    if (pc_wr)
    begin
        pc_reg = pc_val;
    end
end


endmodule
