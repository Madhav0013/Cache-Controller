//=============================================================================
// TESTBENCH.SV — Cache Controller UVM Testbench for EDA Playground (RIGHT PANE)
// BUG FIXES APPLIED:
//   1. Interfaces and assertions in testbench.sv (VCS compilation unit fix)
//   2. Classes at $unit scope (no package wrapper)
//   3. Scoreboard variable declarations at top of write()
//   4. Sequence constraints use local:: to reference task arguments
//=============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import cache_pkg::*;

//=============================================================================
// CACHE INTERFACE
//=============================================================================
interface cache_if #(
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    logic                    cpu_req;
    logic                    cpu_wr;
    logic [ADDR_WIDTH-1:0]   cpu_addr;
    logic [DATA_WIDTH-1:0]   cpu_wdata;
    logic [DATA_WIDTH-1:0]   cpu_rdata;
    logic                    cpu_ready;

    logic                    mem_req;
    logic                    mem_wr;
    logic [ADDR_WIDTH-1:0]   mem_addr;
    logic [DATA_WIDTH-1:0]   mem_wdata;
    logic [DATA_WIDTH-1:0]   mem_rdata;
    logic                    mem_ready;

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

//=============================================================================
// SVA ASSERTIONS MODULE
//=============================================================================
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
    input logic              cpu_req,
    input logic              cpu_wr,
    input logic [ADDR_W-1:0] cpu_addr,
    input logic [DATA_W-1:0] cpu_wdata,
    input logic [DATA_W-1:0] cpu_rdata,
    input logic              cpu_ready,
    input logic              mem_req,
    input logic              mem_wr,
    input logic [ADDR_W-1:0] mem_addr,
    input logic [DATA_W-1:0] mem_wdata,
    input logic              mem_ready,
    input cache_state_t      state,
    input logic [31:0]       hit_count,
    input logic [31:0]       miss_count,
    input logic [31:0]       wb_count
);

    // FP1: FSM always returns to IDLE (liveness)
    FP1_FSM_LIVENESS: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state != IDLE) |-> ##[1:100] (state == IDLE)
    ) else $error("[FP1] FSM stuck — did not return to IDLE within 100 cycles");

    // FP2: No cpu_ready without being in DONE state
    FP2_NO_SPURIOUS_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(cpu_ready) |-> (state == DONE)
    ) else $error("[FP2] cpu_ready asserted outside of DONE state");

    // FP3: DONE state always asserts cpu_ready
    FP3_DONE_IMPLIES_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == DONE) |-> cpu_ready
    ) else $error("[FP3] FSM in DONE but cpu_ready not asserted");

    // FP4: Writeback state always writes to memory
    FP4_WRITEBACK_BEFORE_ALLOCATE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == WRITEBACK) |-> (mem_req && mem_wr)
    ) else $error("[FP4] In WRITEBACK state but not writing to memory");

    // FP5: Allocate reads from memory (not writes)
    FP5_ALLOCATE_IS_READ: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == ALLOCATE && mem_req) |-> !mem_wr
    ) else $error("[FP5] In ALLOCATE state but mem_wr is asserted");

    // FP6: Memory address alignment
    FP6_MEM_ADDR_ALIGNED: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_req |-> (mem_addr[OFF_W-1:0] == '0)
    ) else $error("[FP6] Memory address not word-aligned");

    // FP7: Hit and miss counts are monotonically increasing
    FP7_HIT_COUNT_MONOTONIC: assert property (
        @(posedge clk) disable iff (!rst_n)
        1 |=> (hit_count >= $past(hit_count))
    ) else $error("[FP7] Hit count decreased");

    FP7B_MISS_COUNT_MONOTONIC: assert property (
        @(posedge clk) disable iff (!rst_n)
        1 |=> (miss_count >= $past(miss_count))
    ) else $error("[FP7B] Miss count decreased");

    // FP8: After reset, FSM is in IDLE
    FP8_RESET_STATE: assert property (
        @(posedge clk)
        !rst_n |=> (state == IDLE)
    ) else $error("[FP8] FSM not in IDLE after reset");

    // Cover properties
    C1_READ_HIT: cover property (
        @(posedge clk) cpu_req && !cpu_wr ##[1:10] (cpu_ready && (state == DONE))
    );

    C2_WRITE_HIT: cover property (
        @(posedge clk) cpu_req && cpu_wr ##[1:10] (cpu_ready && (state == DONE))
    );

    C3_DIRTY_WRITEBACK: cover property (
        @(posedge clk) (state == TAG_CHECK) ##1 (state == WRITEBACK)
    );

    C4_CLEAN_MISS: cover property (
        @(posedge clk) (state == TAG_CHECK) ##1 (state == ALLOCATE)
    );

    C5_FULL_DIRTY_MISS: cover property (
        @(posedge clk) (state == TAG_CHECK)
            ##1 (state == WRITEBACK)
            ##[1:50] (state == ALLOCATE)
            ##[1:50] (state == DONE)
    );

