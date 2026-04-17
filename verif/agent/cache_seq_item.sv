class cache_seq_item extends uvm_sequence_item;

    rand bit [15:0]  addr;
    rand bit [31:0]  wdata;
    rand bit         wr;    // 1=write, 0=read

    // Response fields (filled by driver/monitor after operation completes)
    bit [31:0]       rdata;
    bit              hit;

    // Constraints
    constraint c_addr_aligned { addr[1:0] == 2'b00; }

    `uvm_object_utils_begin(cache_seq_item)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(wr,    UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_field_int(hit,   UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cache_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%04h wdata=0x%08h rdata=0x%08h hit=%0b",
                          wr ? "WR" : "RD", addr, wdata, rdata, hit);
    endfunction

endclass
