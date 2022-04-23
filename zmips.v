/*
    CLOCK CYCLE:
    ___            _____________
      |            |           |
      |   FIRST    |   SECOND  |
      |    HALF    |    HALF   |
      |____________|           |__

      ^            ^
      |            |
      |            Read
      Writeback

    ** Reg and Mem writeback: posedge clk
    ** PC and pipeline regs update: negedge clk
*/

module zmips(i_data, i_addr, d_data_o, d_data_i, d_addr, clk, d_wr, d_rd, rst);
input [31:0] i_data;
output [31:0] i_addr, d_addr, d_data_o;
input [31:0] d_data_i;
input clk, rst; // Active HIGH reset
output d_wr, d_rd;

// Opcodes (See ID stage for how bits [5:4] determine the FORMAT)
//
// Layout of an R-Format instruction
// +------+-----+-----+-----+-----+------+
// |  op  |  rs |  rt |  rd |shamt| func |
// +------+-----+-----+-----+-----+------+
// |      |     |     |     |     |      |
// 31   26|25 21|20 16|15 11|10  6|5     0
//
// Registers:
//   rs -> Source reg 1, can be shifted by setting appropiate bits in OP field
//   rt -> Source reg 2
//   rd -> Destination register of operation
//         Note that this is only written to if the write back flag
//         is set in the OP field
// 
// Layout of OP field (See CONTROL and ID stage for definitions)
// 5 4 3 2 1 0
// | | | | | +-> ALUOp3 (See ALU for details)
// | | | | +---> 1 = Force flags to ZCN bits in funct / 0 = ZCN set as result of OP
// | | | +-----> 1 = Write back to reg rd, 0 = Don't save operation result
// | | +-------> 0 = "Normal operation" / 1 = Load/store (the above bit determines
// | |               the operation -> 1 = load / 0 = store)
// | +---------> 0
// +-----------> 0
//
// Layout of FUNCT field (See ID stage for these definitions)
// 5 4 3 2 1 0
// | | | | | +-> 1 = update N flag
// | | | | +---> 1 = update C flag
// | | | +-----> 1 = update Z flag
// | | +-------> ALUOp0 (See ALU for details)
// | +---------> ALUOp1 (See ALU for details)
// +-----------> ALUOp2 (See ALU for details)
//   ****** NOTE:
//          If all bits of FUNCT are set then this is a JUMP instruction
//          which sets the PC to the value in rs
//
//
// Layout of I-Format
// +----+--+--------------------------+
// | op |cc|          SE_IMMD         |
// +----+--+--------------------------+
// |    |    \                        |
// 31 28|27 26|25                     0
//
// Layout of OP field (See CONTROL and ID stage for definitions)
// 3 2 1 0 
// | | | +-> 1 = Write back to reg rd, 0 = Don't save operation result
// | | +---> 1 = Branch on flag set, 0 = branch on flag clear
// +-+-----> 0 = R-format instruction (May include)
//           1 = I-format load immediate to register 0
//           2 = I-format branch
//           3 = J-format jump (Jump absolute)
//
// cc for load immediate is:
// 1 0
// +-+-> 01 - Required
//
// cc for branches is split as follows:
// 1 0
// +-+-> 0 = Branch on Z
//       1 = Branch on C
//       2 = Branch on N
//       3 = Branch Always
//
//
// Layout of JUMP J-Format
// +--+------------------------------+
// |op|           address            |
// +--+------------------------------+
// |   \                             |
// 31 30|29                          0
//
// Layout of OP field (See CONTROL and ID stage for definitions)
// 5 4 3 2 1 0
// | | +-+-+-+-> Top 4 bits of jump address
// +-+---------> 3 = Jump operation
//
// The "address" field is the target address left shifted two places
//
// Jump instruction: Jumps to the specified address and saves the current PC+4 to
//                   reg number 31
//
//


// Signals for HAZARD DETECTION UNIT
    // EXTERNAL
reg hd_if_id_flush;             // Set to clear the IR to be a NOP
reg hd_id_ex_flush;             // Set to disable stages following ID (this particular cycle as it moves through)
reg hd_if_pc_wr;                // Set to enable updating of PC

    // INTERNAL
