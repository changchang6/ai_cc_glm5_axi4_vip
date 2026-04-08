// AXI4 VIP Parameter Definitions
// Configuration type can be selected via CFG_TYPE define
// Compile with: +define+CFG_TYPE_CFG1 for cfg1 configuration
// Default: DATA_WIDTH=32, ADDR_WIDTH=32, ID_WIDTH=4
// CFG1:    DATA_WIDTH=64, ADDR_WIDTH=48, ID_WIDTH=5

`ifndef AXI4_PARAMS_SVH
`define AXI4_PARAMS_SVH

// Parameter definitions based on CFG_TYPE
`ifdef CFG_TYPE_CFG1
    // CFG1: Maximum configuration
    `define AXI4_DATA_WIDTH 64
    `define AXI4_ADDR_WIDTH 48
    `define AXI4_ID_WIDTH   5
`else
    // DEFAULT configuration
    `define AXI4_DATA_WIDTH 32
    `define AXI4_ADDR_WIDTH 32
    `define AXI4_ID_WIDTH   4
`endif

// Derived parameters
`define AXI4_STRB_WIDTH (`AXI4_DATA_WIDTH / 8)
`define AXI4_USER_WIDTH 16

`endif // AXI4_PARAMS_SVH
