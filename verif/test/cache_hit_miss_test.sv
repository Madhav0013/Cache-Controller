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
