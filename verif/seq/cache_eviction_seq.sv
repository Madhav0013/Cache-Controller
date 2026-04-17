class cache_eviction_seq extends cache_base_seq;
    `uvm_object_utils(cache_eviction_seq)
    function new(string name = "cache_eviction_seq"); super.new(name); endfunction
    task body();
        `uvm_info("SEQ", "Eviction: force dirty evictions by writing to same-index addresses", UVM_LOW)
        // Write to addr 0x0100 (index = addr[5:2] = 0)
        write_addr(16'h0100, 32'hAAAA_AAAA);
        // Read it back (should hit)
        read_addr(16'h0100);
        // Write to addr 0x0500 — same index as 0x0100 (bits [5:2] match), different tag
        // This forces eviction of the dirty line at index 0
        write_addr(16'h0500, 32'hBBBB_BBBB);
        // Read 0x0500 — should hit
        read_addr(16'h0500);
        // Read 0x0100 — should miss (was evicted), but writeback should have saved it to memory
        read_addr(16'h0100);
    endtask
endclass
