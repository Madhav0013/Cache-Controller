class cache_coverage extends uvm_component;

    `uvm_component_utils(cache_coverage)

    uvm_analysis_imp #(cache_seq_item, cache_coverage) analysis_imp;

    cache_seq_item txn;

    // Extract index from address for coverage
    bit [3:0] addr_index;

    covergroup cache_op_cg;
        rw_cp: coverpoint txn.wr {
            bins read  = {0};
            bins write = {1};
        }
        index_cp: coverpoint addr_index {
            bins idx[] = {[0:15]};  // All 16 cache lines
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
        cache_op_cg    = new();
        addr_pattern_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_imp = new("analysis_imp", this);
    endfunction

    function void write(cache_seq_item t);
        txn = t;
        addr_index = t.addr[5:2];  // Extract index bits
        cache_op_cg.sample();
        addr_pattern_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("Cache Op Coverage: %0.2f%% | Addr Pattern Coverage: %0.2f%%",
                                    cache_op_cg.get_coverage(),
                                    addr_pattern_cg.get_coverage()), UVM_LOW)
    endfunction

endclass
