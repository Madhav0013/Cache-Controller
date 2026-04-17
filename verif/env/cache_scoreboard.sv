class cache_scoreboard extends uvm_component;

    `uvm_component_utils(cache_scoreboard)

    uvm_analysis_imp #(cache_seq_item, cache_scoreboard) analysis_imp;

    // Golden memory model — models the "correct" behavior
    bit [31:0] golden_memory [bit [15:0]];  // Associative array: addr → data

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
        txn_count++;

        if (txn.wr) begin
            // WRITE: update golden model
            golden_memory[txn.addr] = txn.wdata;
            write_count++;
            pass_count++;  // Writes always "pass" (no RTL output to check)
            `uvm_info("SB", $sformatf("WRITE: addr=0x%04h data=0x%08h (stored in golden model)",
                                       txn.addr, txn.wdata), UVM_MEDIUM)
        end else begin
            // READ: compare RTL response against golden model
            bit [31:0] expected;
            read_count++;

            if (golden_memory.exists(txn.addr)) begin
                expected = golden_memory[txn.addr];
            end else begin
                expected = 32'h0;  // Uninitialized memory reads as 0
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
