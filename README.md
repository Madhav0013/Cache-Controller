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

**Status: ✅ 100% PASSED**

| Test Name | Status | Coverage Impact |
|-----------|--------|-----------------|
| `cache_smoke_test` | ✅ PASSED | Basic functionality |
| `cache_hit_miss_test` | ✅ PASSED | Sequential memory patterns |
| `cache_eviction_test` | ✅ PASSED | Dirty writeback path |
| `cache_thrash_test` | ✅ PASSED | 100% Cache Op Coverage |
| `cache_random_test` | ✅ PASSED | 100% Address Pattern Coverage |

Please refer to the `doc/verification_signoff_report.md` for full test suite execution, coverage details, and screenshots of the EDA logs.

## Formal Properties

All SVA properties successfully evaluated with zero failures:

| ID | Property | Type | Status |
|----|----------|------|--------|
| FP1 | FSM always returns to IDLE | Liveness | ✅ Verified |
| FP2 | No spurious cpu_ready | Safety | ✅ Verified |
| FP3 | DONE always asserts ready | Safety | ✅ Verified |
| FP4 | Writeback writes to memory | Safety | ✅ Verified |
| FP5 | Allocate reads from memory | Safety | ✅ Verified |
| FP6 | Memory address alignment | Safety | ✅ Verified |
| FP7 | Counters monotonically increase | Safety | ✅ Verified |
| FP8 | Reset puts FSM in IDLE | Safety | ✅ Verified |

## Directory Structure
- `doc/`: Contains verification plan, final sign-off report, and screenshots
- `rtl/`: Core cache controller Verilog files
- `sim/`: EDA playground single-file equivalents (for quick simulation drops)
- `verif/`: Full split-file UVM environment with assertions

## Tools

- Synopsys VCS X-2025.06-SP1
- UVM 1.2
- EDA Playground
