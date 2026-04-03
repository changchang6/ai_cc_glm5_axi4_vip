// AXI4 Test Library
// Contains test cases using the VIP

`ifndef AXI4_TEST_LIB_SV
`define AXI4_TEST_LIB_SV

// Include the original test file which has axi4_base_test
`include "axi4_test.sv"

// Import packages
import uvm_pkg::*;
import axi4_pkg::*;

// Smoke Test
// Basic test to verify VIP functionality with write-readback verification
// Data verification is performed inside the sequence
class axi4_smoke_test extends axi4_base_test;
    `uvm_component_utils(axi4_smoke_test)

    // Test parameters
    // LEN=0 (single beat), SIZE=2 (4 bytes)
    // Start address: aligned to 4 bytes
    // Number of transactions: 10

    // Constructor
    function new(string name = "axi4_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build phase - can override base test configuration here if needed
    // function void build_phase(uvm_phase phase);
    //     super.build_phase(phase);
    //     // Override specific configuration parameters for this test
    //     // m_cfg.m_max_outstanding = 16;
    // endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_smoke_test_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 VIP SMOKE TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: 1 beat (LEN=0)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 10", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_smoke_test_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN=0 (single beat per transaction)
        // - SIZE=2 (4 bytes per beat)
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 10
        if (!seq.randomize() with {
            m_len        == 0;            // Single beat
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == 10;           // 10 transactions
            m_burst      == INCR;         // INCR burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Smoke test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_smoke_test

`endif // AXI4_TEST_LIB_SV
