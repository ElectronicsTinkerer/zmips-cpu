module zmips_barrel_shift(
    input [31:0] a,
    input [4:0] shift,
    input [1:0] op,
    output reg [31:0] y,
    output reg cout
    );

always_comb begin
    case (op)
    2'b01: {cout, y} = a << shift;
    2'b10: {y, cout} = {a, 1'b0} >>> shift;
    2'b11: {y, cout} = {a, 1'b0} >> shift;
    default: {y, cout} = {a, 1'b0};
    endcase
end

endmodule: zmips_barrel_shift
