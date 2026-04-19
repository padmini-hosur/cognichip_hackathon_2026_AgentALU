# AI-Assisted Verification Framework for CPU Datapath ALU

## Team: Agent-ALU

| Name |
|------|
| Padmini Hosur |
| Nishan Varghese | 
| Abhinav Mudiraj Gottam | 
SJSU Hackathon · CogniChip ACI · EDA & Digital Logic Verification

---

## Overview

This project implements a **human-in-the-loop AI verification framework** for a 32-bit CPU datapath ALU. CogniChip's ACI generates all verification artifacts — RTL, testbench, and SVA assertions — from a structured JSON specification. The human engineer connects the stages: running simulation, feeding the PASS/FAIL log back into CogniChip as a new prompt, and triggering the AI analysis layer.

The core innovation is a **closed-loop feedback mechanism** demonstrated live:
- CogniChip generates a buggy RTL with 3 injected bugs
- Verilator 5.042 surfaces 6 failures across 38 executed vectors
- The simulation log is pasted into CogniChip (Prompt 7 — the AI Analysis Layer)
- The AI explains each failure in plain English, cites the RTL section responsible, and generates 9 directed fix vectors
- CogniChip generates corrected RTL — re-simulation shows all tests pass

**Key principle:** You are the human-in-the-loop connecting the stages. CogniChip is the AI agent at each node.

---

## Problem

Verification is the primary bottleneck in chip design, consuming approximately 70% of development time:

- Manual testbenches miss corner cases — overflow errors, sign-extension bugs, divide-by-zero edge conditions
- Assertions are incomplete or written after the fact
- Debugging is slow — engineers trace simulation logs manually to find root causes
- Corner-case bugs found after tapeout cause expensive silicon re-spins

---

## Solution: 7-Stage Verification Pipeline

```
Stage 1 — JSON Spec (single source of truth for all artifacts)
      │
      ▼
Stage 2 — CogniChip ACI generates PPA-optimised RTL
          alu_32bit.sv — 7 sections, labelled // PPA-POWER: // PPA-AREA: // PPA-PERF:
      │
      ▼
Stage 3 — ACI generates self-checking testbench
          alu_32bit_tb.sv — 42 directed vectors across all 12 operations
      │
Stage 4 — ACI generates SVA bind file
          alu_assertions.sv — 17 assertions + 8 cover points
      │
      ▼
Stage 5 — Simulate buggy RTL (alu_32bit_buggy.sv)
          Verilator 5.042 → 32 PASS  6 FAIL  (38 vectors executed)
      │
      ▼  [HUMAN-IN-THE-LOOP: paste simulation log into CogniChip]
      │
Stage 6 — CogniChip AI Analysis Layer (Prompt 7)
          · Explains each failure in plain English
          · Hypothesises root cause, cites RTL section number
          · Generates 9 directed fix vectors
          · Produces coverage gap analysis (4 unexecuted vectors)
      │
      ▼
Stage 7 — CogniChip generates corrected RTL
          Re-simulate → 44 tests all PASS · 17/17 assertions pass · 8/8 cover points hit
```

---

## Key Features

- 32-bit ALU with 12 operations: ADD, SUB, AND, OR, XOR, NOT, SLL, SRL, SRA, MUL, DIV, MOD
- AI-generated PPA-optimised RTL — 6 hardware optimisation techniques
- Self-checking testbench — 42 directed vectors, 38 executed in iteration 1
- **17 SVA assertion properties + 8 cover points** (alu_assertions.sv)
- AI-driven failure analysis: root cause per RTL section, 9 directed fix vectors
- Coverage gap analysis: 4 unexecuted vectors identified and explained
- Iterative closed-loop workflow across 2 simulation iterations

---

## Tools Used

| Tool | Purpose |
|------|---------|
| CogniChip ACI | RTL, testbench, assertion generation; failure analysis; fix generation |
| SystemVerilog (IEEE 1800-2012) | HDL for all generated files |
| Verilator 5.042 (--assert enabled) | Simulation — both testbench and SVA assertion evaluation |

---

## Results

### Iteration 1 — Buggy RTL (alu_32bit_buggy.sv)

| Metric | Value |
|--------|-------|
| Simulator | Verilator 5.042 (--assert enabled) |
| Total vectors defined | 42 |
| Vectors executed | 38 (4 not run — X-propagation on undefined operands) |
| Testbench: PASS | 32 |
| Testbench: FAIL | 6 |
| SVA result | 6 assertion violations |
| Assertions defined | 17 assertions + 8 cover points |

From the actual simulation log (Slide 9):
> `DUT: alu_32bit_buggy.sv · TB: alu_32bit_tb.sv (42 vectors / 38 executed) · Tool: Verilator 5.042 · Result: 32 PASSED  6 FAILED`

