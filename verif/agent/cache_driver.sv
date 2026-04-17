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
        // Initialize signals
        @(posedge vif.clk);
        vif.cpu_req   <= 1'b0;
        vif.cpu_wr    <= 1'b0;
        vif.cpu_addr  <= '0;
        vif.cpu_wdata <= '0;

        // Wait for reset deassertion
        @(posedge vif.rst_n);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(txn);
            drive_txn(txn);
            seq_item_port.item_done();
        end
    endtask

    task drive_txn(cache_seq_item txn);
        // Assert request
        @(posedge vif.clk);
        vif.cpu_req   <= 1'b1;
        vif.cpu_wr    <= txn.wr;
        vif.cpu_addr  <= txn.addr;
        vif.cpu_wdata <= txn.wdata;

        // Deassert request on next cycle (pulse)
        @(posedge vif.clk);
        vif.cpu_req <= 1'b0;

        // Wait for cpu_ready
        while (!vif.cpu_ready) @(posedge vif.clk);

        // Capture response
        if (!txn.wr) txn.rdata = vif.cpu_rdata;

        // One idle cycle between transactions
        @(posedge vif.clk);
    endtask

endclass
