package cache_pkg;

    // Cache parameters
    parameter int ADDR_WIDTH   = 16;
    parameter int DATA_WIDTH   = 32;
    parameter int CACHE_LINES  = 16;    // Number of cache lines
    parameter int INDEX_WIDTH  = 4;     // log2(CACHE_LINES)
    parameter int OFFSET_WIDTH = 2;     // log2(DATA_WIDTH/8) = log2(4) = 2
    parameter int TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH; // 10

    // FSM states
    typedef enum logic [2:0] {
        IDLE      = 3'b000,
        TAG_CHECK = 3'b001,
        WRITEBACK = 3'b010,
        ALLOCATE  = 3'b011,
        DONE      = 3'b100
    } cache_state_t;

    // Request type
    typedef enum logic {
        READ  = 1'b0,
        WRITE = 1'b1
    } req_type_t;

endpackage : cache_pkg
