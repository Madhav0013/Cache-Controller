class cache_thrash_seq extends cache_base_seq;
    `uvm_object_utils(cache_thrash_seq)
    function new(string name = "cache_thrash_seq"); super.new(name); endfunction
    task body();
        int i;
        `uvm_info("SEQ", "Thrash: write to 32 addresses (2x cache size), forcing full eviction cycle", UVM_LOW)
        // Fill all 16 lines with writes
        for (i = 0; i < 16; i++)
            write_addr(16'h0000 + (i * 4), 32'hF000_0000 + i);
        // Now write 16 more with different tags but same indices — evict all dirty lines
        for (i = 0; i < 16; i++)
            write_addr(16'h1000 + (i * 4), 32'hE000_0000 + i);
        // Read back the second set — should all hit
        for (i = 0; i < 16; i++)
            read_addr(16'h1000 + (i * 4));
        // Read back the first set — should all miss, data comes from memory (was written back)
        for (i = 0; i < 16; i++)
            read_addr(16'h0000 + (i * 4));
    endtask
endclass
