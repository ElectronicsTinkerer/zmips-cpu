/**
 * ZMIPS test bench
 */

module tb_zmips();

wire [31:0] i_addr, d_data_o, d_addr;
wire [31:0] i_data, d_data_i;
wire d_wr, d_rd;
reg clk, rst;

// Instruction memory
reg [31:0] i_mem[0:4095];
initial $readmemb("asm-output.dat", i_mem);

// Data memory
reg [31:0] d_mem[0:4095];

zmips UUT_ZPU0(i_data, i_addr, d_data_o, d_data_i, d_addr, clk, d_wr, d_rd, rst);

// Implement RAM
assign i_data = i_mem[i_addr >> 2];
assign d_data_i = d_mem[d_addr >> 2];

always @(negedge clk)
begin
    if (d_wr)
    begin
        d_mem[d_addr] <= d_data_o;
    end
end

// Start Test code

initial $monitor("IA: %h | ID: %h || DA: %h | DI: %h | DO: %h | WR: %b | RD: %b || CLK: %b || RST: %b", i_addr, i_data, d_addr, d_data_i, d_data_o, d_wr, d_rd, clk, rst);

initial
begin
    clk = 1'b0;
    forever #10 clk = ~clk;
end

initial
begin
    rst = 1'b1;
    #25
    rst = 1'b0;

end

endmodule