reg hw_reg_conflict;            // High when approximately rt(ID/EX) == rs(IF/ID) or rt(ID/EX) == rt(IF/ID)


// Signals for FORWARDING UNIT
    // EXTERNAL
reg [1:0] fw_ex_rs_src;         // Mux select for ALU "a" input
reg [1:0] fw_ex_rt_src;         // Mux select for ALU "b" input
reg [1:0] fw_id_jump_rs;        // Mux select for R-format jump rs
wire fw_ex_z;                   // Mux select for Z flag (Between Z FF (0) and ALU Z ouptut (1))
wire fw_ex_c;                   // Mux select for C flag (Between C FF (0) and ALU C ouptut (1))
wire fw_ex_n;                   // Mux select for N flag (Between N FF (0) and ALU N ouptut (1))
reg fw_mem_ldsw;                // Mux select for consecutive mem load/store operation (WB->MEM)

    // INTERNAL
// [none]


// Signals for IF STAGE
wire [31:0] pc_next_val;        // To be fed into the PC on the next NEGEDGE of CLK
wire [31:0] pc_inc_val;         // Selected if the next address is to be fetched
wire pc_src_sel;                // Low = INC PC, High = result from ID stage

reg [31:0] pc;                  // Program Counter
reg [31:0] if_id_pipe_pc;       // Pipelined PC
reg [31:0] if_id_pipe_ir;       // Result from reading instruction memory

// Signals for ID STAGE
wire [31:0] d_reg_0, d_reg_1;
wire [31:0] ir_immd_se;         // Sign extension
wire [31:0] ir_immd_se_sh;      // Shifted sign extend (left, 2)
wire [31:0] pc_id_temp_branch_val;   // Value of the PC if a branch were to be taken
wire [31:0] pc_id_branch_val;   // Value to assign to PC after taking into account whether to take the branch
wire [31:0] pc_id_val;          // For when the ID stage must modify the PC (branch, jump)
wire [31:0] ir_addr_sh;         // Shifted immediate address for Jump & Link instruction
wire [31:0] id_pc_alu_mem;      // Muxed bus from MEM ALU out or memory read
wire [31:0] id_pc_reg_val;      // Value of the register to load the PC with
reg id_rfmt;                    // High when instruction is R-format
reg id_imfmt;                   // High when instruction is I-format SE IMMD load
reg id_ifmt;                    // High when instruction is I-format
reg id_jfmt;                    // High when instruction is J-format
reg id_do_branch;               // High when a branch should be taken
wire id_zf;                     // Z flag for branch logic (forwarded)
wire id_cf;                     // C flag for branch logic (forwarded)
wire id_nf;                     // N flag for branch logic (forwarded)
wire id_r_jump;                 // High when bits 5..0 are all high and R-format (00)
wire id_immd_load;              // High when instruction is an immediate se load

wire [5:0] ir_r_op;             // Opcode fields
wire [3:0] ir_i_op;
wire [1:0] ir_j_op;
wire [4:0] ir_rs;
wire [4:0] ir_rt;
wire [4:0] ir_rd;
wire [5:0] ir_funct;
wire [25:0] ir_immd;
wire [29:0] ir_addr;
wire [1:0] ir_cc;

reg [31:0] id_ex_pipe_reg_0, id_ex_pipe_reg_1;  // Outputs from reg file
reg [4:0] id_ex_pipe_rs, id_ex_pipe_rt, id_ex_pipe_rd;
reg [31:0] id_ex_pipe_immd_se;
reg id_ex_pipe_shop;            // Shift type operation
reg id_ex_pipe_alusrc;          // 1 on SE IMMD, 0 on REG_1
reg id_ex_pipe_memrd;           // 1 on read from mem
reg id_ex_pipe_memwr;           // 1 on write to mem
reg id_ex_pipe_wrreg;           // 1 on write to reg
    // Flag control lines:
    // Do not need to be separate signals from id_ex_pipe_immd_se, but makes it more readable
