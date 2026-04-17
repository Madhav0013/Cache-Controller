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
