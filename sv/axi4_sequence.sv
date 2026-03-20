// AXI4 Sequences
// Contains base sequence and common test sequences

`ifndef AXI4_SEQUENCE_SV
`define AXI4_SEQUENCE_SV

// Base AXI4 Sequence
class axi4_base_sequence extends uvm_sequence #(axi4_transaction);
    `uvm_object_utils(axi4_base_sequence)
    `uvm_declare_p_sequencer(axi4_sequencer)

    // Configuration handle
    axi4_config m_cfg;

    // Constructor
    function new(string name = "axi4_base_sequence");
        super.new(name);
    endfunction

    // Pre-start - raise objection
    task pre_start();
        if (starting_phase != null) begin
            starting_phase.raise_objection(this);
        end
    endtask

    // Post-start - drop objection
    task post_start();
        if (starting_phase != null) begin
            starting_phase.drop_objection(this);
        end
    endtask

    // Get configuration
    task get_config();
        uvm_config_db#(axi4_config)::get(null, get_full_name(), "m_cfg", m_cfg);
    endtask

endclass : axi4_base_sequence

// Simple Write Sequence - Single write transaction
class axi4_single_write_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_single_write_sequence)

    // Transaction parameters
    rand bit [31:0] m_addr;
    rand bit [7:0]  m_len;
    rand bit [2:0]  m_size;
    rand axi4_burst_t m_burst;

    // Constructor
    function new(string name = "axi4_single_write_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == WRITE;
            m_addr == local::m_addr;
            m_len == local::m_len;
            m_size == local::m_size;
            m_burst == local::m_burst;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent write transaction: ADDR=0x%08h, LEN=%0d",
            trans.m_addr, trans.m_len), UVM_MEDIUM)
    endtask

endclass : axi4_single_write_sequence

// Simple Read Sequence - Single read transaction
class axi4_single_read_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_single_read_sequence)

    // Transaction parameters
    rand bit [31:0] m_addr;
    rand bit [7:0]  m_len;
    rand bit [2:0]  m_size;
    rand axi4_burst_t m_burst;

    // Constructor
    function new(string name = "axi4_single_read_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == READ;
            m_addr == local::m_addr;
            m_len == local::m_len;
            m_size == local::m_size;
            m_burst == local::m_burst;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent read transaction: ADDR=0x%08h, LEN=%0d",
            trans.m_addr, trans.m_len), UVM_MEDIUM)
    endtask

endclass : axi4_single_read_sequence

// Random Write Sequence - Random write transactions
class axi4_random_write_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_random_write_sequence)

    // Number of transactions
    rand int m_num_trans;

    constraint c_num_trans {
        m_num_trans inside {[1:100]};
    }

    // Constructor
    function new(string name = "axi4_random_write_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        `uvm_info(get_type_name(), $sformatf(
            "Starting %0d random write transactions", m_num_trans), UVM_MEDIUM)

        repeat (m_num_trans) begin
            trans = axi4_transaction::type_id::create("trans");
            if (!trans.randomize() with {
                m_trans_type == WRITE;
            }) begin
                `uvm_error(get_type_name(), "Randomization failed")
                return;
            end

            start_item(trans);
            finish_item(trans);
        end

        `uvm_info(get_type_name(), "Random write sequence completed", UVM_MEDIUM)
    endtask

endclass : axi4_random_write_sequence

// Random Read Sequence - Random read transactions
class axi4_random_read_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_random_read_sequence)

    // Number of transactions
    rand int m_num_trans;

    constraint c_num_trans {
        m_num_trans inside {[1:100]};
    }

    // Constructor
    function new(string name = "axi4_random_read_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        `uvm_info(get_type_name(), $sformatf(
            "Starting %0d random read transactions", m_num_trans), UVM_MEDIUM)

        repeat (m_num_trans) begin
            trans = axi4_transaction::type_id::create("trans");
            if (!trans.randomize() with {
                m_trans_type == READ;
            }) begin
                `uvm_error(get_type_name(), "Randomization failed")
                return;
            end

            start_item(trans);
            finish_item(trans);
        end

        `uvm_info(get_type_name(), "Random read sequence completed", UVM_MEDIUM)
    endtask

endclass : axi4_random_read_sequence

