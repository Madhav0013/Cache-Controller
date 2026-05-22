module cache_assertions
    import cache_pkg::*;
#(
    parameter int ADDR_W = ADDR_WIDTH,
    parameter int DATA_W = DATA_WIDTH,
    parameter int LINES  = CACHE_LINES,
    parameter int IDX_W  = INDEX_WIDTH,
    parameter int TAG_W  = TAG_WIDTH,
    parameter int OFF_W  = OFFSET_WIDTH
)(
    input logic              clk,
    input logic              rst_n,
    // CPU side
    input logic              cpu_req,
    input logic              cpu_wr,
    input logic [ADDR_W-1:0] cpu_addr,
    input logic [DATA_W-1:0] cpu_wdata,
    input logic [DATA_W-1:0] cpu_rdata,
    input logic              cpu_ready,
    // Memory side
    input logic              mem_req,
    input logic              mem_wr,
    input logic [ADDR_W-1:0] mem_addr,
    input logic [DATA_W-1:0] mem_wdata,
    input logic              mem_ready,
    // Internal state (for formal — connect via hierarchical path or ports)
    input cache_state_t      state,
    input logic [31:0]       hit_count,
    input logic [31:0]       miss_count,
    input logic [31:0]       wb_count
);

    // =========================================================================
    // FP1: FSM always returns to IDLE (liveness)
    // The cache must not get stuck in any state forever
    // =========================================================================
    FP1_FSM_LIVENESS: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state != IDLE) |-> ##[1:100] (state == IDLE)
    ) else $error("[FP1] FSM stuck — did not return to IDLE within 100 cycles");

    // =========================================================================
    // FP2: No cpu_ready without prior cpu_req
    // The cache must not spontaneously assert ready
    // =========================================================================
    FP2_NO_SPURIOUS_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(cpu_ready) |-> (state == DONE)
    ) else $error("[FP2] cpu_ready asserted outside of DONE state");

    // =========================================================================
    // FP3: DONE state always asserts cpu_ready
    // Every completed operation must signal the CPU
    // =========================================================================
    FP3_DONE_IMPLIES_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == DONE) |-> cpu_ready
    ) else $error("[FP3] FSM in DONE but cpu_ready not asserted");

    // =========================================================================
    // FP4: Writeback must happen before allocate on dirty miss
    // If a dirty line is being evicted, memory write must occur
    // =========================================================================
    FP4_WRITEBACK_BEFORE_ALLOCATE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == WRITEBACK && !mem_ready) |-> (mem_req && mem_wr)
    ) else $error("[FP4] In WRITEBACK state but not writing to memory");

    // =========================================================================
    // FP5: Allocate reads from memory (not writes)
    // =========================================================================
    FP5_ALLOCATE_IS_READ: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == ALLOCATE && mem_req) |-> !mem_wr
    ) else $error("[FP5] In ALLOCATE state but mem_wr is asserted (should be reading)");

    // =========================================================================
    // FP6: Memory address alignment
    // All memory accesses must be word-aligned
    // =========================================================================
    FP6_MEM_ADDR_ALIGNED: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_req |-> (mem_addr[OFF_W-1:0] == '0)
    ) else $error("[FP6] Memory address not word-aligned");

    // =========================================================================
    // FP7: Hit and miss counts are monotonically increasing
    // =========================================================================
    FP7_HIT_COUNT_MONOTONIC: assert property (
        @(posedge clk) disable iff (!rst_n)
        1 |=> (hit_count >= $past(hit_count))
    ) else $error("[FP7] Hit count decreased");

    FP7B_MISS_COUNT_MONOTONIC: assert property (
        @(posedge clk) disable iff (!rst_n)
        1 |=> (miss_count >= $past(miss_count))
    ) else $error("[FP7B] Miss count decreased");

    // =========================================================================
    // FP8: After reset, FSM is in IDLE
    // =========================================================================
    FP8_RESET_STATE: assert property (
        @(posedge clk)
        !rst_n |=> (state == IDLE)
    ) else $error("[FP8] FSM not in IDLE after reset");

    // =========================================================================
    // COVER PROPERTIES — prove these scenarios are reachable
    // =========================================================================

    // C1: Read hit observed
    C1_READ_HIT: cover property (
        @(posedge clk) cpu_req && !cpu_wr ##[1:10] (cpu_ready && (state == DONE))
    );

    // C2: Write hit observed
    C2_WRITE_HIT: cover property (
        @(posedge clk) cpu_req && cpu_wr ##[1:10] (cpu_ready && (state == DONE))
    );

    // C3: Dirty writeback observed
    C3_DIRTY_WRITEBACK: cover property (
        @(posedge clk) (state == TAG_CHECK) ##1 (state == WRITEBACK)
    );

    // C4: Clean miss (skip writeback, go straight to allocate)
    C4_CLEAN_MISS: cover property (
        @(posedge clk) (state == TAG_CHECK) ##1 (state == ALLOCATE)
    );

    // C5: Full sequence: miss → writeback → allocate → done
    C5_FULL_DIRTY_MISS: cover property (
        @(posedge clk) (state == TAG_CHECK)
            ##1 (state == WRITEBACK)
            ##[1:50] (state == ALLOCATE)
            ##[1:50] (state == DONE)
    );

endmodule : cache_assertions
