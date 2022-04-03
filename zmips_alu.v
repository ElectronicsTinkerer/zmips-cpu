module zmips_alu(a, b, op, shamt, cin, y, zero, cout);
input [31:0] a, b;
input [3:0] op;
input [4:0] shamt;
input cin;
output [31:0] y;
output zero, cout;

// ALU Operations
// Format of op:
// 3 2 1 0
// | | | +-> 0 = add (A + B) / 1 = sub (A-B)
// | | |         In reality, this just inverts the B input
// | +-+---> Group operation number (0-3)
// +-------> 0 = Use Group 0 operations / 1 = Use Group 1 operations
//
// Group 0 operations:
//  0 = ADD/SUB
//  1 = AND
//  2 = OR
//  3 = EOR
//
// Group 1 operations:
//  0 = No shift on ALU "A" input ("A" passthrough)
//  1 = Shift ALU "A" input left (logical) by shamt
//  2 = Shift ALU "A" input right (arithmetic) by shamt
//  3 = Shift ALU "A" input right (logical) by shamt
//


localparam A_ADD = 6'h0; // Group 0
localparam A_SUB = 6'h1;
localparam A_AND = 6'h2;
localparam A_OR  = 6'h4;
localparam A_EOR = 6'h6;
localparam A_NOP = 6'h8; // Group 1
localparam A_SLL = 6'ha;
localparam A_SRA = 6'hc;
localparam A_SRL = 6'he;


wire [31:0] b_in;           // The B input to the adder
wire [31:0] add_rslt;       // The result of the adder
wire [31:0] and_rslt;       // Result of ANDing A and B
wire [31:0] or_rslt;        // Result of ORing A and B
wire [31:0] eor_rslt;       // Result of XORing A and B
wire [31:0] g0_y;           // Result from Group 0 operations
wire [31:0] g1_y;           // Result from Group 1 operations
wire [1:0] i_op;            // Internal OPeration category
wire i_group;               // Operation group identifier
wire i_cin;
wire i_cout;
wire g0_cout, g1_cout;      // Carry out signals from each group

assign i_op = op[2:1];
assign i_group = op[3];
assign zero = ~|y;

// -------------- GROUP 0 ----------------
assign b_in = b ^ op[0];
assign i_cin = op[0]
assign {i_cout, add_rslt} = a + b_in + cin;    // Eventually replace this with a CSA or similar
assign and_rslt = a & b_in;
assign or_rslt = a | b_in;
assign eor_rslt = a ^ b_in;

zmips_mux432 ALU_I_MUX(
        .a(add_rslt),
        .b(and_rslt),
        .c(or_rslt),
        .d(eor_rslt),
        .sel(i_op),
        .y(g0_y)
    );

assign g0_cout = (i_op == 2'b00) ? i_cout : 1'b0;  // Only assign C if in ADD/SUB mode

// -------------- GROUP 1 ----------------

zmips_barrel_shift ALU_I_BS(.a(a), .shift(shamt), .op(i_op), .y(g1_y), .cout(g1_cout));

// -------------- GROUP SELECTION ----------------
zmips_mux232 ALU_IO_MUX(.a(g0_y), .b(g1_y), .sel(i_group), .y(y));
assign cout = i_group ? g1_cout : g0_cout;

endmodule