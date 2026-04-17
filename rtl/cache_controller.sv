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
    // Hit/miss logic
    // =========================================================================
    logic cache_hit;
    assign cache_hit = valid_array[req_index] && (tag_array[req_index] == req_tag);

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
                    if (valid_array[req_index] && dirty_array[req_index])
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
            cpu_ready  <= 1'b0;
            mem_req    <= 1'b0;
            mem_wr     <= 1'b0;
            mem_addr   <= '0;
            mem_wdata  <= '0;
            hit_count  <= '0;
            miss_count <= '0;
            wb_count   <= '0;
        end else begin
            // Defaults
            cpu_ready <= 1'b0;
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
                        // Writeback complete — now allocate (read new line from memory)
                        mem_req  <= 1'b1;
                        mem_wr   <= 1'b0;
                        mem_addr <= cpu_addr_reg;
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
                    cpu_ready <= 1'b1;
                end
            endcase
        end
    end

endmodule : cache_controller
