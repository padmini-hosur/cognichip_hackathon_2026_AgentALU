
# **AI-Assisted Verification Framework for CPU Datapath ALU**

## Team: Agent-ALU

* Nishan Varghese 
* Padmini Hosur 
* Abhinav Mudiraj Gottam
---

## Overview

This project implements an **AI-assisted verification framework** for a 32-bit CPU datapath ALU.

The system automates:

* RTL generation
* Testbench creation
* Assertion generation
* Bug detection
* Root cause analysis
* Iterative fix & re-verification

Result: A **closed-loop verification workflow** that reduces manual effort and improves debugging efficiency.

---

## Problem

Verification is the primary bottleneck in chip design, consuming ~70% of development time.

Challenges:

* Manual testbenches miss edge cases
* Assertions are incomplete
* Debugging is slow and error-prone
* Corner-case bugs lead to silicon failures

---

##  Solution

We built a spec-driven, AI-in-the-loop verification pipeline:

The system uses "CogniChip ACI" to generate and analyze verification artifacts at every stage.

---

## Key Features

* 32-bit ALU with 12 operations
* AI-generated RTL (PPA-aware design)
* Self-checking testbench (42 test vectors)
* System Verilog Assertions (17 properties, 8 cover points)
* AI-based root cause analysis
* Coverage gap identification
* Closed-loop verification flow

---

## Tools Used

* SystemVerilog (IEEE 1800-2012)
* Verilator 5.042
* CogniChip ACI (AI generation & reasoning)

---

## Results

### Buggy Design Results

* **32 PASS / 6 FAIL** (38 test vectors)
* **6 assertion violations**
* **2/3 bugs detected via assertions**

Example failure (overflow bug):

> Incorrect overflow flag due to using carry instead of signed overflow logic 

Example failure (shift bug):

> Arithmetic right shift failed to sign-extend negative values 

---

### Fixed Design Results

* **38 / 38 tests PASS**
* **17 / 17 assertions PASS**
* **0 violations**
* **8 / 8 coverage points HIT** 

---

## Bugs Identified

| Bug   | Description                          | Status |
| ----- | ------------------------------------ | ------ |
| BUG 1 | Overflow flag incorrectly uses carry | Fixed  |
| BUG 2 | DIV/MOD guard uses wrong signal      | Latent |
| BUG 3 | SRA missing sign extension           | Fixed  |

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

## Key Achievements

* Fully automated verification pipeline
* Detection and correction of multiple RTL bugs
* Assertion-based bug isolation
* AI-assisted debugging insights
* Achieved complete functional coverage after fixes

---

## Challenges

* Handling large input space and corner cases
* Integrating AI-generated RTL, TB, and assertions
* Debugging multi-stage inconsistencies

---

## How We Solved Them

* Structured spec-driven workflow
* Iterative simulation + AI feedback
* Maintaining consistency across all generated artifacts

---

## Future Work

* Extend to full CPU datapath verification
* Integrate formal verification tools
* Automate coverage-driven test generation
* Support larger systems (pipeline, memory, interconnects)

---

## Impact

This project demonstrates how AI can:

* Reduce verification effort
* Improve coverage
* Accelerate debugging
* Enable scalable hardware verification workflows

---

# Final Note

This repository showcases a **complete AI-assisted verification pipeline**, demonstrating how modern chip design workflows can be significantly improved using intelligent automation.

---
