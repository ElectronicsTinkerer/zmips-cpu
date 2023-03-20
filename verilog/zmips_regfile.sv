/**
 * Reg file, 32bits x 32 registers
 * Dual read port
 * Single write port
 * Write enable (active high), writes on rising edge of CLK
 *
 * Zach Baldwin 2022-03
 */


module zmips_regfile(
    input [4:0] addr_0, addr_1, wr_addr,
    input [31:0] wr_data, pc_val,
    input pc_wr, wr, clk,
    output [31:0] data_0, data_1
    );

// The internal register file
logic [31:0] regfile [0:29];
logic [31:0] pc_reg;

logic [1:0] regsel_0, regsel_1;

assign regsel_0 = {&addr_0[4:1], addr_0[0]};
assign regsel_1 = {&addr_1[4:1], addr_1[0]};

zmips_mux432 MUX_D0(
    .a(regfile[addr_0]),
    .b(regfile[addr_0]),
    .c(pc_reg),
    .d(pc_val),
    .sel(regsel_0),
    .y(data_0)
);

zmips_mux432 MUX_D1(
    .a(regfile[addr_1]),
    .b(regfile[addr_1]),
    .c(pc_reg),
    .d(pc_val),
    .sel(regsel_1),
    .y(data_1)
);

always_ff @(negedge clk) begin
    // If writing and one of the first 30 regs, then write
    if (wr && ((&wr_addr[4:1]) == 1'b0)) begin
        regfile[wr_addr] <= wr_data;
    end
end

always_ff @(negedge clk) begin
    if (pc_wr) begin
        pc_reg <= pc_val;
    end
end


endmodule: zmips_regfile
