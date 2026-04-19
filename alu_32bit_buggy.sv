// =============================================================================
// File        : alu_32bit_buggy.sv
// Description : PPA-Optimised 32-bit ALU — identical to alu_32bit.sv except
//               for 3 deliberately injected bugs listed below.
// Reset       : Active-low SYNCHRONOUS reset (posedge clk only sensitivity).
// =============================================================================

// -----------------------------------------------------------------------------
// Package: alu_pkg
// Opcode encoding matches JSON specification (0-11).
// Names are prefixed ALU_ to avoid clashes with SystemVerilog keywords.
// -----------------------------------------------------------------------------
package alu_pkg;
    typedef enum logic [3:0] {
        ALU_ADD = 4'd0,
        ALU_SUB = 4'd1,
        ALU_AND = 4'd2,
        ALU_OR  = 4'd3,
        ALU_XOR = 4'd4,
        ALU_NOT = 4'd5,
        ALU_SLL = 4'd6,
        ALU_SRL = 4'd7,
        ALU_SRA = 4'd8,
        ALU_MUL = 4'd9,
        ALU_DIV = 4'd10,
        ALU_MOD = 4'd11
    } alu_op_t;
endpackage : alu_pkg

// =================================================================
// FILE: alu_32bit_buggy.sv
// PURPOSE: Intentionally buggy ALU for AI loopback demonstration
// BUG 1: flag_ovf uses comb_carry instead of ovf_flag (Section 7)
// BUG 2: DIV/MOD guard checks operand_b instead of b_gated (Section 5)
// BUG 3: shift_fill=0 always — SRA has no sign extension (Section 3)
// Expected FAIL count when run against alu_32bit_tb.sv: 5 tests
// =================================================================

