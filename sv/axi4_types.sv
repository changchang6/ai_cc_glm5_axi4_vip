// AXI4 Type Definitions
// Contains enums, structs, and typedefs for AXI4 protocol

`ifndef AXI4_TYPES_SV
`define AXI4_TYPES_SV

// Burst type enumeration
typedef enum logic [1:0] {
    FIXED = 2'b00,
    INCR  = 2'b01,
    WRAP  = 2'b10,
    RESV  = 2'b11
} axi4_burst_t;

// Response type enumeration
typedef enum logic [1:0] {
    OKAY   = 2'b00,
    EXOKAY = 2'b01,
    SLVERR = 2'b10,
    DECERR = 2'b11
} axi4_resp_t;

// Transaction type enumeration
typedef enum bit {
    READ  = 1'b0,
    WRITE = 1'b1
} axi4_trans_t;

// Cache attribute definitions (ARCACHE/AWCACHE)
typedef enum logic [3:0] {
    CACHE_DEVICE_NON_BUFFERABLE      = 4'b0000,
    CACHE_DEVICE_BUFFERABLE          = 4'b0001,
    CACHE_NORMAL_NON_CACHEABLE       = 4'b0010,
    CACHE_NORMAL_NON_CACHEABLE_ALLOC = 4'b0011,
    CACHE_WRITE_THROUGH_NO_ALLOC     = 4'b1010,
    CACHE_WRITE_THROUGH_READ_ALLOC   = 4'b1110,
    CACHE_WRITE_BACK_NO_ALLOC        = 4'b1011,
    CACHE_WRITE_BACK_READ_ALLOC      = 4'b1111
} axi4_cache_t;

// Protection attributes (ARPROT/AWPROT)
typedef struct packed {
    logic privilege;  // 0 = unprivileged, 1 = privileged
    logic secure;     // 0 = secure, 1 = non-secure
    logic data;       // 0 = data, 1 = instruction
} axi4_prot_t;

// QoS class (4 bits: 0-15, higher value = higher priority)
typedef logic [3:0] axi4_qos_t;

// Region identifier (4 bits)
typedef logic [3:0] axi4_region_t;

// User extension (configurable width)
typedef logic [15:0] axi4_user_t;

// Write address channel struct
typedef struct packed {
    logic [31:0] awaddr;
    logic [3:0]  awid;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awlock;
    logic [3:0]  awcache;
    logic [2:0]  awprot;
    logic [3:0]  awqos;
    logic [3:0]  awregion;
    logic [15:0] awuser;
} axi4_aw_chan_t;

// Write data channel struct
typedef struct packed {
    logic [255:0] wdata;
    logic [31:0]  wstrb;
    logic         wlast;
    logic [15:0]  wuser;
} axi4_w_chan_t;

// Write response channel struct
typedef struct packed {
    logic [3:0]  bid;
    logic [1:0]  bresp;
    logic [15:0] buser;
} axi4_b_chan_t;

// Read address channel struct
typedef struct packed {
    logic [31:0] araddr;
    logic [3:0]  arid;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arlock;
    logic [3:0]  arcache;
    logic [2:0]  arprot;
    logic [3:0]  arqos;
    logic [3:0]  arregion;
    logic [15:0] aruser;
} axi4_ar_chan_t;

// Read data channel struct
typedef struct packed {
    logic [255:0] rdata;
    logic [3:0]  rid;
    logic [1:0]  rresp;
    logic        rlast;
    logic [15:0] ruser;
} axi4_r_chan_t;

// Transaction status enumeration
typedef enum bit [1:0] {
    TRANS_IDLE,
    TRANS_ACTIVE,
    TRANS_COMPLETE,
    TRANS_ERROR
} axi4_trans_status_t;

// Latency statistics structure
typedef struct {
    int unsigned min_latency;
    int unsigned max_latency;
    int unsigned total_latency;
    int unsigned trans_count;
    logic [3:0]  min_latency_id;
    logic [3:0]  max_latency_id;
} axi4_latency_stats_t;

// Bandwidth statistics structure
typedef struct {
    longint unsigned total_bytes;
    real total_time_ns;
    real bandwidth_mbps;
    real efficiency;
} axi4_bandwidth_stats_t;

`endif // AXI4_TYPES_SV