reg id_ex_pipe_wrzf;            // 1 to enable writing to Z flag
reg id_ex_pipe_wrcf;            // 1 to enable writing to C flag
reg id_ex_pipe_wrnf;            // 1 to enable writing to N flag
reg id_ex_pipe_forcef;          // 1 to enable forcing of ZCN flags to the ZCN bits of the opcode

// Signals for EX STAGE
wire [31:0] ex_alu_a;           // ALU "a" input value
wire [31:0] ex_alu_b;           // ALU "b" input value
wire [31:0] ex_alu_pre_a;       // ALU "a" input value before the ALUSrc mux
wire [3:0] ex_alu_op;           // ALU internal operation code
wire [31:0] ex_alu_rslt;        // ALU result
wire ex_zf_alu, ex_cf_alu, ex_nf_alu;   // Zero, Carry, Negative flags output from ALU
wire ex_zf, ex_cf, ex_nf;       // Zero, Carry, Negative flags input lines to the flag FFs
wire [5:0] ex_funct;            // Function code
wire [4:0] ex_shamt;            // Barrel shifter amount
wire ex_alu_cin;                // CIN input to the ALU. Set for CMP instruction, otherwise
                                // it represents the value of the flag_carry.

                                // For instructions which affect the flags:
reg flag_zero;                  // Zero flag (1 = previous operation was 0)
reg flag_carry;                 // Carry flag (1 = previous op resulted in a carry)
reg flag_negative;              // Negative flag (bit 31 of the previous ALU result)

reg [31:0] ex_mem_pipe_alu_rslt;    // ALU result (Also used as address in a MEMory access op)
reg [31:0] ex_mem_pipe_data;    // Data to be written to memory in a SW operation
reg [4:0] ex_mem_pipe_wb_reg;   // Reg to which to write back
reg ex_mem_pipe_memrd;          // High on a memory read
reg ex_mem_pipe_memwr;          // High on a memory write
reg ex_mem_pipe_wrreg;          // High when the reg in ex_mem_pipe_wb_reg needs to be written

// Signals for MEM STAGE
reg [31:0] mem_wb_pipe_memd;    // Data from memory
reg [31:0] mem_wb_pipe_alud;    // Data from ALU
reg [4:0] mem_wb_pipe_wb_reg;   // Register to which to write back
reg mem_wb_pipe_memrd;          // High when reading from memory
reg mem_wb_pipe_wrreg;          // High when writing back to a reg

// Signals for WB STAGE
wire [4:0] wb_addr;             // Register number to which to write back
wire [31:0] wb_data;            // Data to write to a register
wire wb_wr;                     // 1 = write, 0 = don't write