// -----------------------------------------------------------------------------
// Module: alu_32bit
// -----------------------------------------------------------------------------
module alu_32bit
    import alu_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,       // Active-low synchronous reset
    input  alu_op_t     alu_op,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [4:0]  shamt,
    output logic [31:0] result,
    output logic        flag_zero,
    output logic        flag_neg,
    output logic        flag_carry,
    output logic        flag_ovf
);

    // =========================================================================
    // PPA-POWER: operand isolation
    // =========================================================================
    logic        is_shift;   // PPA-POWER: operand isolation
    logic        is_arith;   // PPA-POWER: operand isolation
    logic        needs_b;    // PPA-POWER: operand isolation
    logic [31:0] b_gated;    // PPA-POWER: operand isolation
    logic [4:0]  sh_gated;   // PPA-POWER: operand isolation

    assign is_shift = (alu_op == ALU_SLL) | (alu_op == ALU_SRL) | (alu_op == ALU_SRA);
    assign is_arith = (alu_op == ALU_ADD) | (alu_op == ALU_SUB);
    assign needs_b  = ~(alu_op == ALU_NOT) & ~is_shift;
    assign b_gated  = needs_b  ? operand_b : 32'b0;
    assign sh_gated = is_shift ? shamt      : 5'b0;

    // =========================================================================
    // PPA-AREA: shared adder
    // =========================================================================
    logic        do_sub;     // PPA-AREA: shared adder
    logic [31:0] b_inv;      // PPA-AREA: shared adder
    logic [32:0] add_out;    // PPA-AREA: shared adder
    logic        ovf_flag;   // PPA-AREA: shared adder

    assign do_sub  = (alu_op == ALU_SUB);
    assign b_inv   = b_gated ^ {32{do_sub}};
    assign add_out = {1'b0, operand_a} + {1'b0, b_inv} + {32'b0, do_sub};
    assign ovf_flag = (~(operand_a[31] ^ b_inv[31])) & (operand_a[31] ^ add_out[31]);

    // =========================================================================
    // PPA-AREA: unified barrel shifter
    // PPA-PERF: 5-level mux tree
    // =========================================================================

    // -- Direction and fill ---------------------------------------------------
    logic        shift_left;    // PPA-AREA: unified barrel shifter
    logic        shift_fill;    // PPA-AREA: unified barrel shifter

    assign shift_left = (alu_op == ALU_SLL);
    // BUG 3: shift_fill always 0 — SRA becomes SRL, sign extension disabled
    assign shift_fill = 1'b0;

    // -- Input bit-reversal for SLL (genvar loop 1) ---------------------------
    logic [31:0] shift_in;      // PPA-AREA: unified barrel shifter

    genvar gi;
    generate
        for (gi = 0; gi < 32; gi++) begin : gen_shift_in
            // PPA-AREA: unified barrel shifter
            assign shift_in[gi] = shift_left ? operand_a[31-gi] : operand_a[gi];
        end
    endgenerate

    // -- 5-level right-shift mux tree -----------------------------------------
    logic [31:0] sr0;           // PPA-PERF: 5-level mux tree
    logic [31:0] sr1;           // PPA-PERF: 5-level mux tree
    logic [31:0] sr2;           // PPA-PERF: 5-level mux tree
    logic [31:0] sr3;           // PPA-PERF: 5-level mux tree
    logic [31:0] shift_out_r;   // PPA-PERF: 5-level mux tree

    assign sr0        = sh_gated[0] ? {shift_fill,        shift_in[31:1]}    : shift_in;
    assign sr1        = sh_gated[1] ? {{2{shift_fill}},   sr0[31:2]}         : sr0;
    assign sr2        = sh_gated[2] ? {{4{shift_fill}},   sr1[31:4]}         : sr1;
    assign sr3        = sh_gated[3] ? {{8{shift_fill}},   sr2[31:8]}         : sr2;
    assign shift_out_r = sh_gated[4] ? {{16{shift_fill}}, sr3[31:16]}        : sr3;

    // -- Output bit-reversal for SLL (genvar loop 2) --------------------------
    logic [31:0] shift_result;  // PPA-AREA: unified barrel shifter

    genvar go;
    generate
        for (go = 0; go < 32; go++) begin : gen_shift_out
            // PPA-AREA: unified barrel shifter
            assign shift_result[go] = shift_left ? shift_out_r[31-go] : shift_out_r[go];
        end
    endgenerate

    // =========================================================================
    // PPA-AREA: signed multiply via unsigned + negate
    // =========================================================================
    logic        a_neg_m;       // PPA-AREA: signed multiply via unsigned + negate
    logic        b_neg_m;       // PPA-AREA: signed multiply via unsigned + negate
    logic        prod_neg;      // PPA-AREA: signed multiply via unsigned + negate
    logic [31:0] a_abs;         // PPA-AREA: signed multiply via unsigned + negate
    logic [31:0] b_abs;         // PPA-AREA: signed multiply via unsigned + negate
    logic [63:0] prod_u;        // PPA-AREA: signed multiply via unsigned + negate
    logic [31:0] prod_lo;       // PPA-AREA: signed multiply via unsigned + negate
    logic [31:0] mul_result;    // PPA-AREA: signed multiply via unsigned + negate

    assign a_neg_m   = operand_a[31];
    assign b_neg_m   = b_gated[31];
    assign prod_neg  = a_neg_m ^ b_neg_m;
    assign a_abs     = a_neg_m ? (~operand_a + 32'd1) : operand_a;
    assign b_abs     = b_neg_m ? (~b_gated  + 32'd1) : b_gated;
    assign prod_u    = {32'b0, a_abs} * {32'b0, b_abs};   // Named 64-bit wire
    assign prod_lo   = prod_u[31:0];                        // Slice named wire
    assign mul_result = prod_neg ? (~prod_lo + 32'd1) : prod_lo;

    // =========================================================================
    // PPA-PERF: unique case, priority-free mux synthesis
    // =========================================================================
    logic [31:0] comb_result;
    logic        comb_carry;

    always_comb begin : result_mux
        // PPA-PERF: unique case, priority-free mux synthesis
        comb_result = 32'b0;    // Default — prevents latches
        comb_carry  = 1'b0;     // Default — prevents latches

        unique case (alu_op)
            ALU_ADD,
            ALU_SUB : begin
                comb_result = add_out[31:0];
                comb_carry  = add_out[32];
            end
            ALU_AND : comb_result = operand_a & b_gated;
            ALU_OR  : comb_result = operand_a | b_gated;
            ALU_XOR : comb_result = operand_a ^ b_gated;
            ALU_NOT : comb_result = ~operand_a;
            ALU_SLL,
            ALU_SRL,
            ALU_SRA : comb_result = shift_result;
            ALU_MUL : comb_result = mul_result;
            ALU_DIV : begin
                // BUG 2: checks operand_b instead of b_gated — wrong signal in guard
                if (operand_b == 32'b0)
                    comb_result = 32'b0;
                else
                    comb_result = 32'($signed(operand_a) / $signed(b_gated));
            end
            ALU_MOD : begin
                // BUG 2: checks operand_b instead of b_gated — wrong signal in guard
                if (operand_b == 32'b0)
                    comb_result = 32'b0;
                else
                    comb_result = 32'($signed(operand_a) % $signed(b_gated));
            end
            default : begin
                comb_result = 32'b0;
                comb_carry  = 1'b0;
            end
        endcase
    end : result_mux

    // =========================================================================
    // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    // =========================================================================
    alu_op_t     prev_op;   // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    logic [31:0] prev_a;    // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    logic [31:0] prev_b;    // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    logic [4:0]  prev_sh;   // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    logic        inp_changed; // PPA-POWER: clock gate enable, ICG cell inferred by synthesis
    logic        clk_en;    // PPA-POWER: clock gate enable, ICG cell inferred by synthesis

    always_ff @(posedge clk) begin : prev_reg
        if (!rst_n) begin
            prev_op <= ALU_ADD;
            prev_a  <= 32'b0;
            prev_b  <= 32'b0;
            prev_sh <= 5'b0;
        end else begin
            prev_op <= alu_op;
            prev_a  <= operand_a;
            prev_b  <= operand_b;
            prev_sh <= shamt;
        end
    end : prev_reg

    assign inp_changed = (operand_a != prev_a) | (operand_b != prev_b) |
                         (alu_op    != prev_op) | (shamt     != prev_sh);
    assign clk_en = inp_changed | ~rst_n;

    // =========================================================================
    // Output registers — synchronous active-low reset, clock-gate enabled
    // =========================================================================
    always_ff @(posedge clk) begin : out_reg
        if (!rst_n) begin
            result     <= 32'b0;
            flag_zero  <= 1'b0;
            flag_neg   <= 1'b0;
            flag_carry <= 1'b0;
            flag_ovf   <= 1'b0;
        end else if (clk_en) begin
            result     <= comb_result;
            flag_zero  <= (comb_result == 32'b0);
            flag_neg   <= comb_result[31];
            flag_carry <= is_arith ? comb_carry : 1'b0;
            // BUG 1: uses comb_carry instead of ovf_flag — carry != overflow
            flag_ovf   <= is_arith ? comb_carry : 1'b0;
        end
    end : out_reg

endmodule : alu_32bit
