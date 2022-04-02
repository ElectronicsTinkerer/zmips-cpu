module zmips_barrel_shift(a, shift, op, y);
input [31:0] a;
input [4:0] shift;
input [1:0] op;
output reg [31:0] y;

always @(*)
begin
    case (op)
    2'b00: y = a << shift;
    2'b10: y = a >> shift;
    2'b11: y = a >>> shift;
    default: y = a;
    endcase
end

endmodule
