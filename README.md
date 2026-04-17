# Direct-Mapped Write-Back Cache Controller — UVM + Formal Verification

## Overview

A parameterized direct-mapped write-back cache controller verified using both UVM
simulation-based testing and SVA formal property checking. The cache supports
configurable address width, data width, and number of cache lines.

## Architecture

- **Cache type:** Direct-mapped, write-back with dirty bit
- **Parameters:** ADDR_WIDTH=16, DATA_WIDTH=32, CACHE_LINES=16
- **FSM states:** IDLE → TAG_CHECK → WRITEBACK (if dirty) → ALLOCATE → DONE
- **Features:** Dirty bit tracking, hit/miss detection, performance counters

## Verification Approach

This project uses **two complementary verification strategies**:

1. **Simulation (UVM):** Constrained-random and directed tests with a golden
   memory reference model scoreboard
2. **Formal (SVA):** 8 formal properties proving safety and liveness invariants

## Test Results

*To be updated with verified EDA Playground results*

## Formal Properties

| ID | Property | Type | Status |
|----|----------|------|--------|
| FP1 | FSM always returns to IDLE | Liveness | TBD |
| FP2 | No spurious cpu_ready | Safety | TBD |
| FP3 | DONE always asserts ready | Safety | TBD |
| FP4 | Writeback writes to memory | Safety | TBD |
| FP5 | Allocate reads from memory | Safety | TBD |
| FP6 | Memory address alignment | Safety | TBD |
| FP7 | Counters monotonically increase | Safety | TBD |
| FP8 | Reset puts FSM in IDLE | Safety | TBD |

## Directory Structure

See `doc/verification_plan.md` for the full verification plan (written before any code).

## Tools

- Synopsys VCS X-2025.06-SP1
- UVM 1.2
- EDA Playground
