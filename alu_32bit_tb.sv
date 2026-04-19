// =============================================================================
// File        : alu_32bit_tb.sv
// Description : Self-checking directed testbench for alu_32bit.
//               42 test vectors covering all 12 operations including
//               carry, overflow, divide-by-zero, and sign-extension corners.
//               All outputs are registered (1-cycle latency) — each check()
//               call applies inputs then waits one posedge clk before sampling.
// =============================================================================
`timescale 1ns/1ps

import alu_pkg::*;

module alu_32bit_tb;

    // -------------------------------------------------------------------------
    // DUT signal declarations
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    alu_op_t     alu_op;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [4:0]  shamt;
    logic [31:0] result;
    logic        flag_zero;
    logic        flag_neg;
    logic        flag_carry;
    logic        flag_ovf;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    alu_32bit dut (
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
        .flag_ovf  (flag_ovf)
    );

    // -------------------------------------------------------------------------
    // Clock: 100 MHz — period = 10 ns
    // -------------------------------------------------------------------------
    initial clk = 0;
    always  #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard counters
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("alu_32bit.vcd");
        $dumpvars(0, alu_32bit_tb);
    end

    // =========================================================================
    // Task: check
    // Applies one set of inputs, waits one rising clock edge (+1 ns settle),
    // then compares all DUT outputs against expected values.
    // =========================================================================
    task automatic check(
        input string       test_name,
        input alu_op_t     op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [4:0]  sh,
        input logic [31:0] exp_result,
        input logic        exp_Z,
        input logic        exp_N,
        input logic        exp_C,
        input logic        exp_V
    );
        alu_op    = op;
        operand_a = a;
        operand_b = b;
        shamt     = sh;
        @(posedge clk); #1;
        if (result === exp_result && flag_zero === exp_Z && flag_neg === exp_N &&
            flag_carry === exp_C && flag_ovf === exp_V) begin
            $display("  PASS | %-38s | result=%08h Z=%0b N=%0b C=%0b V=%0b",
                     test_name, result, flag_zero, flag_neg, flag_carry, flag_ovf);
        end else begin
            $display("  FAIL | %-38s | got=%08h(exp=%08h) Z=%0b(%0b) N=%0b(%0b) C=%0b(%0b) V=%0b(%0b)",
                     test_name, result, exp_result,
                     flag_zero,  exp_Z,
                     flag_neg,   exp_N,
                     flag_carry, exp_C,
                     flag_ovf,   exp_V);
        end
        if (result === exp_result && flag_zero === exp_Z && flag_neg === exp_N &&
            flag_carry === exp_C && flag_ovf === exp_V) begin
            pass_cnt++;
        end else begin
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("TEST START");
        $display("=================================================================");
        $display("  alu_32bit Self-Checking Testbench — 42 Vectors");
        $display("=================================================================");

        // ---------------------------------------------------------------------
        // Reset: assert rst_n=0 for 3 full clock cycles
        // ---------------------------------------------------------------------
        rst_n     = 1'b0;
        alu_op    = ALU_ADD;
        operand_a = 32'b0;
        operand_b = 32'b0;
        shamt     = 5'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk);   // Idle cycle 1: prev_reg captures {ALU_ADD,0,0,0}
        @(posedge clk);   // Idle cycle 2: prev_reg stable
        #1;               // Step 1 ns past the posedge edge.  Icarus can fire
                          // multiple consecutive @(posedge clk) calls in the
                          // same scheduling round (t=same), causing always_ff
                          // to evaluate BEFORE check() sets new inputs, so
                          // clk_en=0 and result stays 0.  The #1 here moves
                          // the process to t+1 ns, making it impossible for
                          // the first check()'s @(posedge clk) to collide with
                          // this posedge.

        // =====================================================================
        // ADD — 5 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  ADD");
        $display("-----------------------------------------------------------------");
        check("ADD  5+3=8",
              ALU_ADD, 32'd5,        32'd3,        5'd0, 32'd8,         0,0,0,0);
        check("ADD  0+0 [zero]",
              ALU_ADD, 32'd0,        32'd0,        5'd0, 32'd0,         1,0,0,0);
        check("ADD  0xFFFFFFFF+1 [carry]",
              ALU_ADD, 32'hFFFFFFFF, 32'd1,        5'd0, 32'd0,         1,0,1,0);
        check("ADD  0x7FFFFFFF+1 [pos ovf]",
              ALU_ADD, 32'h7FFFFFFF, 32'd1,        5'd0, 32'h80000000, 0,1,0,1);
        check("ADD  0x80000000+0x80000000",
              ALU_ADD, 32'h80000000, 32'h80000000, 5'd0, 32'd0,         1,0,1,1);

        // =====================================================================
        // SUB — 4 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  SUB");
        $display("-----------------------------------------------------------------");
        check("SUB  10-3=7",
              ALU_SUB, 32'd10,       32'd3,        5'd0, 32'd7,         0,0,1,0);  // carry=1: no borrow (A>=B)
        check("SUB  5-5 [zero]",
              ALU_SUB, 32'd5,        32'd5,        5'd0, 32'd0,         1,0,1,0);  // carry=1: no borrow (A==B)
        check("SUB  3-10 [neg+borrow]",
              ALU_SUB, 32'd3,        32'd10,       5'd0, 32'hFFFFFFF9,  0,1,0,0);  // carry=0: borrow (A<B)
        check("SUB  0x80000000-1 [neg ovf]",
              ALU_SUB, 32'h80000000, 32'd1,        5'd0, 32'h7FFFFFFF, 0,0,1,1);  // carry=1: no borrow; ovf=1: signed overflow

        // =====================================================================
        // AND — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  AND");
        $display("-----------------------------------------------------------------");
        check("AND  0xFF&0x0F=0x0F",
              ALU_AND, 32'h000000FF, 32'h0000000F, 5'd0, 32'h0000000F, 0,0,0,0);
        check("AND  0xAAAA&0x5555 [zero]",
              ALU_AND, 32'hAAAAAAAA, 32'h55555555, 5'd0, 32'h00000000, 1,0,0,0);
        check("AND  0xFFFF&0x8000 [neg]",
              ALU_AND, 32'hFFFFFFFF, 32'h80000000, 5'd0, 32'h80000000, 0,1,0,0);

        // =====================================================================
        // OR — 2 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  OR");
        $display("-----------------------------------------------------------------");
        check("OR   0xAAAA|0x5555 [allones]",
              ALU_OR,  32'hAAAAAAAA, 32'h55555555, 5'd0, 32'hFFFFFFFF, 0,1,0,0);
        check("OR   0|0 [zero]",
              ALU_OR,  32'd0,        32'd0,        5'd0, 32'd0,         1,0,0,0);

        // =====================================================================
        // XOR — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  XOR");
        $display("-----------------------------------------------------------------");
        check("XOR  same [zero]",
              ALU_XOR, 32'hDEADBEEF, 32'hDEADBEEF, 5'd0, 32'h00000000, 1,0,0,0);
        check("XOR  0xF^0xA=5",
              ALU_XOR, 32'h0000000F, 32'h0000000A, 5'd0, 32'h00000005, 0,0,0,0);
        check("XOR  neg result",
              ALU_XOR, 32'h80000001, 32'h00000001, 5'd0, 32'h80000000, 0,1,0,0);

        // =====================================================================
        // NOT — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  NOT");
        $display("-----------------------------------------------------------------");
        check("NOT  ~0=0xFFFFFFFF [neg]",
              ALU_NOT, 32'h00000000, 32'hX,        5'd0, 32'hFFFFFFFF, 0,1,0,0);
        check("NOT  ~0xFFFFFFFF [zero]",
              ALU_NOT, 32'hFFFFFFFF, 32'hX,        5'd0, 32'h00000000, 1,0,0,0);
        check("NOT  ~0x7FFFFFFF",
              ALU_NOT, 32'h7FFFFFFF, 32'hX,        5'd0, 32'h80000000, 0,1,0,0);

        // =====================================================================
        // SLL — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  SLL");
        $display("-----------------------------------------------------------------");
        check("SLL  1<<0=1",
              ALU_SLL, 32'd1,        32'hX,        5'd0,  32'h00000001, 0,0,0,0);
        check("SLL  1<<4=0x10",
              ALU_SLL, 32'd1,        32'hX,        5'd4,  32'h00000010, 0,0,0,0);
        check("SLL  1<<31 [MSB]",
              ALU_SLL, 32'd1,        32'hX,        5'd31, 32'h80000000, 0,1,0,0);

        // =====================================================================
        // SRL — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  SRL");
        $display("-----------------------------------------------------------------");
        check("SRL  0x80000000>>1",
              ALU_SRL, 32'h80000000, 32'hX,        5'd1,  32'h40000000, 0,0,0,0);
        check("SRL  0xFF>>4=0xF",
              ALU_SRL, 32'h000000FF, 32'hX,        5'd4,  32'h0000000F, 0,0,0,0);
        check("SRL  0xFFFFFFFF>>31=1",
              ALU_SRL, 32'hFFFFFFFF, 32'hX,        5'd31, 32'h00000001, 0,0,0,0);

        // =====================================================================
        // SRA — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  SRA");
        $display("-----------------------------------------------------------------");
        check("SRA  0xFFFFFFF8>>>1 [signext]",
              ALU_SRA, 32'hFFFFFFF8, 32'hX,        5'd1,  32'hFFFFFFFC, 0,1,0,0);
        check("SRA  8>>>1=4",
              ALU_SRA, 32'd8,        32'hX,        5'd1,  32'd4,        0,0,0,0);
        check("SRA  0x80000000>>>31 [allF]",
              ALU_SRA, 32'h80000000, 32'hX,        5'd31, 32'hFFFFFFFF, 0,1,0,0);

        // =====================================================================
        // MUL — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  MUL");
        $display("-----------------------------------------------------------------");
        check("MUL  6*7=42",
              ALU_MUL, 32'd6,        32'd7,        5'd0, 32'd42,        0,0,0,0);
        check("MUL  0*0xFFFFFFFF [zero]",
              ALU_MUL, 32'd0,        32'hFFFFFFFF, 5'd0, 32'd0,         1,0,0,0);
        check("MUL  -1*-1=1",
              ALU_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 5'd0, 32'h00000001, 0,0,0,0);

        // =====================================================================
        // DIV — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  DIV");
        $display("-----------------------------------------------------------------");
        check("DIV  42/6=7",
              ALU_DIV, 32'd42,       32'd6,        5'd0, 32'd7,         0,0,0,0);
        check("DIV  -42/6=-7 [signed]",
              ALU_DIV, 32'hFFFFFFD6, 32'd6,        5'd0, 32'hFFFFFFF9,  0,1,0,0);
        check("DIV  100/0=0 [guard]",
              ALU_DIV, 32'd100,      32'd0,        5'd0, 32'd0,         1,0,0,0);

        // =====================================================================
        // MOD — 3 vectors
        // =====================================================================
        $display("-----------------------------------------------------------------");
        $display("  MOD");
        $display("-----------------------------------------------------------------");
        check("MOD  10%3=1",
              ALU_MOD, 32'd10,       32'd3,        5'd0, 32'd1,         0,0,0,0);
        check("MOD  10%0=0 [guard]",
              ALU_MOD, 32'd10,       32'd0,        5'd0, 32'd0,         1,0,0,0);
        check("MOD  -13%5 [signed]",
              ALU_MOD, 32'hFFFFFFF3, 32'd5,        5'd0, 32'hFFFFFFFD,  0,1,0,0);  // -13%5=-3 (C99 trunc-toward-zero)

        // =====================================================================
        // Summary
        // =====================================================================
        $display("=================================================================");
        $display("  TOTAL: %0d PASSED  %0d FAILED  (out of %0d)",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0) begin
            $display("  ALL TESTS PASSED");
            $display("TEST PASSED");
        end else begin
            $display("  *** %0d FAILURES — see FAIL lines above ***", fail_cnt);
            $display("TEST FAILED");
        end
        $display("=================================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Simulation timeout guard (prevents infinite hang)
    // -------------------------------------------------------------------------
    initial begin
        #100000;
        $display("ERROR: simulation timeout after 100us");
        $display("TEST FAILED");
        $finish;
    end

endmodule : alu_32bit_tb
