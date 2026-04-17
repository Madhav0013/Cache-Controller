class cache_random_test extends cache_base_test;
    `uvm_component_utils(cache_random_test)
    function new(string name = "cache_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
        cache_random_seq seq;
        phase.raise_objection(this);
        seq = cache_random_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
        #5000ns;
        phase.drop_objection(this);
    endtask
endclass