endmodule : cache_assertions

//=============================================================================
// UVM CLASSES
//=============================================================================

//--- cache_seq_item ---
class cache_seq_item extends uvm_sequence_item;

    rand bit [15:0]  addr;
    rand bit [31:0]  wdata;
    rand bit         wr;

    bit [31:0]       rdata;
    bit              hit;

    constraint c_addr_aligned { addr[1:0] == 2'b00; }

    `uvm_object_utils_begin(cache_seq_item)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(wr,    UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_field_int(hit,   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cache_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%04h wdata=0x%08h rdata=0x%08h hit=%0b",
                          wr ? "WR" : "RD", addr, wdata, rdata, hit);
    endfunction

endclass

//--- cache_sequencer ---
class cache_sequencer extends uvm_sequencer #(cache_seq_item);
    `uvm_component_utils(cache_sequencer)
    function new(string name = "cache_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass

//--- cache_driver ---
class cache_driver extends uvm_driver #(cache_seq_item);

    `uvm_component_utils(cache_driver)
    virtual cache_if vif;

    function new(string name = "cache_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cache_if)::get(this, "", "cache_vif", vif))
            `uvm_fatal("DRV", "Cannot get cache_vif from config_db")
    endfunction

    task run_phase(uvm_phase phase);
        cache_seq_item txn;
        @(posedge vif.clk);
        vif.cpu_req   <= 1'b0;
        vif.cpu_wr    <= 1'b0;
        vif.cpu_addr  <= '0;
        vif.cpu_wdata <= '0;

        @(posedge vif.rst_n);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(txn);
            drive_txn(txn);
            seq_item_port.item_done();
        end
    endtask

    task drive_txn(cache_seq_item txn);
        @(posedge vif.clk);
        vif.cpu_req   <= 1'b1;
        vif.cpu_wr    <= txn.wr;
        vif.cpu_addr  <= txn.addr;
        vif.cpu_wdata <= txn.wdata;

        @(posedge vif.clk);
        vif.cpu_req <= 1'b0;

        while (!vif.cpu_ready) @(posedge vif.clk);

        if (!txn.wr) txn.rdata = vif.cpu_rdata;

        @(posedge vif.clk);
    endtask

endclass

//--- cache_monitor ---
class cache_monitor extends uvm_monitor;

    `uvm_component_utils(cache_monitor)
    virtual cache_if vif;
    uvm_analysis_port #(cache_seq_item) ap;

    function new(string name = "cache_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual cache_if)::get(this, "", "cache_vif", vif))
            `uvm_fatal("MON", "Cannot get cache_vif from config_db")
    endfunction

    task run_phase(uvm_phase phase);
        cache_seq_item txn;
        @(posedge vif.rst_n);
        forever begin
            @(posedge vif.clk);
            if (vif.cpu_req) begin
                txn = cache_seq_item::type_id::create("txn");
                txn.wr    = vif.cpu_wr;
                txn.addr  = vif.cpu_addr;
                txn.wdata = vif.cpu_wdata;

                while (!vif.cpu_ready) @(posedge vif.clk);
                txn.rdata = vif.cpu_rdata;

                `uvm_info("MON", $sformatf("Cache: %s", txn.convert2string()), UVM_HIGH)
                ap.write(txn);
            end
        end
    endtask

endclass

//--- cache_agent ---
class cache_agent extends uvm_agent;

    `uvm_component_utils(cache_agent)

    cache_driver    drv;
    cache_monitor   mon;
    cache_sequencer sqr;

    function new(string name = "cache_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = cache_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv = cache_driver::type_id::create("drv", this);
            sqr = cache_sequencer::type_id::create("sqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

//--- cache_scoreboard ---
class cache_scoreboard extends uvm_component;

    `uvm_component_utils(cache_scoreboard)

    uvm_analysis_imp #(cache_seq_item, cache_scoreboard) analysis_imp;

    bit [31:0] golden_memory [bit [15:0]];

    int txn_count;
    int pass_count;
    int fail_count;
    int read_count;
    int write_count;

    function new(string name = "cache_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_imp = new("analysis_imp", this);
    endfunction

    function void write(cache_seq_item txn);
        bit [31:0] expected;

        txn_count++;

        if (txn.wr) begin
            golden_memory[txn.addr] = txn.wdata;
            write_count++;
            pass_count++;
            `uvm_info("SB", $sformatf("WRITE: addr=0x%04h data=0x%08h (stored in golden model)",
                                       txn.addr, txn.wdata), UVM_MEDIUM)
        end else begin
            read_count++;

            if (golden_memory.exists(txn.addr)) begin
                expected = golden_memory[txn.addr];
            end else begin
                expected = 32'h0;
            end

            if (txn.rdata === expected) begin
                pass_count++;
                `uvm_info("SB", $sformatf("READ MATCH: addr=0x%04h expected=0x%08h got=0x%08h",
                                           txn.addr, expected, txn.rdata), UVM_MEDIUM)
            end else begin
                fail_count++;
                `uvm_error("SB", $sformatf("READ MISMATCH: addr=0x%04h expected=0x%08h got=0x%08h",
                                            txn.addr, expected, txn.rdata))
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SB", "========================================", UVM_LOW)
        `uvm_info("SB", "       SCOREBOARD SUMMARY              ", UVM_LOW)
        `uvm_info("SB", "========================================", UVM_LOW)
        `uvm_info("SB", $sformatf("  Total transactions : %0d", txn_count), UVM_LOW)
        `uvm_info("SB", $sformatf("  Writes             : %0d", write_count), UVM_LOW)
        `uvm_info("SB", $sformatf("  Reads              : %0d", read_count), UVM_LOW)
        `uvm_info("SB", $sformatf("  Checks passed      : %0d", pass_count), UVM_LOW)
        `uvm_info("SB", $sformatf("  Checks failed      : %0d", fail_count), UVM_LOW)
        `uvm_info("SB", "========================================", UVM_LOW)
        if (fail_count == 0)
            `uvm_info("SB", "TEST PASSED", UVM_LOW)
        else
            `uvm_error("SB", $sformatf("TEST FAILED: %0d mismatches", fail_count))
    endfunction

endclass

//--- cache_coverage ---
class cache_coverage extends uvm_component;

    `uvm_component_utils(cache_coverage)

    uvm_analysis_imp #(cache_seq_item, cache_coverage) analysis_imp;

    cache_seq_item txn;
    bit [3:0] addr_index;

    covergroup cache_op_cg;
        rw_cp: coverpoint txn.wr {
            bins read  = {0};
            bins write = {1};
        }
        index_cp: coverpoint addr_index {
            bins idx[] = {[0:15]};
        }
        rw_x_index: cross rw_cp, index_cp;
    endgroup

    covergroup addr_pattern_cg;
        addr_cp: coverpoint txn.addr[7:2] {
            bins low_addr  = {[0:15]};
            bins high_addr = {[16:63]};
        }
    endgroup

    function new(string name = "cache_coverage", uvm_component parent = null);
        super.new(name, parent);
        cache_op_cg     = new();
        addr_pattern_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_imp = new("analysis_imp", this);
    endfunction

    function void write(cache_seq_item t);
        txn = t;
        addr_index = t.addr[5:2];
        cache_op_cg.sample();
        addr_pattern_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Cache Op Coverage: %0.2f%% | Addr Pattern Coverage: %0.2f%%",
                                    cache_op_cg.get_coverage(),
                                    addr_pattern_cg.get_coverage()), UVM_LOW)
    endfunction

endclass

//--- cache_env ---
class cache_env extends uvm_env;

    `uvm_component_utils(cache_env)

    cache_agent       agt;
    cache_scoreboard  sb;
    cache_coverage    cov;

    function new(string name = "cache_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = cache_agent::type_id::create("agt", this);
        sb  = cache_scoreboard::type_id::create("sb", this);
        cov = cache_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.mon.ap.connect(sb.analysis_imp);
        agt.mon.ap.connect(cov.analysis_imp);
    endfunction

endclass

//=============================================================================
// SEQUENCES (FIX: all constraints use local:: for task argument references)
//=============================================================================

class cache_base_seq extends uvm_sequence #(cache_seq_item);

    `uvm_object_utils(cache_base_seq)

    function new(string name = "cache_base_seq");
        super.new(name);
    endfunction

    task write_addr(bit [15:0] addr, bit [31:0] data);
        cache_seq_item t;
        t = cache_seq_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with { t.wr == 1; t.addr == local::addr; t.wdata == local::data; })
            `uvm_error("SEQ", "Randomization failed")
        finish_item(t);
    endtask

    task read_addr(bit [15:0] addr);
        cache_seq_item t;
        t = cache_seq_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with { t.wr == 0; t.addr == local::addr; })
            `uvm_error("SEQ", "Randomization failed")
        finish_item(t);
    endtask

endclass

class cache_smoke_seq extends cache_base_seq;
    `uvm_object_utils(cache_smoke_seq)
    function new(string name = "cache_smoke_seq"); super.new(name); endfunction
    task body();
        `uvm_info("SEQ", "Smoke: write then read one address", UVM_LOW)
        write_addr(16'h0100, 32'hDEADBEEF);
        read_addr(16'h0100);
    endtask
endclass

class cache_hit_miss_seq extends cache_base_seq;
    `uvm_object_utils(cache_hit_miss_seq)
    function new(string name = "cache_hit_miss_seq"); super.new(name); endfunction
    task body();
        int i;
        `uvm_info("SEQ", "Hit/Miss: write 8 addrs, read back (hits), read new (misses)", UVM_LOW)
        for (i = 0; i < 8; i++)
            write_addr(16'h0000 + (i * 4), 32'hA000_0000 + i);
        for (i = 0; i < 8; i++)
            read_addr(16'h0000 + (i * 4));
        for (i = 0; i < 4; i++)
            read_addr(16'h1000 + (i * 4));
    endtask
endclass

class cache_eviction_seq extends cache_base_seq;
    `uvm_object_utils(cache_eviction_seq)
    function new(string name = "cache_eviction_seq"); super.new(name); endfunction
    task body();
        `uvm_info("SEQ", "Eviction: force dirty evictions by writing to same-index addresses", UVM_LOW)
        write_addr(16'h0100, 32'hAAAA_AAAA);
        read_addr(16'h0100);
        write_addr(16'h0500, 32'hBBBB_BBBB);
        read_addr(16'h0500);
        read_addr(16'h0100);
    endtask
endclass

class cache_thrash_seq extends cache_base_seq;
    `uvm_object_utils(cache_thrash_seq)
    function new(string name = "cache_thrash_seq"); super.new(name); endfunction
    task body();
        int i;
        `uvm_info("SEQ", "Thrash: write 32 addrs (2x cache), force full eviction cycle", UVM_LOW)
        for (i = 0; i < 16; i++)
            write_addr(16'h0000 + (i * 4), 32'hF000_0000 + i);
        for (i = 0; i < 16; i++)
            write_addr(16'h1000 + (i * 4), 32'hE000_0000 + i);
        for (i = 0; i < 16; i++)
            read_addr(16'h1000 + (i * 4));
        for (i = 0; i < 16; i++)
            read_addr(16'h0000 + (i * 4));
    endtask
endclass

class cache_random_seq extends cache_base_seq;
    `uvm_object_utils(cache_random_seq)
    rand int num_txns;
    constraint c_num { num_txns inside {[50:100]}; }

    function new(string name = "cache_random_seq"); super.new(name); endfunction

    task body();
        cache_seq_item t;
        int i;
        `uvm_info("SEQ", $sformatf("Random: %0d transactions", num_txns), UVM_LOW)
        for (i = 0; i < num_txns; i++) begin
            t = cache_seq_item::type_id::create($sformatf("t_%0d", i));
            start_item(t);
            if (!t.randomize() with {
                t.addr[1:0] == 2'b00;
                t.addr[15:6] inside {[0:7]};
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(t);
        end
    endtask
endclass

//=============================================================================
// TESTS
//=============================================================================

class cache_base_test extends uvm_test;
    `uvm_component_utils(cache_base_test)
    cache_env env;

    function new(string name = "cache_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = cache_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction
endclass

class cache_smoke_test extends cache_base_test;
    `uvm_component_utils(cache_smoke_test)
    function new(string name = "cache_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_smoke_seq seq;
        phase.raise_objection(this);
        seq = cache_smoke_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        #500ns;
        phase.drop_objection(this);
    endtask
endclass

class cache_hit_miss_test extends cache_base_test;
    `uvm_component_utils(cache_hit_miss_test)
    function new(string name = "cache_hit_miss_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_hit_miss_seq seq;
        phase.raise_objection(this);
        seq = cache_hit_miss_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        #500ns;
        phase.drop_objection(this);
    endtask
endclass

class cache_eviction_test extends cache_base_test;
    `uvm_component_utils(cache_eviction_test)
    function new(string name = "cache_eviction_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_eviction_seq seq;
        phase.raise_objection(this);
        seq = cache_eviction_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        #500ns;
        phase.drop_objection(this);
    endtask
endclass

class cache_thrash_test extends cache_base_test;
    `uvm_component_utils(cache_thrash_test)
    function new(string name = "cache_thrash_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_thrash_seq seq;
        phase.raise_objection(this);
        seq = cache_thrash_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        #2000ns;
        phase.drop_objection(this);
    endtask
endclass

class cache_random_test extends cache_base_test;
    `uvm_component_utils(cache_random_test)
    function new(string name = "cache_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_random_seq seq;
        phase.raise_objection(this);
        seq = cache_random_seq::type_id::create("seq");
        if (!seq.randomize())
            `uvm_error("TEST", "Sequence randomization failed")
        seq.start(env.agt.sqr);
        #5000ns;
        phase.drop_objection(this);
    endtask
endclass


//=============================================================================
// TB_TOP MODULE
//=============================================================================
module tb_top;

    logic clk = 0;
    logic rst_n;

    initial forever #5 clk = ~clk;
    initial begin
        rst_n = 0;
        #50 rst_n = 1;
    end

    cache_if #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) cif (.clk(clk), .rst_n(rst_n));

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
    // Simple memory model — 1 cycle latency responder
    // =========================================================================
    bit [31:0] main_memory [bit [15:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cif.mem_ready <= 1'b0;
            cif.mem_rdata <= '0;
        end else begin
            cif.mem_ready <= 1'b0;
            if (cif.mem_req) begin
                cif.mem_ready <= 1'b1;
                if (cif.mem_wr) begin
                    main_memory[cif.mem_addr] = cif.mem_wdata;
                end else begin
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

    initial begin
        #5000000;
        `uvm_fatal("TIMEOUT", "Simulation timeout")
    end

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
