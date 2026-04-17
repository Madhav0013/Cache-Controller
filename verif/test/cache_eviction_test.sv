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