// ----------------- IF STAGE -----------------
// PC
always @(negedge clk)
begin
    if (rst)
    begin
        pc <= 32'b0;
    end
    else if (hd_if_pc_wr == 1'b1)
    begin
        pc <= pc_next_val;
    end
end

// PC Incrementer
zmips_n_adder #(.W(32)) ADD_PC_IF(.a(pc), .b(32'h4), .sum(pc_inc_val));
zmips_mux232 MUX_PC_IF(.a(pc_inc_val), .b(pc_id_val), .sel(pc_src_sel), .y(pc_next_val));

// Instruction Memory Interface
assign i_addr = pc;

// IF/ID connection pipeline register(s)
always @(negedge clk)
begin
    if (hd_if_pc_wr == 1'b1)
    begin
        if_id_pipe_pc <= pc_next_val;
    end

    if (hd_if_id_flush == 1'b1)
    begin
        if_id_pipe_ir <= 32'b0;
    end
    else if (hd_if_pc_wr) // The IR is only updated if the PC changes
    begin
        if_id_pipe_ir <= i_data;
    end
end

// ----------------- ID STAGE -----------------

assign ir_r_op = if_id_pipe_ir[31:26]; // Split IR into individual pieces
assign ir_i_op = if_id_pipe_ir[31:28];
assign ir_j_op = if_id_pipe_ir[31:30];
assign ir_cc = if_id_pipe_ir[27:26];
assign ir_rs = if_id_pipe_ir[25:21];
assign ir_rt = if_id_pipe_ir[20:16];
assign ir_rd = if_id_pipe_ir[15:11];
assign ir_funct = if_id_pipe_ir[5:0];
assign ir_immd = if_id_pipe_ir[25:0];
assign ir_addr = if_id_pipe_ir[29:0];

// Sign extend
assign ir_immd_se = {{6{ir_immd[25]}}, ir_immd};

// Shift immediate
assign ir_immd_se_sh = {ir_immd_se[29:0], 2'b00};

// Calculate branch address
zmips_n_adder #(.W(32)) ADD_PC_ID(.a(if_id_pipe_pc), .b(ir_immd_se_sh), .sum(pc_id_temp_branch_val));

// Deal with flag forwarding for branch decision
assign id_zf = fw_ex_z ? ex_zf : flag_zero;
assign id_cf = fw_ex_c ? ex_cf : flag_carry;
assign id_nf = fw_ex_n ? ex_nf : flag_negative;
always @(*)
begin
    id_do_branch = 1'b0;
    case (ir_cc)
    2'b00: id_do_branch = id_zf ~^ ir_i_op[1];
    2'b01: id_do_branch = id_cf ~^ ir_i_op[1];
    2'b10: id_do_branch = id_nf ~^ ir_i_op[1];
    2'b11: id_do_branch = 1'b1;
    endcase
end

// Finally output the branch decision
zmips_mux232 MUX_PC_BRANCH(.a(if_id_pipe_pc), .b(pc_id_temp_branch_val), .sel(id_do_branch), .y(pc_id_branch_val));

// Shift immediate address
assign ir_addr_sh = {ir_addr[29:0], 2'b00};

// Determine opcode data layout
always @(*)
begin
    id_rfmt  = 1'b0;
    id_imfmt = 1'b0;
    id_ifmt  = 1'b0;
    id_jfmt  = 1'b0;

    casex (ir_j_op)
        2'b00: id_rfmt  = 1'b1;
        2'b01: id_imfmt = 1'b1;
        2'b10: id_ifmt  = 1'b1;
        2'b11: id_jfmt  = 1'b1;
    endcase
end

// If the format is I-branch or J-Format or (R-format and all funct bits are set)
// then the PC will be updated with the output of tbe MUX_PC_ID mux
assign id_r_jump = (&ir_funct) & id_rfmt;
assign pc_src_sel = id_r_jump | id_jfmt | id_ifmt;

zmips_mux232 MUX_PC_ALUMEM(
        .a(ex_mem_pipe_alu_rslt),   // ALU result from previous stage
        .b(d_data_i),               // Result from reading memory
        .sel(ex_mem_pipe_memrd),
        .y(id_pc_alu_mem)
    );

// Forwarding of the jump destination source reg for an R-Format jump
zmips_mux432 MUX_PC_REG(
        .a(d_reg_0),            // Direct from reg
        .b(ex_alu_rslt),        // From ALU output (EX stage)
        .c(id_pc_alu_mem),      // From MEM stage (memory or alu result)
        .d(wb_data),            // Data from wb stage
        .sel(fw_id_jump_rs),
        .y(id_pc_reg_val)
    );

// Final mux to decide what gets fed back to IF stage
zmips_mux432 MUX_PC_ID(
        .a(id_pc_reg_val),      // rs (R-format)
        .b(32'hx),              // DEBUG (Should never be loaded into the PC)
        .c(pc_id_branch_val),   // Immediate sign-extended relative (I-format)
        .d(ir_addr_sh),         // Address from instruction (J-format)
        .sel(ir_j_op),          // Top 2 bits of opcode field determine source
        .y(pc_id_val)           // Feedback to IF
    );

// Reg file
zmips_regfile RF0(
        .addr_0(ir_rs), 
        .addr_1(ir_rt), 
        .wr_addr(wb_addr), 
        .wr_data(wb_data), 
        .wr(wb_wr),
        .clk(clk), 
        .data_0(d_reg_0), 
        .data_1(d_reg_1),
        .pc_val(pc),            // New PC, not the old one which is in the IF/ID pipeline reg
        .pc_wr(id_jfmt)         // Write to PC shadow reg when doing a JL instruction
    );

// For immediate load operations, set the rd to 0
assign id_immd_load = id_imfmt & ir_i_op[2];

// ID/EX connection pipeline register(s)
always @(negedge clk)
begin
    id_ex_pipe_reg_0 <= d_reg_0;        // Pass along reg file outputs
    id_ex_pipe_reg_1 <= d_reg_1;
    id_ex_pipe_rs <= ir_rs;             // Pass along which regs are in use
    id_ex_pipe_rt <= ir_rt;             // rt is needed for forwarding
    id_ex_pipe_rd <= ir_rd & {5{!id_immd_load}}; // Zero rd on immediate se load
    id_ex_pipe_immd_se <= ir_immd_se;   // Pass along sign extended immediate
    id_ex_pipe_shop <= ir_r_op[0];      // Pass along upper bit of ALUOp
    
    if (hd_id_ex_flush == 1'b1 || (id_rfmt|id_imfmt) == 1'b0) // If a hazard (or branch/jump) is detected, knock out the next stage
    begin
        id_ex_pipe_alusrc <= 1'b0;
        id_ex_pipe_memrd <= 1'b0;
        id_ex_pipe_memwr <= 1'b0; 
        id_ex_pipe_wrreg <= 1'b0;
        id_ex_pipe_wrzf <= 1'b0;
        id_ex_pipe_wrcf <= 1'b0;
        id_ex_pipe_wrnf <= 1'b0;
    end
    else                                    // Otherwise, we are good to go
    begin   
        id_ex_pipe_alusrc <= id_immd_load;              // Set ALU a source to SE_IMMD if I-Format
        id_ex_pipe_memrd <= ir_r_op[3] & ir_r_op[2];    // Set mem read on LOAD instruction
        id_ex_pipe_memwr <= ir_r_op[3] & !ir_r_op[2];   // Set mem write on STORE instruction
        id_ex_pipe_wrreg <= (id_rfmt | id_imfmt) & ir_r_op[2]; // Write back to reg
        id_ex_pipe_wrzf <= id_rfmt & ir_funct[2];       // Only change Z flag for R-Type instructions
        id_ex_pipe_wrcf <= id_rfmt & ir_funct[1];       // Only change C flag for R-Type instructions
        id_ex_pipe_wrnf <= id_rfmt & ir_funct[0];       // Only change N flag for R-Type instructions
        id_ex_pipe_forcef <= id_rfmt & ir_r_op[1];      // Only allow forcing of flags in R-format instruction
    end
end

// ----------------- EX STAGE -----------------

assign ex_funct = id_ex_pipe_immd_se[5:0];
assign ex_shamt = id_ex_pipe_immd_se[10:6];
assign ex_alu_op = {id_ex_pipe_shop, ex_funct[5:3] & {3{!id_ex_pipe_alusrc}}}; // Pass through on immd se load

// ALU "a" input mux
zmips_mux432 ALU_A_MUX(
        .a(id_ex_pipe_reg_0),
        .b(wb_data),
        .c(ex_mem_pipe_alu_rslt),
        .d(32'bXX), // DEBUG
        .sel(fw_ex_rs_src),
        .y(ex_alu_pre_a)
    );

// ALUSrc mux for "a" input
// Selects between reg/forwarded data and the SE IMMD data
zmips_mux232 ALU_SRC_MUX(.a(ex_alu_pre_a), .b(id_ex_pipe_immd_se), .sel(id_ex_pipe_alusrc), .y(ex_alu_a));

// ALU "b" input mux
zmips_mux432 ALU_B_MUX(
        .a(id_ex_pipe_reg_1),
        .b(wb_data),
        .c(ex_mem_pipe_alu_rslt),
        .d(32'bXX), // DEBUG
        .sel(fw_ex_rt_src),
        .y(ex_alu_b)
    );

// Handle CIN to ALU since CMP needs it set to perform the correct subtraction
// (CIN) is an inverted borrow)
// Since CMP does not write back, this will set CIN to 1
assign ex_alu_cin = (!id_ex_pipe_wrreg) | flag_carry;

zmips_alu ALU0(
        .a(ex_alu_a),
        .b(ex_alu_b),
        .op(ex_alu_op),
        .y(ex_alu_rslt),
        .shamt(ex_shamt),
        .cin(ex_alu_cin),
        .zero(ex_zf_alu),
        .cout(ex_cf_alu)
    );

// Handle negative flag input line
assign ex_nf_alu = ex_alu_rslt[31];

// If instruction is forcing the flag states, use those instead of the ALU result
assign ex_zf = (id_ex_pipe_forcef == 1'b1) ? id_ex_pipe_wrzf : ex_zf_alu; 
assign ex_cf = (id_ex_pipe_forcef == 1'b1) ? id_ex_pipe_wrcf : ex_cf_alu; 
assign ex_nf = (id_ex_pipe_forcef == 1'b1) ? id_ex_pipe_wrnf : ex_nf_alu; 

// Not a pipeline reg, just state flags for the EX stage (and ID)
always @(negedge clk)
begin
    // Only update flags when their ID/EX enable line is active
    if (id_ex_pipe_wrzf == 1'b1 || id_ex_pipe_forcef == 1'b1)
    begin
        flag_zero <= ex_zf;
    end
    if (id_ex_pipe_wrcf == 1'b1 || id_ex_pipe_forcef == 1'b1)
    begin
        flag_carry <= ex_cf;
    end
    if (id_ex_pipe_wrnf == 1'b1 || id_ex_pipe_forcef == 1'b1)
    begin
        flag_negative <= ex_nf;
    end
end

// Pipeline regs for EX/MEM stage
always @(negedge clk)
begin
    ex_mem_pipe_alu_rslt <= ex_alu_rslt;    // Save ALU result for stage (to be used as the address in a MEMory access)
    ex_mem_pipe_data <= ex_alu_b;           // Also the pre-immediate muxed B input (to be used as the data to write if doing a SW instructions)
    ex_mem_pipe_wb_reg <= id_ex_pipe_rd;    // Save the reg which is to be used for WB stage
    ex_mem_pipe_memrd <= id_ex_pipe_memrd;
    ex_mem_pipe_memwr <= id_ex_pipe_memwr;
    ex_mem_pipe_wrreg <= id_ex_pipe_wrreg;
end


// ----------------- MEM STAGE -----------------

// Data memory interface
assign d_addr = ex_mem_pipe_alu_rslt;
assign d_wr = ex_mem_pipe_memwr;
assign d_rd = ex_mem_pipe_memrd;

// For forwarding from WB stage (consecutive LW/SW on same reg)
zmips_mux232 MUX_DATA_O(.a(ex_mem_pipe_data), .b(mem_wb_pipe_memd), .sel(fw_mem_ldsw), .y(d_data_o));

// MEM/WB pipeline regs
always @(negedge clk)
begin
    mem_wb_pipe_memd <= d_data_i;               // Data in from the data memory
    mem_wb_pipe_alud <= ex_mem_pipe_alu_rslt;   // Data from ALU in EX stage
    mem_wb_pipe_memrd <= ex_mem_pipe_memrd;     // Reading from memory
    mem_wb_pipe_wrreg <= ex_mem_pipe_wrreg;     // Writing to a reg
    mem_wb_pipe_wb_reg <= ex_mem_pipe_wb_reg;   // Reg to which to write back
end


// ----------------- WB STAGE -----------------

// Select the data source to write back
zmips_mux232 WB_MUX(.a(mem_wb_pipe_alud), .b(mem_wb_pipe_memd), .sel(mem_wb_pipe_memrd), .y(wb_data));

assign wb_addr = mem_wb_pipe_wb_reg;

assign wb_wr = mem_wb_pipe_wrreg;


// ----------------- HAZARD DETECTION -----------------


// wire hd_if_id_flush;            // Set to clear the IR to be a NOP
// wire hd_id_ex_flush;            // Set to disable stages following ID (this particular cycle as it moves through)
// wire hd_if_pc_wr;               // Set to enable updating of PC

// Check for LD register use conflicts
always @(*)
begin
    hw_reg_conflict = 1'b0;
    if (id_ex_pipe_memrd == 1'b1 &&
        ((id_ex_pipe_rd == ir_rs) || ((id_ex_pipe_rd == ir_rt) && id_r_jump == 1'b0)))
    begin
        hw_reg_conflict = 1'b1;
    end

end

// Signal pipeline stages
always @(posedge clk)
begin
    hd_id_ex_flush <= hw_reg_conflict;
    hd_if_pc_wr <= (~hw_reg_conflict) | rst;                 // Only update PC when there is not a register conflict
    // NOP the IF stage when a branch or jump is in ID stage (stall on every jump or branch 1 cycle)
    //    OR there is no register conflicts and it is a R-format jump
    hd_if_id_flush <= (~(id_rfmt|id_imfmt)) | ((~hw_reg_conflict) & id_r_jump);
end

// ----------------- FORWARDING CONTROL -----------------


// Forward the flags if the previous instruction (the one currently in EX
// will be modifing the relevant flag)
assign fw_ex_z = id_ex_pipe_wrzf | id_ex_pipe_forcef;
assign fw_ex_c = id_ex_pipe_wrcf | id_ex_pipe_forcef;
assign fw_ex_n = id_ex_pipe_wrnf | id_ex_pipe_forcef;

// Check for forwarding hazards
always @(*)
begin
    fw_ex_rs_src = 2'b00;           // Default to just reading directly from the reg file
    fw_ex_rt_src = 2'b00;
    fw_mem_ldsw = 1'b0;             // Default: don't forward memory data read in the last cycle to memory stage
    fw_id_jump_rs = 2'b00;

    // Check for forwarding of EX rs
    // EX hazard (forward from previous ALU result)
    if (ex_mem_pipe_wrreg == 1'b1 && (ex_mem_pipe_wb_reg == id_ex_pipe_rs))
    begin
        fw_ex_rs_src = 2'b10;
    end
    // MEM hazard (forward from memory or previous previous ALU result)
    else if (mem_wb_pipe_wrreg == 1'b1 && (mem_wb_pipe_wb_reg == id_ex_pipe_rs))
    begin
        fw_ex_rs_src = 2'b01;
    end

    // Check for forwarding of EX rt
    // EX hazard (forward from previous ALU result)
    if (ex_mem_pipe_wrreg == 1'b1 && (ex_mem_pipe_wb_reg == id_ex_pipe_rt))
    begin
        fw_ex_rt_src = 2'b10;
    end
    // MEM hazard (forward from memory or previous previous ALU result)
    else if (mem_wb_pipe_wrreg == 1'b1 && (mem_wb_pipe_wb_reg == id_ex_pipe_rt))
    begin
        fw_ex_rt_src = 2'b01;
    end

    // Check for consecutive LW/SW on the same reg
    if (mem_wb_pipe_wb_reg == ex_mem_pipe_wb_reg && mem_wb_pipe_memrd == 1'b1 && ex_mem_pipe_wrreg == 1'b1)
    begin
        fw_mem_ldsw = 1'b1;
    end

    // Check for R-format jump register dependencies
    if (id_r_jump == 1'b1 && id_ex_pipe_wrreg == 1'b1 && (id_ex_pipe_rd == ir_rs))
    begin
        fw_id_jump_rs = 2'b01; // ALU result
    end
    else if (id_r_jump == 1'b1 && ex_mem_pipe_wrreg == 1'b1 && (ex_mem_pipe_wb_reg == ir_rs))
    begin
        fw_id_jump_rs = 2'b10; // Prev ALU result
    end
    else if (id_r_jump == 1'b1 && mem_wb_pipe_wrreg == 1'b1 && (mem_wb_pipe_wb_reg == ir_rs))
    begin
        fw_id_jump_rs = 2'b11; // Write back result
    end

end

endmodule