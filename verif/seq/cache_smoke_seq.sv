class cache_smoke_seq extends cache_base_seq;
    `uvm_object_utils(cache_smoke_seq)
    function new(string name = "cache_smoke_seq"); super.new(name); endfunction
    task body();
        `uvm_info("SEQ", "Smoke: write then read one address", UVM_LOW)
        write_addr(16'h0100, 32'hDEADBEEF);
        read_addr(16'h0100);
    endtask
endclass
