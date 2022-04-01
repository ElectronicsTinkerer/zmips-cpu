/**
 * 2 x 5 MUX
 */

 module zmips_mux232(a, b, sel, y);
 input [4:0] a, b;
 input sel;
 output [4:0] y;

 assign y = (sel == 0) ? a : b;

 endmodule
