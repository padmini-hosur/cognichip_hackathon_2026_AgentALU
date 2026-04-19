// =============================================================================
// File        : alu_assertions.sv
// Description : Companion SVA bind file for alu_32bit.
//               Binds alu_assertions into every instance of alu_32bit without
//               modifying the DUT source.  Covers:
//                 - Reset behaviour (outputs cleared)
//                 - Output stability when clock-gated (clk_en=0)
//                 - Arithmetic result / flag correctness
//                 - Overflow flag encoding
//                 - Divide/modulo by-zero guard
//                 - Flag mutual exclusivity / sanity
// Reset       : Active-low SYNCHRONOUS reset (matches DUT).
// Usage       : add alu_assertions.sv to compile list; the bind statement at
//               the bottom auto-attaches to every alu_32bit instance.
// =============================================================================

`timescale 1ns/1ps

import alu_pkg::*;

// -----------------------------------------------------------------------------
// Module: alu_assertions
// Ports mirror the I/O + selected internal signals of alu_32bit.
// ovf_flag added to enable precise signed-overflow correctness checking (A11).
// -----------------------------------------------------------------------------
module alu_assertions (
    input  logic        clk,
    input  logic        rst_n,
    input  alu_op_t     alu_op,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [4:0]  shamt,
    input  logic [31:0] result,
    input  logic        flag_zero,
    input  logic        flag_neg,
    input  logic        flag_carry,
    input  logic        flag_ovf,
    input  logic        clk_en,
    input  logic        is_arith,
    input  logic        ovf_flag    // Internal combinational overflow detector
);

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------
    logic is_div_mod;
    assign is_div_mod = (alu_op == ALU_DIV) || (alu_op == ALU_MOD);

    // Registered copies of outputs — used to check stability when clk_en=0
    logic [31:0] result_prev;
    logic        flag_zero_prev;
    logic        flag_neg_prev;
    logic        flag_carry_prev;
    logic        flag_ovf_prev;

    always_ff @(posedge clk) begin
        result_prev    <= result;
        flag_zero_prev <= flag_zero;
        flag_neg_prev  <= flag_neg;
        flag_carry_prev <= flag_carry;
        flag_ovf_prev  <= flag_ovf;
    end

    // =========================================================================
    // GROUP 1 — Reset assertions
    // After synchronous reset de-asserts, on the very clock edge where rst_n=0
    // the outputs must be cleared.
    // =========================================================================

    // A1: result is 0 while reset is asserted
    ast_reset_result_zero : assert property (
        @(posedge clk)
        (!rst_n) |-> (result == 32'b0)
    ) else $warning("ASSERT FAIL ast_reset_result_zero: result=%0h during reset", result);

    // A2: all flags cleared during reset
    ast_reset_flags_zero : assert property (
        @(posedge clk)
        (!rst_n) |-> (!flag_zero && !flag_neg && !flag_carry && !flag_ovf)
    ) else $warning("ASSERT FAIL ast_reset_flags_zero: flags not cleared during reset Z=%b N=%b C=%b V=%b",
                  flag_zero, flag_neg, flag_carry, flag_ovf);

    // =========================================================================
    // GROUP 2 — Clock-gate stability
    // When clk_en=0 and not in reset, outputs must hold their previous value.
    // =========================================================================

    // A3: result stable when clock-gated
    ast_clkgate_result_stable : assert property (
        @(posedge clk) disable iff (!rst_n)
        (!clk_en) |=> (result == result_prev)
    ) else $warning("ASSERT FAIL ast_clkgate_result_stable: result changed while clk_en=0 (prev=%0h now=%0h)",
                  result_prev, result);

    // A4: flags stable when clock-gated
    ast_clkgate_flags_stable : assert property (
        @(posedge clk) disable iff (!rst_n)
        (!clk_en) |=> (flag_zero  == flag_zero_prev  &&
                       flag_neg   == flag_neg_prev    &&
                       flag_carry == flag_carry_prev  &&
                       flag_ovf   == flag_ovf_prev)
    ) else $warning("ASSERT FAIL ast_clkgate_flags_stable: flags changed while clk_en=0");

    // =========================================================================
    // GROUP 3 — flag_zero correctness
    // flag_zero must equal (result == 0) one cycle after clk_en=1.
    // =========================================================================

    // A5: flag_zero set iff result is zero
    ast_flag_zero_correct : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en) |=> (flag_zero == (result == 32'b0))
    ) else $warning("ASSERT FAIL ast_flag_zero_correct: flag_zero=%b but result=%0h",
                  flag_zero, result);

    // =========================================================================
    // GROUP 4 — flag_neg correctness
    // flag_neg must equal result[31] (MSB = sign bit).
    // =========================================================================

    // A6: flag_neg equals MSB of result
    ast_flag_neg_correct : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en) |=> (flag_neg == result[31])
    ) else $warning("ASSERT FAIL ast_flag_neg_correct: flag_neg=%b but result[31]=%b",
                  flag_neg, result[31]);

    // =========================================================================
    // GROUP 5 — Arithmetic flag suppression
    // flag_carry and flag_ovf must be 0 for non-arithmetic operations.
    // =========================================================================

    // A7: carry suppressed for non-arithmetic ops
    ast_carry_suppressed_non_arith : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && !is_arith) |=> (flag_carry == 1'b0)
    ) else $warning("ASSERT FAIL ast_carry_suppressed_non_arith: flag_carry=%b for op=%s",
                  flag_carry, alu_op.name());

    // A8: overflow suppressed for non-arithmetic ops
    ast_ovf_suppressed_non_arith : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && !is_arith) |=> (flag_ovf == 1'b0)
    ) else $warning("ASSERT FAIL ast_ovf_suppressed_non_arith: flag_ovf=%b for op=%s",
                  flag_ovf, alu_op.name());

    // =========================================================================
    // GROUP 6 — Divide/Modulo by-zero guard
    // When operand_b==0 and the op is DIV or MOD, result must be 0.
    // =========================================================================

    // A9: DIV/MOD by zero yields result=0
    ast_div_mod_by_zero_result : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && is_div_mod && (operand_b == 32'b0)) |=>
            (result == 32'b0)
    ) else $warning("ASSERT FAIL ast_div_mod_by_zero_result: op=%s divisor=0 but result=%0h",
                  alu_op.name(), result);

    // A10: DIV/MOD by zero sets flag_zero
    ast_div_mod_by_zero_flag : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && is_div_mod && (operand_b == 32'b0)) |=>
            (flag_zero == 1'b1)
    ) else $warning("ASSERT FAIL ast_div_mod_by_zero_flag: op=%s divisor=0 but flag_zero=0",
                  alu_op.name());

    // =========================================================================
    // GROUP 7 — Overflow encoding correctness
    // A11 (STRENGTHENED): flag_ovf registered value must exactly match the
    //   combinational ovf_flag from the previous cycle when is_arith was true.
    //   This catches BOTH false positives (carry=1, overflow=0) AND false
    //   negatives (carry=0, overflow=1) — the original weak A11 caught neither.
    // A12 (NEW): flag_ovf must be 0 exactly one cycle after a non-arith op.
    //   Complementary to A11: ensures no ovf leakage across op boundaries.
    // =========================================================================

    // A11 STRENGTHENED: flag_ovf must equal $past(ovf_flag) after arith ops
    //   WAS: (flag_ovf) |-> $past(is_arith, 1)  [only checked direction, not value]
    //   NOW: directly verifies the registered flag matches the combinational signal
    ast_ovf_equals_ovf_flag : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && is_arith) |=> (flag_ovf == $past(ovf_flag, 1))
    ) else $warning("ASSERT FAIL ast_ovf_equals_ovf_flag: flag_ovf=%b but ovf_flag was %b (is_arith cycle)",
                  flag_ovf, $past(ovf_flag, 1));

    // A13 (NEW): flag_ovf must be 0 one cycle after non-arith op
    ast_ovf_zero_after_non_arith : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && !is_arith) |=> (flag_ovf == 1'b0)
    ) else $warning("ASSERT FAIL ast_ovf_zero_after_non_arith: flag_ovf=%b after non-arith op",
                  flag_ovf);

    // A14: carry can only be asserted for arithmetic operations
    ast_carry_implies_arith : assert property (
        @(posedge clk) disable iff (!rst_n)
        (flag_carry) |-> $past(is_arith, 1)
    ) else $warning("ASSERT FAIL ast_carry_implies_arith: flag_carry set for non-arith op");

    // =========================================================================
    // GROUP 9 — Arithmetic result correctness (reference model checks)
    // These check the actual computed result against a combinational reference,
    // catching bugs where the DUT output diverges from the correct value.
    // =========================================================================

    // A15: SRA of a negative value must produce a negative result (sign-extend)
    //   If operand_a[31]=1 and we SRA by any amount, result[31] must stay 1.
    //   This directly catches BUG 3 (shift_fill=0 kills sign propagation).
    ast_sra_neg_signext : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && (alu_op == ALU_SRA) && operand_a[31]) |=>
            (result[31] == 1'b1)
    ) else $warning("ASSERT FAIL ast_sra_neg_signext: SRA of negative value did not sign-extend: result=%0h",
                  result);

    // A16: ADD result must equal operand_a + operand_b (combinational reference)
    //   Uses $past to compare the registered result against what the adder
    //   should have produced on the previous cycle.
    ast_add_result_correct : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && (alu_op == ALU_ADD)) |=>
            (result == ($past(operand_a) + $past(operand_b)))
    ) else $warning("ASSERT FAIL ast_add_result_correct: ADD result=%0h expected=%0h",
                  result, ($past(operand_a) + $past(operand_b)));

    // A17: SUB result must equal operand_a - operand_b (combinational reference)
    ast_sub_result_correct : assert property (
        @(posedge clk) disable iff (!rst_n)
        (clk_en && (alu_op == ALU_SUB)) |=>
            (result == ($past(operand_a) - $past(operand_b)))
    ) else $warning("ASSERT FAIL ast_sub_result_correct: SUB result=%0h expected=%0h",
                  result, ($past(operand_a) - $past(operand_b)));

    // =========================================================================
    // GROUP 8 — Covers (ensure interesting scenarios are exercised)
    // =========================================================================

    // C1: ADD with carry-out observed
    cov_add_carry : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_ADD) && flag_carry
    );

    // C2: ADD with overflow observed
    cov_add_ovf : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_ADD) && flag_ovf
    );

    // C3: SUB with borrow (carry=0) observed
    cov_sub_borrow : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_SUB) && !flag_carry
    );

    // C4: SUB with overflow observed
    cov_sub_ovf : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_SUB) && flag_ovf
    );

    // C5: Zero result observed for ADD
    cov_add_zero : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_ADD) && flag_zero
    );

    // C6: Negative result observed for shift
    cov_shift_neg : cover property (
        @(posedge clk) disable iff (!rst_n)
        ((alu_op == ALU_SLL) || (alu_op == ALU_SRL) || (alu_op == ALU_SRA)) && flag_neg
    );

    // C7: DIV by zero guard triggered
    cov_div_by_zero : cover property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == ALU_DIV) && (operand_b == 32'b0)
    );

    // C8: clk_en=0 observed (clock gate active)
    cov_clk_gate_active : cover property (
        @(posedge clk) disable iff (!rst_n)
        (!clk_en)
    );

endmodule : alu_assertions

// =============================================================================
// Bind statement — attaches alu_assertions to every alu_32bit instance.
// The port map uses DUT internal signals for clk_en and is_arith.
// =============================================================================
bind alu_32bit alu_assertions u_alu_assertions (
    .clk       (clk),
    .rst_n     (rst_n),
    .alu_op    (alu_op),
    .operand_a (operand_a),
    .operand_b (operand_b),
    .shamt     (shamt),
    .result    (result),
    .flag_zero (flag_zero),
    .flag_neg  (flag_neg),
    .flag_carry(flag_carry),
    .flag_ovf  (flag_ovf),
    .clk_en    (clk_en),
    .is_arith  (is_arith),
    .ovf_flag  (ovf_flag)   // Internal combinational overflow detector
);
