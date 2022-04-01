/**
 * 4 x 32 MUX
 */

module zmips_mux232(a, b, c, d, sel, y);
input [31:0] a, b, c, d;
input [1:0] sel;
output reg [31:0] y;

always @(a or b or c or d or sel)
begin
    case (sel)
    2'b00: begin
        y = a;
    end
    2'b01: begin
        y = b;
    end
    2'b10: begin
        y = c;
    end
    2'b11: begin
        y = d;
    end
    endcase
end

endmodule
