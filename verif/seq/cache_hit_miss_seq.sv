class cache_hit_miss_seq extends cache_base_seq;
    `uvm_object_utils(cache_hit_miss_seq)
    function new(string name = "cache_hit_miss_seq"); super.new(name); endfunction
    task body();
        int i;
        `uvm_info("SEQ", "Hit/Miss: write 8 addresses, read them back (hits), read new ones (misses)", UVM_LOW)
        // Write 8 unique addresses (different indices)
        for (i = 0; i < 8; i++)
            write_addr(16'h0000 + (i * 4), 32'hA000_0000 + i);
        // Read them back — should all be hits
        for (i = 0; i < 8; i++)
            read_addr(16'h0000 + (i * 4));
        // Read 4 new addresses that haven't been written — misses, read from uninitialized memory
        for (i = 0; i < 4; i++)
            read_addr(16'h1000 + (i * 4));
    endtask
endclass
