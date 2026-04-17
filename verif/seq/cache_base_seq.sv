class cache_base_seq extends uvm_sequence #(cache_seq_item);

    `uvm_object_utils(cache_base_seq)

    function new(string name = "cache_base_seq");
        super.new(name);
    endfunction

    task write_addr(bit [15:0] addr, bit [31:0] data);
        cache_seq_item t;
        t = cache_seq_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with { t.wr == 1; t.addr == addr; t.wdata == data; })
            `uvm_error("SEQ", "Randomization failed")
        finish_item(t);
    endtask

    task read_addr(bit [15:0] addr);
        cache_seq_item t;
        t = cache_seq_item::type_id::create("t");
        start_item(t);
        if (!t.randomize() with { t.wr == 0; t.addr == addr; })
            `uvm_error("SEQ", "Randomization failed")
        finish_item(t);
    endtask

endclass
