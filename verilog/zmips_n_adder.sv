/**
 * N-bit parameterized adder
 */

module zmips_n_adder #(
    parameter W = 32
  ) (
    input [W-1:0] a, b,
    output [W-1:0] sum
  );

assign sum = a + b;

endmodule: zmips_n_adder