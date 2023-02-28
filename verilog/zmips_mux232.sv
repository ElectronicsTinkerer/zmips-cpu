/**
 * 2 x 32 MUX
 */

module zmips_mux232(
    input [31:0] a, b,
    input sel,
    output [31:0] y
    );

assign y = (sel == 0) ? a : b;

endmodule: zmips_mux232
