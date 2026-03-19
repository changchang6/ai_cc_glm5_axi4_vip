// AXI4 Types and Definitions
// This file contains all type definitions, enumerations, and parameters for AXI4 VIP

`ifndef AXI4_TYPES_SV
`define AXI4_TYPES_SV

// Default parameter definitions (can be overridden)
`ifndef AXI4_DATA_WIDTH
  `define AXI4_DATA_WIDTH 128
`endif

`ifndef AXI4_ADDR_WIDTH
  `define AXI4_ADDR_WIDTH 32
`endif

`ifndef AXI4_ID_WIDTH
  `define AXI4_ID_WIDTH 4
`endif

`ifndef AXI4_USER_WIDTH
  `define AXI4_USER_WIDTH 4
`endif

// AXI4 Burst Type Enumeration
typedef enum logic [1:0] {
  AXI4_BURST_FIXED = 2'b00,  // Fixed address burst
  AXI4_BURST_INCR  = 2'b01,   // Incrementing burst
  AXI4_BURST_WRAP  = 2'b10,   // Wrapping burst
  AXI4_BURST_RESERVED = 2'b11 // Reserved (should not be used)
} axi4_burst_type_e;

// AXI4 Response Type Enumeration
typedef enum logic [1:0] {
  AXI4_RESP_OKAY   = 2'b00,  // Normal access success
  AXI4_RESP_EXOKAY = 2'b01,  // Exclusive access okay
  AXI4_RESP_SLVERR = 2'b10,  // Slave error
  AXI4_RESP_DECERR = 2'b11   // Decode error
} axi4_resp_type_e;

// AXI4 Transaction Type Enumeration
typedef enum logic {
  AXI4_TRANS_READ  = 1'b0,   // Read transaction
  AXI4_TRANS_WRITE = 1'b1    // Write transaction
} axi4_transaction_type_e;

// AXI4 Lock Type Enumeration
typedef enum logic [1:0] {
  AXI4_LOCK_NORMAL     = 2'b00,  // Normal access
  AXI4_LOCK_EXCLUSIVE  = 2'b01,  // Exclusive access
  AXI4_LOCK_LOCKED     = 2'b10,  // Locked access
  AXI4_LOCK_RESERVED   = 2'b11   // Reserved
} axi4_lock_type_e;

// AXI4 Cache Attributes (ARCACHE/AWCACHE)
typedef enum logic [3:0] {
  AXI4_CACHE_DEVICE_NON_BUFFERABLE    = 4'b0000,
  AXI4_CACHE_DEVICE_BUFFERABLE        = 4'b0001,
  AXI4_CACHE_NORMAL_NON_CACHEABLE     = 4'b0010,
  AXI4_CACHE_NORMAL_NON_CACHEABLE_BUF = 4'b0011,
  AXI4_CACHE_WRITE_THROUGH_NO_ALLOC   = 4'b0110,
  AXI4_CACHE_WRITE_THROUGH_ALLOC      = 4'b0110,
  AXI4_CACHE_WRITE_BACK_NO_ALLOC      = 4'b1010,
  AXI4_CACHE_WRITE_BACK_ALLOC         = 4'b1110
} axi4_cache_type_e;

// AXI4 Protection Attributes (ARPROT/AWPROT)
typedef struct packed {
  logic privileged;  // Privileged access
  logic non_secure;  // Non-secure access
  logic instruction; // Instruction access
} axi4_prot_t;

// AXI4 QoS Priority Levels
typedef enum logic [3:0] {
  AXI4_QOS_LOWEST    = 4'b0000,
  AXI4_QOS_LOW       = 4'b0011,
  AXI4_QOS_MEDIUM    = 4'b0111,
  AXI4_QOS_HIGH      = 4'b1011,
  AXI4_QOS_HIGHEST   = 4'b1111
} axi4_qos_level_e;

// AXI4 Size Encoding (2^size bytes per transfer)
typedef enum logic [2:0] {
  AXI4_SIZE_1_BYTE   = 3'b000,  // 1 byte
  AXI4_SIZE_2_BYTES  = 3'b001,  // 2 bytes
  AXI4_SIZE_4_BYTES   = 3'b010,  // 4 bytes
  AXI4_SIZE_8_BYTES   = 3'b011,  // 8 bytes
  AXI4_SIZE_16_BYTES  = 3'b100,  // 16 bytes
  AXI4_SIZE_32_BYTES  = 3'b101,  // 32 bytes
  AXI4_SIZE_64_BYTES  = 3'b110,  // 64 bytes
  AXI4_SIZE_128_BYTES = 3'b111   // 128 bytes
} axi4_size_e;

// Function to convert size encoding to byte count
function automatic int axi4_size_to_bytes(logic [2:0] size);
  return (1 << int'(size));
endfunction

// Function to check if address is aligned to transfer size
function automatic bit is_aligned(logic [`AXI4_ADDR_WIDTH-1:0] addr, logic [2:0] size);
  int alignment = axi4_size_to_bytes(size);
  return ((addr & (alignment - 1)) == 0);
endfunction

// Function to calculate lower wrap boundary for WRAP burst
function automatic logic [`AXI4_ADDR_WIDTH-1:0] get_wrap_boundary(
  logic [`AXI4_ADDR_WIDTH-1:0] addr,
  int burst_length,
  int transfer_size
);
  int total_bytes = burst_length * transfer_size;
  return (addr / total_bytes) * total_bytes;
endfunction

// Function to check if address crosses 4KB boundary
function automatic bit crosses_4kb_boundary(
  logic [`AXI4_ADDR_WIDTH-1:0] start_addr,
  int burst_length,
  int transfer_size
);
  logic [`AXI4_ADDR_WIDTH-1:0] end_addr;
  end_addr = start_addr + (burst_length * transfer_size) - 1;
  return (start_addr[11:0] > end_addr[11:0]) ||
         ((start_addr[31:12] != end_addr[31:12]) && (start_addr[11:0] != 0));
endfunction

// Function to check if address crosses 2KB boundary (AXI4 requirement)
function automatic bit crosses_2kb_boundary(
  logic [`AXI4_ADDR_WIDTH-1:0] start_addr,
  int burst_length,
  int transfer_size
);
  logic [`AXI4_ADDR_WIDTH-1:0] end_addr;
  end_addr = start_addr + (burst_length * transfer_size) - 1;
  return (start_addr[31:11] != end_addr[31:11]);
endfunction

// Function to calculate bytes until next 2KB boundary
function automatic int bytes_to_2kb_boundary(logic [`AXI4_ADDR_WIDTH-1:0] addr);
  int offset_in_2kb = int'(addr & 12'h7FF);
  return 2048 - offset_in_2kb;
endfunction

// Constants for AXI4 protocol
localparam AXI4_MAX_BURST_LENGTH_INCR = 256;  // Maximum burst length for INCR (1-256 beats)
localparam AXI4_MAX_BURST_LENGTH_FIXED = 16;  // Maximum burst length for FIXED (1-16 beats)
localparam AXI4_MAX_BURST_LENGTH_WRAP_VALUES[] = '{2, 4, 8, 16};  // Valid WRAP burst lengths

localparam AXI4_BURST_4KB = 4096;  // 4KB boundary
localparam AXI4_BURST_2KB = 2048;  // 2KB boundary (minimum slave requirement)

`endif // AXI4_TYPES_SV