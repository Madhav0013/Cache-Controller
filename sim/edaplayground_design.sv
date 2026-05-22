//=============================================================================
// DESIGN.SV — Cache Controller RTL for EDA Playground (LEFT PANE)
// BUG FIXES APPLIED:
//   1. cache_hit uses registered address (req_index_reg/req_tag_reg)
//   2. integer i at module scope (VCS-safe)
//   3. cpu_ready is combinational: assign cpu_ready = (state == DONE)
//   4. alloc_req_sent flag prevents ALLOCATE from accepting stale
//      mem_ready left over from WRITEBACK response
//=============================================================================

//=============================================================================
// FILE 1: cache_pkg.sv
//=============================================================================
package cache_pkg;

    parameter int ADDR_WIDTH   = 16;
    parameter int DATA_WIDTH   = 32;
    parameter int CACHE_LINES  = 16;
    parameter int INDEX_WIDTH  = 4;
    parameter int OFFSET_WIDTH = 2;
    parameter int TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;

    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        TAG_CHECK = 3'b001,
        WRITEBACK = 3'b010,
        ALLOCATE  = 3'b011,
        DONE      = 3'b100
    } cache_state_t;

    typedef enum logic {
        READ  = 1'b0,
        WRITE = 1'b1
    } req_type_t;

endpackage : cache_pkg

//=============================================================================
// FILE 2: cache_controller.sv
//=============================================================================
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

    input  logic                cpu_req,
    input  logic                cpu_wr,
    input  logic [ADDR_W-1:0]  cpu_addr,
    input  logic [DATA_W-1:0]  cpu_wdata,
    output logic [DATA_W-1:0]  cpu_rdata,
    output logic                cpu_ready,

    output logic                mem_req,
    output logic                mem_wr,
    output logic [ADDR_W-1:0]  mem_addr,
    output logic [DATA_W-1:0]  mem_wdata,
    input  logic [DATA_W-1:0]  mem_rdata,
    input  logic                mem_ready,

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
    // Registered request fields (captured on cpu_req in IDLE)
    // =========================================================================
    logic                cpu_wr_reg;
    logic [ADDR_W-1:0]   cpu_addr_reg;
    logic [DATA_W-1:0]   cpu_wdata_reg;
    logic [TAG_W-1:0]    req_tag_reg;
    logic [IDX_W-1:0]    req_index_reg;

    // =========================================================================
    // Allocate-request-sent flag — prevents ALLOCATE from accepting stale
    // mem_ready left over from the WRITEBACK memory response
    // =========================================================================
    logic alloc_req_sent;

    // =========================================================================
    // Hit/miss logic — uses REGISTERED address
    // =========================================================================
    logic cache_hit;
    assign cache_hit = valid_array[req_index_reg] && (tag_array[req_index_reg] == req_tag_reg);

    // =========================================================================
    // FSM
    // =========================================================================
    cache_state_t state, next_state;

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
                if (mem_ready && alloc_req_sent)
                    next_state = DONE;
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // cpu_ready — combinational, asserted when FSM is in DONE state
    // FIX: was registered (1-cycle delay caused SVA FP2/FP3 failures)
    // =========================================================================
    assign cpu_ready = (state == DONE);

    // =========================================================================
    // Capture request on IDLE→TAG_CHECK transition
    // =========================================================================
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

    // =========================================================================
    // Datapath
    // =========================================================================
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < LINES; i = i + 1) begin
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
            alloc_req_sent <= 1'b0;
        end else begin
            mem_req   <= 1'b0;

            case (state)
                IDLE: begin
                    // Wait for cpu_req
                end

                TAG_CHECK: begin
                    if (cache_hit) begin
                        hit_count <= hit_count + 1;
                        if (cpu_wr_reg) begin
                            data_array[req_index_reg]  <= cpu_wdata_reg;
                            dirty_array[req_index_reg] <= 1'b1;
                        end else begin
                            cpu_rdata <= data_array[req_index_reg];
                        end
                    end else begin
                        miss_count <= miss_count + 1;
                        if (valid_array[req_index_reg] && dirty_array[req_index_reg]) begin
                            mem_req   <= 1'b1;
                            mem_wr    <= 1'b1;
                            mem_addr  <= {tag_array[req_index_reg], req_index_reg, {OFF_W{1'b0}}};
                            mem_wdata <= data_array[req_index_reg];
                            wb_count  <= wb_count + 1;
                            alloc_req_sent <= 1'b0;  // Will be set when ALLOCATE issues its read
                        end else begin
                            mem_req  <= 1'b1;
                            mem_wr   <= 1'b0;
                            mem_addr <= cpu_addr_reg;
                            alloc_req_sent <= 1'b1;  // Allocate read issued here (clean miss)
                        end
                    end
                end

                WRITEBACK: begin
                    if (mem_ready) begin
                        // Writeback complete — do NOT issue allocate read yet.
                        // mem_req defaults to 0 (from top of always_ff).
                        // ALLOCATE will issue its own read and set alloc_req_sent.
                    end else begin
                        mem_req   <= 1'b1;
                        mem_wr    <= 1'b1;
                        mem_addr  <= {tag_array[req_index_reg], req_index_reg, {OFF_W{1'b0}}};
                        mem_wdata <= data_array[req_index_reg];
                    end
                end

                ALLOCATE: begin
                    if (mem_ready && alloc_req_sent) begin
                        valid_array[req_index_reg] <= 1'b1;
                        tag_array[req_index_reg]   <= req_tag_reg;
                        alloc_req_sent <= 1'b0;
                        if (cpu_wr_reg) begin
                            data_array[req_index_reg]  <= cpu_wdata_reg;
                            dirty_array[req_index_reg] <= 1'b1;
                        end else begin
                            data_array[req_index_reg]  <= mem_rdata;
                            dirty_array[req_index_reg] <= 1'b0;
                            cpu_rdata <= mem_rdata;
                        end
                    end else begin
                        mem_req  <= 1'b1;
                        mem_wr   <= 1'b0;
                        mem_addr <= cpu_addr_reg;
                        alloc_req_sent <= 1'b1;
                    end
                end

                DONE: begin
                    // cpu_ready is combinational — nothing needed here
                end
            endcase
        end
    end

endmodule : cache_controller