// Mixed Read/Write Sequence
class axi4_mixed_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_mixed_sequence)

    // Number of transactions
    rand int m_num_trans;
    rand int m_read_ratio;  // Percentage of reads (0-100)

    constraint c_num_trans {
        m_num_trans inside {[1:100]};
    }

    constraint c_read_ratio {
        m_read_ratio inside {[0:100]};
    }

    // Constructor
    function new(string name = "axi4_mixed_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;
        int rand_val;

        `uvm_info(get_type_name(), $sformatf(
            "Starting %0d mixed transactions (read ratio=%0d%%)",
            m_num_trans, m_read_ratio), UVM_MEDIUM)

        repeat (m_num_trans) begin
            trans = axi4_transaction::type_id::create("trans");

            rand_val = $urandom_range(0, 99);

            if (!trans.randomize() with {
                m_trans_type == (rand_val < m_read_ratio) ? READ : WRITE;
            }) begin
                `uvm_error(get_type_name(), "Randomization failed")
                return;
            end

            start_item(trans);
            finish_item(trans);
        end

        `uvm_info(get_type_name(), "Mixed sequence completed", UVM_MEDIUM)
    endtask

endclass : axi4_mixed_sequence

// Fixed Burst Write Sequence
class axi4_fixed_burst_write_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_fixed_burst_write_sequence)

    rand bit [31:0] m_addr;
    rand int m_num_beats;  // 1-16 beats for FIXED burst

    constraint c_num_beats {
        m_num_beats inside {[1:16]};
    }

    // Constructor
    function new(string name = "axi4_fixed_burst_write_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == WRITE;
            m_addr == local::m_addr;
            m_burst == FIXED;
            m_len == local::m_num_beats - 1;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent FIXED burst write: ADDR=0x%08h, Beats=%0d",
            trans.m_addr, m_num_beats), UVM_MEDIUM)
    endtask

endclass : axi4_fixed_burst_write_sequence

// Wrap Burst Read Sequence
class axi4_wrap_burst_read_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_wrap_burst_read_sequence)

    rand bit [31:0] m_addr;
    rand int m_num_beats;  // 2, 4, 8, or 16 beats for WRAP burst

    constraint c_num_beats {
        m_num_beats inside {2, 4, 8, 16};
    }

    constraint c_addr_aligned {
        // Address must be aligned for WRAP burst
        // This is a soft constraint
    }

    // Constructor
    function new(string name = "axi4_wrap_burst_read_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == READ;
            m_addr == local::m_addr;
            m_burst == WRAP;
            m_len == local::m_num_beats - 1;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent WRAP burst read: ADDR=0x%08h, Beats=%0d",
            trans.m_addr, m_num_beats), UVM_MEDIUM)
    endtask

endclass : axi4_wrap_burst_read_sequence

// Long INCR Burst Sequence (to test burst splitting)
class axi4_long_incr_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_long_incr_sequence)

    rand bit [31:0] m_addr;
    rand int m_num_beats;  // > 16 to trigger burst splitting
    rand bit m_is_write;

    constraint c_num_beats {
        m_num_beats inside {[17:256]};
    }

    // Constructor
    function new(string name = "axi4_long_incr_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == (m_is_write ? WRITE : READ);
            m_addr == local::m_addr;
            m_burst == INCR;
            m_len == local::m_num_beats - 1;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent long INCR burst: ADDR=0x%08h, Beats=%0d, Type=%s",
            trans.m_addr, m_num_beats, m_is_write ? "WRITE" : "READ"), UVM_MEDIUM)
    endtask

endclass : axi4_long_incr_sequence

// Unaligned Transfer Sequence
class axi4_unaligned_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_unaligned_sequence)

    rand bit [31:0] m_addr;
    rand int m_num_beats;
    rand bit m_is_write;

    constraint c_unaligned_addr {
        // Force unaligned address
        m_addr[1:0] != 2'b00;
    }

    constraint c_num_beats {
        m_num_beats inside {[1:16]};
    }

    // Constructor
    function new(string name = "axi4_unaligned_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");

        // Disable aligned constraint for unaligned transfer
        trans.c_addr_aligned_soft.constraint_mode(0);

        if (!trans.randomize() with {
            m_trans_type == (m_is_write ? WRITE : READ);
            m_addr == local::m_addr;
            m_len == local::m_num_beats - 1;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent unaligned transfer: ADDR=0x%08h, Beats=%0d, Type=%s",
            trans.m_addr, m_num_beats, m_is_write ? "WRITE" : "READ"), UVM_MEDIUM)
    endtask

endclass : axi4_unaligned_sequence

// 2KB Boundary Crossing Sequence (to test burst splitting)
class axi4_2kb_boundary_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_2kb_boundary_sequence)

    rand bit [31:0] m_start_addr;
    rand int m_num_beats;
    rand bit [2:0] m_size;
    rand bit m_is_write;

    constraint c_near_boundary {
        // Start address near 2KB boundary
        m_start_addr[11:0] inside {[2040:2047]};
    }

    constraint c_num_beats {
        m_num_beats inside {[2:16]};
    }

    constraint c_size {
        m_size inside {0, 1, 2, 3};  // 1, 2, 4, 8 bytes
    }

    // Constructor
    function new(string name = "axi4_2kb_boundary_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        trans = axi4_transaction::type_id::create("trans");
        if (!trans.randomize() with {
            m_trans_type == (m_is_write ? WRITE : READ);
            m_addr == local::m_start_addr;
            m_len == local::m_num_beats - 1;
            m_size == local::m_size;
            m_burst == INCR;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent 2KB boundary crossing: ADDR=0x%08h, Beats=%0d, Size=%0d bytes",
            trans.m_addr, m_num_beats, 1 << m_size), UVM_MEDIUM)
    endtask

endclass : axi4_2kb_boundary_sequence

// Back-to-back Sequence (maximum throughput test)
class axi4_back_to_back_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_back_to_back_sequence)

    rand int m_num_trans;
    rand bit m_is_write;

    constraint c_num_trans {
        m_num_trans inside {[1:50]};
    }

    // Constructor
    function new(string name = "axi4_back_to_back_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;

        `uvm_info(get_type_name(), $sformatf(
            "Starting %0d back-to-back %s transactions",
            m_num_trans, m_is_write ? "write" : "read"), UVM_MEDIUM)

        repeat (m_num_trans) begin
            trans = axi4_transaction::type_id::create("trans");
            if (!trans.randomize() with {
                m_trans_type == (m_is_write ? WRITE : READ);
                m_len <= 3;  // Short bursts for throughput test
            }) begin
                `uvm_error(get_type_name(), "Randomization failed")
                return;
            end

            start_item(trans);
            finish_item(trans);
        end

        `uvm_info(get_type_name(), "Back-to-back sequence completed", UVM_MEDIUM)
    endtask

endclass : axi4_back_to_back_sequence

// WSTRB Non-contiguous Mask Test Sequence
class axi4_wstrb_mask_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_wstrb_mask_sequence)

    rand bit [31:0] m_addr;
    rand bit [31:0] m_wstrb_pattern;  // Non-contiguous WSTRB pattern
    rand int m_num_beats;

    constraint c_num_beats {
        m_num_beats inside {[1:4]};
    }

    // Constructor
    function new(string name = "axi4_wstrb_mask_sequence");
        super.new(name);
    endfunction

    // Body
    task body();
        axi4_transaction trans;
        bit [31:0] wstrb_arr[];

        trans = axi4_transaction::type_id::create("trans");
        wstrb_arr = new[m_num_beats];

        // Apply non-contiguous WSTRB pattern to all beats
        for (int i = 0; i < m_num_beats; i++) begin
            wstrb_arr[i] = m_wstrb_pattern;
        end

        if (!trans.randomize() with {
            m_trans_type == WRITE;
            m_addr == local::m_addr;
            m_len == local::m_num_beats - 1;
        }) begin
            `uvm_error(get_type_name(), "Randomization failed")
            return;
        end

        // Override WSTRB with non-contiguous pattern
        trans.m_wstrb = wstrb_arr;

        start_item(trans);
        finish_item(trans);

        `uvm_info(get_type_name(), $sformatf(
            "Sent WSTRB mask write: ADDR=0x%08h, WSTRB=0b%08b",
            trans.m_addr, m_wstrb_pattern), UVM_MEDIUM)
    endtask

endclass : axi4_wstrb_mask_sequence

`endif // AXI4_SEQUENCE_SV