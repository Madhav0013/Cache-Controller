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

                // Wait for completion
                while (!vif.cpu_ready) @(posedge vif.clk);
                txn.rdata = vif.cpu_rdata;

                `uvm_info("MON", $sformatf("Cache: %s", txn.convert2string()), UVM_HIGH)
                ap.write(txn);
            end
        end
    endtask

endclass