SVA violations observed (Slide 10):
- `[85000ps]  ASSERT FAIL ast_ovf_equals_ovf_flag: flag_ovf=1 but ovf_flag was 0`
- `[95000ps]  ASSERT FAIL ast_ovf_equals_ovf_flag: flag_ovf=0 but ovf_flag was 1`
- `[325000ps] ASSERT FAIL ast_sra_neg_signext: SRA of negative value did not sign-extend: result=7ffffffc`

### Iteration 2 — Fixed RTL (alu_32bit_fixed.sv)

| Metric | Value |
|--------|-------|
| Vectors executed | 44 / 44 (42 original + 2 directed fix vectors) |
| Testbench: PASS | 44 |
| Testbench: FAIL | 0 |
| SVA assertions | 17 / 17 passing |
| Cover points hit | 8 / 8 |
| Bugs remaining | 0 |

---

## Bugs Identified

| Bug | Description | RTL Section | Detected by | Status |
|-----|-------------|-------------|-------------|--------|
| BUG 1 | `flag_ovf` assigned from `comb_carry` instead of `ovf_flag` — carry ≠ overflow | Section 7 — output registers | TB (2 FAILs) + SVA `ast_ovf_equals_ovf_flag` | Fixed |
| BUG 2 | DIV/MOD guard checks `operand_b` instead of `b_gated` — wrong signal | Section 5 — result mux | TB (2 FAILs) | Fixed |
| BUG 3 | `shift_fill = 0` always — SRA behaves as SRL, no sign extension | Section 3 — barrel shifter | TB (2 FAILs) + SVA `ast_sra_neg_signext` | Fixed |

---

## PPA Optimisations

| Technique | Category | Description |
|-----------|----------|-------------|
| Operand isolation | PPA-POWER | `b_gated` and `sh_gated` forced to 0 when unused — suppresses toggle activity |
| Shared adder | PPA-AREA | SUB reuses ADD carry-chain: `B ^ {32{do_sub}} + cin=do_sub` — one 33-bit adder |
| Unified barrel shifter | PPA-AREA+PERF | SLL reuses SRL mux tree via bit-reversal — O(log₂32) = 5 mux levels |
| Signed multiplier | PPA-AREA | Unsigned `|A|×|B|` → named wire `prod_u` → slice `prod_lo` → post-negate |
| `unique case` | PPA-PERF | Priority-free mux synthesis in result selection |
| Clock gate enable | PPA-POWER | `clk_en` freezes output flops when inputs unchanged — ICG cell inferred |

---

## SVA Assertions (alu_assertions.sv)

The assertions file is a self-contained bind file — no changes to alu_32bit.sv required.
All helper signals (`is_arith`, `is_div_mod`) are recomputed inside the assertions module from output ports only.

**17 assertion properties + 8 cover points** run with `verilator --assert`.

Key properties that fired on the buggy DUT:
- `ast_ovf_equals_ovf_flag` — fired 4 times (Bug 1: overflow flag mismatch)
- `ast_sra_neg_signext` — fired 2 times (Bug 3: missing sign extension)

---
## AI Contributions

AI was used at multiple stages:

* RTL generation with PPA optimization
* Testbench generation (42 vectors)
* Assertion generation (17 SVA properties)
* Failure explanation in plain English
* Root cause identification
* Directed fix vector generation
* Coverage gap analysis

---

## Challenges

**SVA bind file — internal signals not accessible** — `clk_en` and `is_arith` are internal wires inside `alu_32bit`, not output ports. They cannot appear in a bind statement port list. Fixed by recomputing both signals inside `alu_assertions` from the `alu_op` port, making the file fully self-contained.

**CogniChip prompt ordering is dependency-critical** — if dependent modules are generated too many prompts apart, port names drift in the rolling context window and instantiation breaks. Fixed by always generating a module and everything that instantiates it back-to-back.

**4 vectors not executed in iteration 1** — Verilator ran 38 of 42 vectors. The 4 unexecuted vectors used `32'hX` as `operand_b` in NOT and shift operations. Verilator applies stricter X-propagation than Icarus Verilog. These were identified by the AI Analysis Layer as coverage gaps and resolved in iteration 2.

---

## Future Work

- Extend to a 5-stage RISC-V pipeline — the ALU becomes the EX stage; the same verification framework scales unchanged
- Formal verification — connect SVA assertions to JasperGold or SymbiYosys for exhaustive property proving beyond simulation
- Coverage-driven AI loop — replace directed vectors with covergroup tracking; feed gaps to AI for automatic vector generation
- Support for larger systems: pipeline hazard detection, memory subsystem, cache coherence

---

## Impact

This project demonstrates that AI can act as an active participant in hardware verification — not just a code generator, but a diagnostic reasoner that reads simulation failures, hypothesises hardware root causes, generates targeted test vectors, and produces corrected RTL. The human engineer provides judgment and integration at three key decision points; everything else is AI-driven.

The same pipeline is tool-agnostic and applies to any RTL block described by a structured specification.
