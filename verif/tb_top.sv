`timescale 1ns/1ps

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import cache_pkg::*;

    logic clk = 0;
    logic rst_n;

    // Clock generation — 100 MHz
    initial forever #5 clk = ~clk;

    // Reset
    initial begin
        rst_n = 0;
        #50 rst_n = 1;
    end

    // Interface instantiation
    cache_if #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) cif (.clk(clk), .rst_n(rst_n));

    // DUT instantiation
    cache_controller dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .cpu_req   (cif.cpu_req),
        .cpu_wr    (cif.cpu_wr),
        .cpu_addr  (cif.cpu_addr),
        .cpu_wdata (cif.cpu_wdata),
        .cpu_rdata (cif.cpu_rdata),
        .cpu_ready (cif.cpu_ready),
        .mem_req   (cif.mem_req),
        .mem_wr    (cif.mem_wr),
        .mem_addr  (cif.mem_addr),
        .mem_wdata (cif.mem_wdata),
        .mem_rdata (cif.mem_rdata),
        .mem_ready (cif.mem_ready),
        .hit_count (cif.hit_count),
        .miss_count(cif.miss_count),
        .wb_count  (cif.wb_count)
    );

    // =========================================================================
    // Simple memory model (slave responder)
    // Responds to cache memory-side requests with 1-cycle latency
    // =========================================================================
    logic [31:0] main_memory [logic [15:0]];  // Associative array models main memory

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cif.mem_ready <= 1'b0;
            cif.mem_rdata <= '0;
        end else begin
            cif.mem_ready <= 1'b0;
            if (cif.mem_req) begin
                cif.mem_ready <= 1'b1;
                if (cif.mem_wr) begin
                    // Write to memory
                    main_memory[cif.mem_addr] = cif.mem_wdata;
                end else begin
                    // Read from memory
                    if (main_memory.exists(cif.mem_addr))
                        cif.mem_rdata <= main_memory[cif.mem_addr];
                    else
                        cif.mem_rdata <= 32'h0;
                end
            end
        end
    end

    // =========================================================================
    // SVA assertions
    // =========================================================================
    cache_assertions #(
        .ADDR_W(16), .DATA_W(32), .LINES(16),
        .IDX_W(4), .TAG_W(10), .OFF_W(2)
    ) sva_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .cpu_req   (cif.cpu_req),
        .cpu_wr    (cif.cpu_wr),
        .cpu_addr  (cif.cpu_addr),
        .cpu_wdata (cif.cpu_wdata),
        .cpu_rdata (cif.cpu_rdata),
        .cpu_ready (cif.cpu_ready),
        .mem_req   (cif.mem_req),
        .mem_wr    (cif.mem_wr),
        .mem_addr  (cif.mem_addr),
        .mem_wdata (cif.mem_wdata),
        .mem_ready (cif.mem_ready),
        .state     (dut.state),
        .hit_count (cif.hit_count),
        .miss_count(cif.miss_count),
        .wb_count  (cif.wb_count)
    );

    // =========================================================================
    // UVM config and run
    // =========================================================================
    initial begin
        uvm_config_db#(virtual cache_if)::set(null, "*", "cache_vif", cif);
        run_test();
    end

    // Watchdog
    initial begin
        #5000000;  // 5ms
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end

    // VCD dump
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
