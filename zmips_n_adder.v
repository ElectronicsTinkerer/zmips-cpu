module zmips_n_adder (
    parameter W = 32;
) (a, b, sum);
input [W-1:0] a, b;
output sum[W-1:0];

assign sum = a + b;

endmodule