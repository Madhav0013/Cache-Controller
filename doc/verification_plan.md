# Cache Controller Verification Plan

## 1. Design Under Test

Direct-mapped write-back cache controller with the following parameters:
- ADDR_WIDTH: 16 bits
- DATA_WIDTH: 32 bits
- CACHE_LINES: 16 (4-bit index)
- LINE_SIZE: 1 word (32 bits) — simplified, one word per cache line

Address breakdown: [TAG | INDEX | BYTE_OFFSET]
- BYTE_OFFSET: bits [1:0] (word-aligned, 4 bytes)
- INDEX: bits [5:2] (16 lines = 4 bits)
- TAG: bits [15:6] (remaining 10 bits)

## 2. Features to Verify

| ID | Feature | Description | Priority |
|----|---------|-------------|----------|
| F1 | Read hit | Read from cached address returns correct data in 1 cycle | P0 |
| F2 | Read miss (clean) | Read miss on clean line fetches from memory, returns data | P0 |
| F3 | Read miss (dirty) | Read miss on dirty line writes back, then fetches | P0 |
| F4 | Write hit | Write to cached address updates data and sets dirty bit | P0 |
| F5 | Write miss (clean) | Write miss allocates line, writes data, sets dirty | P0 |
| F6 | Write miss (dirty) | Write miss writes back dirty line, allocates, writes | P0 |
| F7 | Dirty writeback | Dirty eviction correctly writes back to memory | P0 |
| F8 | Tag comparison | Correct hit/miss determination based on tag match | P0 |
| F9 | Valid bit | Invalid lines always miss regardless of tag | P1 |
| F10 | Reset behavior | All valid bits cleared on reset, all lines invalid | P1 |
| F11 | Back-to-back ops | Consecutive operations without idle cycles between | P1 |
| F12 | Same-index conflict | Two addresses mapping to same index force eviction | P1 |
| F13 | Performance counters | Hit/miss/writeback counters increment correctly | P2 |

## 3. Test Scenarios

| Test | Features Covered | Stimulus Strategy |
|------|-----------------|-------------------|
| cache_smoke_test | F1, F4 | Write one address, read it back |
| cache_hit_miss_test | F1, F2, F5, F8, F9 | Write N addresses, read them (hits), read new addresses (misses) |
| cache_eviction_test | F3, F6, F7, F12 | Write to addr A, write to addr B (same index, different tag), verify A was written back |
| cache_thrash_test | F3, F6, F7, F12 | Write to more unique indices than cache size, forcing all lines to be evicted |
| cache_random_test | F1-F13 | Constrained-random mix of reads and writes to random addresses |

## 4. Formal Properties (SVA)

| ID | Property | Type | Description |
|----|----------|------|-------------|
| FP1 | No silent data loss | Safety | A dirty line must be written back to memory before being overwritten |
| FP2 | Read consistency | Safety | A read to address X must return the most recent write to address X |
| FP3 | Tag uniqueness | Safety | No two valid lines can have the same index (enforced by direct-mapped structure) |
| FP4 | Dirty bit correctness | Safety | Dirty bit is set if and only if the line has been written since allocation |
| FP5 | Valid bit after reset | Safety | All valid bits are 0 after reset |
| FP6 | FSM return to IDLE | Liveness | The FSM must always eventually return to IDLE |
| FP7 | No response without request | Safety | cpu_rvalid cannot assert without a prior cpu_req |
| FP8 | Writeback before evict | Safety | If a dirty line is being evicted, mem_wr must assert before the new line is allocated |

## 5. Coverage Goals

| Covergroup | Coverpoints | Target |
|------------|-------------|--------|
| cache_op_cg | read/write × hit/miss | 100% of 4 bins |
| eviction_cg | clean_evict / dirty_evict | Both bins hit |
| addr_index_cg | All 16 cache line indices exercised | 100% (all 16) |
| back_to_back_cg | consecutive read, consecutive write, read-after-write, write-after-read | All 4 bins |
| dirty_bit_cg | line transitions: clean→dirty, dirty→clean (after writeback) | Both bins |

## 6. Pass/Fail Criteria

- All UVM tests: 0 UVM_ERROR, 0 UVM_FATAL
- Scoreboard: all read data matches golden model
- Formal: all 8 properties PROVEN (not just "no counterexample found")
- Coverage: 100% of cache_op_cg (hit/miss × read/write cross)
- Coverage: all 16 indices exercised
