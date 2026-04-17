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
