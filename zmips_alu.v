module zmips_alu(a, b, op, y, zero, cout);
input [31:0] a, b;
input [2:0] op;
output [31:0] y;
output zero, cout;

// ALU Operations
// Format:
// x x x
// | | +-> 0 = add (A + B) / 1 = sub (A-B)
// +-+---> 0 = ADD/SUB
//         1 = AND
//         2 = OR
//         3 = EOR
localparam A_ADD = 6'h0;
localparam A_SUB = 6'h1;
localparam A_AND = 6'h2;
localparam A_OR  = 6'h4;
localparam A_EOR = 6'h6;

wire [31:0] b_in;           // The B input to the adder
wire [31:0] add_rslt;       // The result of the adder
wire [31:0] and_rslt;       // Result of ANDing A and B
wire [31:0] or_rslt;        // Result of ORing A and B
wire [31:0] eor_rslt;       // Result of XORing A and B
wire [1:0] i_op;            // Internal OPeration category
wire i_cin;
wire i_cout;

assign i_op = op[2:1];

assign b_in = b ^ op[0];
assign i_cin = op[0]
assign {i_cout, add_rslt} = a + bin + i_cin;    // Eventually replace this with a CSA or similar

zmips_mux432 ALU_I_MUX(
        .a(add_rslt),
        .b(and_rslt),
        .c(or_rslt),
        .d(eor_rslt),
        .sel(i_op),
        .y(y)
    );

assign cout = (i_op == 2'b00) ? i_cout : 1'b0;  // Only assign C if in ADD/SUB mode
assign zero = ~|y;

endmodule