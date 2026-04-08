// AXI4 VIP Package
// Contains all AXI4 VIP components

`timescale 1ns/1ps

`ifndef AXI4_PKG_SV
`define AXI4_PKG_SV

package axi4_pkg;

    // Import UVM package
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Parameter definitions (must be included first)
    `include "axi4_params.svh"

    // Type definitions
    `include "axi4_types.sv"

    // Configuration
    `include "axi4_config.sv"

    // Transaction
    `include "axi4_transaction.sv"

    // Sequencer
    `include "axi4_sequencer.sv"

    // Sequences
    `include "axi4_sequence.sv"
    `include "seq_lib.sv"

    // Monitor
    `include "axi4_monitor.sv"

    // Driver
    `include "axi4_master_driver.sv"

    // Agent
    `include "axi4_master_agent.sv"

    // Environment
    `include "axi4_env.sv"

endpackage : axi4_pkg

`endif // AXI4_PKG_SV