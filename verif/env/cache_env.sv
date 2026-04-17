class cache_env extends uvm_env;

    `uvm_component_utils(cache_env)

    cache_agent       agt;
    cache_scoreboard  sb;
    cache_coverage    cov;

    function new(string name = "cache_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = cache_agent::type_id::create("agt", this);
        sb  = cache_scoreboard::type_id::create("sb", this);
        cov = cache_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agt.mon.ap.connect(sb.analysis_imp);
        agt.mon.ap.connect(cov.analysis_imp);
    endfunction

endclass
