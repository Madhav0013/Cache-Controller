// =============================================================================
// EDA Playground — Design file (design.sv)
// Cache Controller with Formal SVA Properties
// =============================================================================

// ======================= cache_pkg.sv =======================================
package cache_pkg;

    // Cache parameters
    parameter int ADDR_WIDTH   = 16;
    parameter int DATA_WIDTH   = 32;
    parameter int CACHE_LINES  = 16;    // Number of cache lines
    parameter int INDEX_WIDTH  = 4;     // log2(CACHE_LINES)
    parameter int OFFSET_WIDTH = 2;     // log2(DATA_WIDTH/8) = log2(4) = 2
    parameter int TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH; // 10

    // FSM states
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        TAG_CHECK = 3'b001,
        WRITEBACK = 3'b010,
        ALLOCATE  = 3'b011,
        DONE      = 3'b100
    } cache_state_t;

    // Request type
    typedef enum logic {
        READ  = 1'b0,
        WRITE = 1'b1
    } req_type_t;

endpackage : cache_pkg

// ======================= cache_controller.sv ================================
module cache_controller
    import cache_pkg::*;
#(
    parameter int ADDR_W  = ADDR_WIDTH,
    parameter int DATA_W  = DATA_WIDTH,
    parameter int LINES   = CACHE_LINES,
    parameter int IDX_W   = INDEX_WIDTH,
    parameter int TAG_W   = TAG_WIDTH,
    parameter int OFF_W   = OFFSET_WIDTH
)(
    input  logic                clk,
    input  logic                rst_n,

    // CPU-side interface
    input  logic                cpu_req,      // CPU request valid
    input  logic                cpu_wr,       // 1=write, 0=read
    input  logic [ADDR_W-1:0]  cpu_addr,     // CPU address
    input  logic [DATA_W-1:0]  cpu_wdata,    // CPU write data
    output logic [DATA_W-1:0]  cpu_rdata,    // CPU read data
    output logic                cpu_ready,    // Cache ready (operation complete)

    // Memory-side interface
    output logic                mem_req,      // Memory request valid
    output logic                mem_wr,       // 1=write, 0=read
    output logic [ADDR_W-1:0]  mem_addr,     // Memory address
    output logic [DATA_W-1:0]  mem_wdata,    // Data to write to memory
    input  logic [DATA_W-1:0]  mem_rdata,    // Data read from memory
    input  logic                mem_ready,    // Memory operation complete

    // Performance counters
    output logic [31:0]         hit_count,
    output logic [31:0]         miss_count,
    output logic [31:0]         wb_count
);

    // =========================================================================
    // Cache storage arrays
    // =========================================================================
    logic               valid_array [0:LINES-1];
    logic               dirty_array [0:LINES-1];
    logic [TAG_W-1:0]   tag_array   [0:LINES-1];
    logic [DATA_W-1:0]  data_array  [0:LINES-1];

    // =========================================================================
    // Address decomposition
    // =========================================================================
    logic [TAG_W-1:0]   req_tag;
    logic [IDX_W-1:0]   req_index;

    assign req_tag   = cpu_addr[ADDR_W-1 : IDX_W+OFF_W];
    assign req_index = cpu_addr[IDX_W+OFF_W-1 : OFF_W];

    // =========================================================================
    // Hit/miss logic (uses registered index/tag, valid after IDLE capture)
    // =========================================================================
    logic cache_hit;
    assign cache_hit = valid_array[req_index_reg] && (tag_array[req_index_reg] == req_tag_reg);

    // =========================================================================
    // CPU ready — combinational, asserted exactly when FSM is in DONE
    // =========================================================================
    assign cpu_ready = (state == DONE);

    // =========================================================================
    // FSM
    // =========================================================================
    cache_state_t state, next_state;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req)
                    next_state = TAG_CHECK;
            end

            TAG_CHECK: begin
                if (cache_hit) begin
                    next_state = DONE;
                end else begin
                    // Miss — need to check if dirty line must be written back
                    if (valid_array[req_index_reg] && dirty_array[req_index_reg])
                        next_state = WRITEBACK;
                    else
                        next_state = ALLOCATE;
                end
            end

            WRITEBACK: begin
                if (mem_ready)
                    next_state = ALLOCATE;
            end

            ALLOCATE: begin
                if (mem_ready)
                    next_state = DONE;
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // Datapath — FSM outputs
    // =========================================================================
    // Registered request fields (captured on cpu_req)
    logic                cpu_wr_reg;
    logic [ADDR_W-1:0]   cpu_addr_reg;
    logic [DATA_W-1:0]   cpu_wdata_reg;
    logic [TAG_W-1:0]    req_tag_reg;
    logic [IDX_W-1:0]    req_index_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_wr_reg    <= 1'b0;
            cpu_addr_reg  <= '0;
            cpu_wdata_reg <= '0;
            req_tag_reg   <= '0;
            req_index_reg <= '0;
        end else if (state == IDLE && cpu_req) begin
            cpu_wr_reg    <= cpu_wr;
            cpu_addr_reg  <= cpu_addr;
            cpu_wdata_reg <= cpu_wdata;
            req_tag_reg   <= cpu_addr[ADDR_W-1 : IDX_W+OFF_W];
            req_index_reg <= cpu_addr[IDX_W+OFF_W-1 : OFF_W];
        end
    end

    // Main datapath
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integer i;
            for (i = 0; i < LINES; i++) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
                tag_array[i]   <= '0;
                data_array[i]  <= '0;
            end
            cpu_rdata  <= '0;
            mem_req    <= 1'b0;
            mem_wr     <= 1'b0;
            mem_addr   <= '0;
            mem_wdata  <= '0;
            hit_count  <= '0;
            miss_count <= '0;
            wb_count   <= '0;
        end else begin
            // Defaults
            mem_req   <= 1'b0;

            case (state)
                IDLE: begin
                    // Nothing — wait for cpu_req
                end

                TAG_CHECK: begin
                    if (cache_hit) begin
                        // HIT
                        hit_count <= hit_count + 1;
                        if (cpu_wr_reg) begin
                            // Write hit — update data and set dirty
                            data_array[req_index_reg]  <= cpu_wdata_reg;
                            dirty_array[req_index_reg] <= 1'b1;
                        end else begin
                            // Read hit — return data
                            cpu_rdata <= data_array[req_index_reg];
                        end
                    end else begin
                        // MISS
                        miss_count <= miss_count + 1;
                        if (valid_array[req_index_reg] && dirty_array[req_index_reg]) begin
                            // Dirty line — initiate writeback
                            mem_req   <= 1'b1;
                            mem_wr    <= 1'b1;
                            mem_addr  <= {tag_array[req_index_reg], req_index_reg, {OFF_W{1'b0}}};
                            mem_wdata <= data_array[req_index_reg];
                            wb_count  <= wb_count + 1;
                        end else begin
                            // Clean miss — go straight to allocate (read from memory)
                            mem_req  <= 1'b1;
                            mem_wr   <= 1'b0;
                            mem_addr <= cpu_addr_reg;
                        end
                    end
                end

                WRITEBACK: begin
                    if (mem_ready) begin
                        // Writeback complete — do NOT issue read here.
                        // Let mem_req default to 0 so mem_ready deasserts,
                        // then ALLOCATE state will issue the read request.
                    end else begin
                        // Keep request asserted until memory responds
                        mem_req   <= 1'b1;
                        mem_wr    <= 1'b1;
                        mem_addr  <= {tag_array[req_index_reg], req_index_reg, {OFF_W{1'b0}}};
                        mem_wdata <= data_array[req_index_reg];
                    end
                end

                ALLOCATE: begin
                    if (mem_ready) begin
                        // Memory returned data — install in cache
                        valid_array[req_index_reg] <= 1'b1;
                        tag_array[req_index_reg]   <= req_tag_reg;
                        if (cpu_wr_reg) begin
                            // Write miss — store write data, set dirty
                            data_array[req_index_reg]  <= cpu_wdata_reg;
                            dirty_array[req_index_reg] <= 1'b1;
                        end else begin
                            // Read miss — store memory data, clean
                            data_array[req_index_reg]  <= mem_rdata;
                            dirty_array[req_index_reg] <= 1'b0;
                            cpu_rdata <= mem_rdata;
                        end
                    end else begin
                        // Keep request asserted
                        mem_req  <= 1'b1;
                        mem_wr   <= 1'b0;
                        mem_addr <= cpu_addr_reg;
                    end
                end

                DONE: begin
                    // cpu_ready driven combinationally
                end
            endcase
        end
    end

endmodule : cache_controller

// ======================= cache_if.sv ========================================
interface cache_if #(
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // CPU side
    logic                    cpu_req;
    logic                    cpu_wr;
    logic [ADDR_WIDTH-1:0]   cpu_addr;
    logic [DATA_WIDTH-1:0]   cpu_wdata;
    logic [DATA_WIDTH-1:0]   cpu_rdata;
    logic                    cpu_ready;

    // Memory side
    logic                    mem_req;
    logic                    mem_wr;
    logic [ADDR_WIDTH-1:0]   mem_addr;
    logic [DATA_WIDTH-1:0]   mem_wdata;
    logic [DATA_WIDTH-1:0]   mem_rdata;
    logic                    mem_ready;

    // Performance counters
    logic [31:0]             hit_count;
    logic [31:0]             miss_count;
    logic [31:0]             wb_count;

    modport driver (
        output cpu_req, cpu_wr, cpu_addr, cpu_wdata,
        input  cpu_rdata, cpu_ready, clk, rst_n
    );

    modport monitor (
        input cpu_req, cpu_wr, cpu_addr, cpu_wdata,
              cpu_rdata, cpu_ready,
              mem_req, mem_wr, mem_addr, mem_wdata,
              mem_rdata, mem_ready,
              hit_count, miss_count, wb_count,
              clk, rst_n
    );

endinterface : cache_if

// ======================= cache_assertions.sv ================================
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
