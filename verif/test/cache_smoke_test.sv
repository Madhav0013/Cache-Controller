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
