class cache_random_seq extends cache_base_seq;
    `uvm_object_utils(cache_random_seq)
    rand int num_txns;
    constraint c_num { num_txns inside {[50:100]}; }

    function new(string name = "cache_random_seq"); super.new(name); endfunction

    task body();
        cache_seq_item t;
        int i;
        `uvm_info("SEQ", $sformatf("Random: %0d transactions", num_txns), UVM_LOW)
        for (i = 0; i < num_txns; i++) begin
            t = cache_seq_item::type_id::create($sformatf("t_%0d", i));
            start_item(t);
            if (!t.randomize() with {
                t.addr[1:0] == 2'b00;
                t.addr[15:6] inside {[0:7]};  // Limit tag range to force collisions
            })
                `uvm_error("SEQ", "Randomization failed")
            finish_item(t);
        end
    endtask
endclass
