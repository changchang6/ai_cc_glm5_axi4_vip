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

// Burst INCR Test
// Test to verify INCR burst functionality with random burst length [1:16]
// Parameters:
//   - LEN: random inside [1:16] beats per transaction
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: INCR
//   - Start address: aligned to 4 bytes
//   - Number of transactions: 5000
class axi4_burst_incr_test extends axi4_base_test;
    `uvm_component_utils(axi4_burst_incr_test)

    // Test parameters
    int m_num_trans = 5000;

    // Constructor
    function new(string name = "axi4_burst_incr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_burst_incr_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BURST INCR TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:16] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 5000", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_burst_incr_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [0:15] (1-16 beats) - randomized in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: INCR
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 5000
        if (!seq.randomize() with {
            m_len        == 0;            // Will be randomized per transaction in sequence
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == local::m_num_trans; // 5000 transactions
            m_burst      == INCR;         // INCR burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Burst INCR test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_burst_incr_test

// Burst FIXED Test
// Test to verify FIXED burst functionality with random burst length [1:16]
// Parameters:
//   - LEN: random inside [0:15] beats per transaction
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: FIXED
//   - Start address: aligned to 4 bytes
//   - Number of transactions: 500
class axi4_burst_fixed_test extends axi4_base_test;
    `uvm_component_utils(axi4_burst_fixed_test)

    // Test parameters
    int m_num_trans = 5000;

    // Constructor
    function new(string name = "axi4_burst_fixed_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_burst_fixed_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BURST FIXED TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:16] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: FIXED", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_burst_fixed_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [0:15] (1-16 beats) - randomized per transaction in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: FIXED
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 500
        if (!seq.randomize() with {
            m_len        == 0;            // Will be randomized per transaction in sequence
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == local::m_num_trans; // 500 transactions
            m_burst      == FIXED;        // FIXED burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Burst FIXED test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_burst_fixed_test

// Burst WRAP Test
// Test to verify WRAP burst functionality with burst length inside {2, 4, 8, 16}
// Parameters:
//   - LEN: random inside {2, 4, 8, 16} beats per transaction
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: WRAP
//   - Start address: aligned to 4 bytes
//   - Number of transactions: 500
class axi4_burst_wrap_test extends axi4_base_test;
    `uvm_component_utils(axi4_burst_wrap_test)

    // Test parameters
    int m_num_trans = 5000;

    // Constructor
    function new(string name = "axi4_burst_wrap_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_burst_wrap_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BURST WRAP TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random {2, 4, 8, 16} beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: WRAP", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_burst_wrap_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random {1, 3, 7, 15} (2, 4, 8, 16 beats) - randomized per transaction in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: WRAP
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 500
        if (!seq.randomize() with {
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == local::m_num_trans; // 500 transactions
            m_burst      == WRAP;         // WRAP burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Burst WRAP test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_burst_wrap_test

// Burst Random Test
// Test to verify random burst functionality with random burst length and type
// Parameters:
//   - LEN: random inside [0:15] beats per transaction (1-16 beats)
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: random (INCR, FIXED, WRAP)
//   - Start address: aligned to 4 bytes
//   - Number of transactions: 500
class axi4_burst_random_test extends axi4_base_test;
    `uvm_component_utils(axi4_burst_random_test)

    // Test parameters
    int m_num_trans = 5000;

    // Constructor
    function new(string name = "axi4_burst_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_burst_random_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BURST RANDOM TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:16] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: random (INCR/FIXED/WRAP)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_burst_random_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [0:15] (1-16 beats) - randomized per transaction in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: random (INCR/FIXED/WRAP) - randomized per transaction in sequence
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 500
        if (!seq.randomize() with {
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == local::m_num_trans; // 500 transactions
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Burst RANDOM test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_burst_random_test

// Burst Slice Test
// Test to verify INCR burst with large burst length [16:256] beats
// Parameters:
//   - LEN: random inside [15:255] (16-256 beats per transaction)
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: INCR
//   - Start address: aligned to 4 bytes
//   - Number of transactions: 500
class axi4_burst_slice_test extends axi4_base_test;
    `uvm_component_utils(axi4_burst_slice_test)

    // Test parameters
    int m_num_trans = 5000;

    // Constructor
    function new(string name = "axi4_burst_slice_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_burst_slice_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BURST SLICE TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [16:256] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: 0x1000_0000 (aligned)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_burst_slice_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [15:255] (16-256 beats) - randomized per transaction in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: INCR
        // - Start address aligned to 4 bytes (0x1000_0000)
        // - Number of transactions: 500
        if (!seq.randomize() with {
            m_size       == 2;            // 4 bytes per beat
            m_start_addr == 32'h1000_0000; // Aligned start address
            m_num_trans  == local::m_num_trans; // 500 transactions
            m_burst      == INCR;         // INCR burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Burst SLICE test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_burst_slice_test

// Unaligned Address Test
// Test to verify unaligned address transfers with random burst lengths
// Parameters:
//   - LEN: random inside [0:255] (1-256 beats)
//   - SIZE: max_width (4 bytes for 32-bit data)
//   - BURST: INCR
//   - Start address: unaligned (address[1:0] != 2'b00)
//   - Number of rounds: 5
//   - Transactions per round: 100
//   - Total transactions: 500
class axi4_unaligned_addr_test extends axi4_base_test;
    `uvm_component_utils(axi4_unaligned_addr_test)

    // Constructor
    function new(string name = "axi4_unaligned_addr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_unaligned_addr_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 UNALIGNED ADDRESS TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:256] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: unaligned (random per round)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Rounds: 5", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transactions per Round: 100", UVM_NONE)
        `uvm_info(get_type_name(), "  - Total Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_unaligned_addr_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [0:255] (1-256 beats) - randomized per transaction in sequence
        // - SIZE: 2 (4 bytes per beat)
        // - BURST: INCR
        // - 5 rounds, 100 transactions per round = 500 total
        if (!seq.randomize() with {
            m_size                == 2;            // 4 bytes per beat
            m_num_rounds          == 10;            // 5 rounds
            m_num_trans_per_round == 100;          // 100 transactions per round
            m_burst               == INCR;         // INCR burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Unaligned address test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_unaligned_addr_test

// Narrow Transfer Test
// Tests narrow transfers with SIZE = byte/half-word/word (0/1/2)
// Parameters:
//   - LEN: random inside [0:255] (1-256 beats)
//   - SIZE: random inside {0, 1, 2} (byte/half-word/word)
//   - BURST: INCR
//   - Start address: random aligned/unaligned
//   - Number of transactions: 500
class axi4_narrow_test extends axi4_base_test;
    `uvm_component_utils(axi4_narrow_test)

    // Constructor
    function new(string name = "axi4_narrow_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_narrow_sequence seq;

        phase.raise_objection(this);

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 NARROW TRANSFER TEST", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:256] beats", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: byte/half-word/word (SIZE=0/1/2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: random aligned/unaligned", UVM_NONE)
        `uvm_info(get_type_name(), "  - Number of Transactions: 500", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // Create and configure the sequence
        seq = axi4_narrow_sequence::type_id::create("seq");

        // Set test parameters:
        // - LEN: random [0:255] (1-256 beats) - randomized per transaction in sequence
        // - SIZE: random {0, 1, 2} (byte/half-word/word) - randomized per transaction
        // - BURST: INCR
        // - Start address: random aligned/unaligned
        // - Number of transactions: 500
        if (!seq.randomize() with {
            m_num_trans  == 5000;  // 500 transactions
            m_burst      == INCR; // INCR burst type
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        // Start the sequence on the master sequencer
        seq.start(m_env.m_master_agent.m_sequencer);

        // Wait for all transactions to complete
        #1000;

        `uvm_info(get_type_name(), "Narrow transfer test sequence completed", UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass : axi4_narrow_test

`endif // AXI4_TEST_LIB_SV
