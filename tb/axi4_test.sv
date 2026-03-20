// AXI4 Test Library
// Contains base test and example test cases

`ifndef AXI4_TEST_SV
`define AXI4_TEST_SV

// Import packages
import uvm_pkg::*;
import axi4_pkg::*;

// Base Test
class axi4_base_test extends uvm_test;
    `uvm_component_utils(axi4_base_test)

    // Environment
    axi4_env m_env;

    // Configuration
    axi4_config m_cfg;

    // Constructor
    function new(string name = "axi4_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get configuration from config_db
        if (!uvm_config_db#(axi4_config)::get(this, "", "m_cfg", m_cfg)) begin
            `uvm_warning(get_type_name(), "Configuration not found, creating default")
            m_cfg = axi4_config::type_id::create("m_cfg");
        end

        // Create environment
        m_env = axi4_env::type_id::create("m_env", this);

        `uvm_info(get_type_name(), "Base test built", UVM_HIGH)
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        phase.drop_objection(this);
    endtask

    // Report phase
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), "Test completed", UVM_MEDIUM)
    endfunction

endclass : axi4_base_test

// Single Write Test
class axi4_single_write_test extends axi4_base_test;
    `uvm_component_utils(axi4_single_write_test)

    // Constructor
    function new(string name = "axi4_single_write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_single_write_sequence seq;

        phase.raise_objection(this);

        seq = axi4_single_write_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h1000_0000;
            m_len == 0;  // Single beat
            m_size == 2;  // 4 bytes
            m_burst == INCR;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_single_write_test

// Single Read Test
class axi4_single_read_test extends axi4_base_test;
    `uvm_component_utils(axi4_single_read_test)

    // Constructor
    function new(string name = "axi4_single_read_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_single_read_sequence seq;

        phase.raise_objection(this);

        seq = axi4_single_read_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h2000_0000;
            m_len == 0;  // Single beat
            m_size == 2;  // 4 bytes
            m_burst == INCR;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_single_read_test

// Random Burst Test
class axi4_random_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_random_burst_test)

    // Number of transactions
    int m_num_trans = 50;

    // Constructor
    function new(string name = "axi4_random_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_mixed_sequence seq;

        phase.raise_objection(this);

        seq = axi4_mixed_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_num_trans == local::m_num_trans;
            m_read_ratio == 50;  // 50% reads, 50% writes
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_random_burst_test

// Fixed Burst Test
class axi4_fixed_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_fixed_burst_test)

    // Constructor
    function new(string name = "axi4_fixed_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_fixed_burst_write_sequence seq;

        phase.raise_objection(this);

        seq = axi4_fixed_burst_write_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h3000_0000;
            m_num_beats == 8;  // 8 beat FIXED burst
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_fixed_burst_test

// Wrap Burst Test
class axi4_wrap_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_wrap_burst_test)

    // Constructor
    function new(string name = "axi4_wrap_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_wrap_burst_read_sequence seq;

        phase.raise_objection(this);

        seq = axi4_wrap_burst_read_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h4000_0000;
            m_num_beats == 4;  // 4 beat WRAP burst
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_wrap_burst_test

// Long INCR Burst Test (tests burst splitting)
class axi4_long_burst_test extends axi4_base_test;
    `uvm_component_utils(axi4_long_burst_test)

    // Constructor
    function new(string name = "axi4_long_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_long_incr_sequence seq;

        phase.raise_objection(this);

        seq = axi4_long_incr_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h5000_0000;
            m_num_beats == 64;  // 64 beat burst (will be split)
            m_is_write == 1;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_long_burst_test

// Unaligned Transfer Test
class axi4_unaligned_test extends axi4_base_test;
    `uvm_component_utils(axi4_unaligned_test)

    // Constructor
    function new(string name = "axi4_unaligned_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_unaligned_sequence seq;

        phase.raise_objection(this);

        seq = axi4_unaligned_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h6000_0003;  // Unaligned address
            m_num_beats == 4;
            m_is_write == 1;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_unaligned_test

// 2KB Boundary Crossing Test
class axi4_2kb_boundary_test extends axi4_base_test;
    `uvm_component_utils(axi4_2kb_boundary_test)

    // Constructor
    function new(string name = "axi4_2kb_boundary_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_2kb_boundary_sequence seq;

        phase.raise_objection(this);

        seq = axi4_2kb_boundary_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_start_addr == 32'h7000_07F8;  // Near 2KB boundary
            m_num_beats == 8;
            m_size == 2;  // 4 bytes per beat
            m_is_write == 1;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_2kb_boundary_test

// WSTRB Mask Test
class axi4_wstrb_mask_test extends axi4_base_test;
    `uvm_component_utils(axi4_wstrb_mask_test)

    // Constructor
    function new(string name = "axi4_wstrb_mask_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_wstrb_mask_sequence seq;

        phase.raise_objection(this);

        seq = axi4_wstrb_mask_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_addr == 32'h8000_0000;
            m_wstrb_pattern == 32'b1011;  // Non-contiguous WSTRB
            m_num_beats == 1;
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_wstrb_mask_test

// Bandwidth Efficiency Test
class axi4_bandwidth_test extends axi4_base_test;
    `uvm_component_utils(axi4_bandwidth_test)

    int m_num_trans = 100;

    // Constructor
    function new(string name = "axi4_bandwidth_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        axi4_back_to_back_sequence seq;

        phase.raise_objection(this);

        seq = axi4_back_to_back_sequence::type_id::create("seq");
        if (!seq.randomize() with {
            m_num_trans == local::m_num_trans;
            m_is_write == 0;  // Read test
        }) begin
            `uvm_error(get_type_name(), "Sequence randomization failed")
        end

        seq.start(m_env.m_master_agent.m_sequencer);

        phase.drop_objection(this);
    endtask

endclass : axi4_bandwidth_test

`endif // AXI4_TEST_SV