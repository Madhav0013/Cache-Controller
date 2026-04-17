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
