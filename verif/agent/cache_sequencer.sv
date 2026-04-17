class cache_sequencer extends uvm_sequencer #(cache_seq_item);
    `uvm_component_utils(cache_sequencer)
    function new(string name = "cache_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
