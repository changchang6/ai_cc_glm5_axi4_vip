// AXI4 Sequence Library
// Contains reusable test sequences

`ifndef AXI4_SEQ_LIB_SV
`define AXI4_SEQ_LIB_SV

// Smoke Test Sequence
// Sends multiple write transactions followed by read-back verification
class axi4_smoke_test_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_smoke_test_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1
    rand bit [2:0]  m_size;          // Burst size encoding
    rand axi4_burst_t m_burst;       // Burst type

    // Write data storage for read-back verification
    // Map: address -> write data
    protected bit [255:0] m_write_data_map[bit [31:0]];

    // Constraints
    constraint c_num_trans {
        m_num_trans inside {[1:100]};
    }

    constraint c_len {
        m_len <= 255;
    }

    constraint c_size {
        m_size <= 5;  // Max 128 bytes per beat
    }

    constraint c_addr_aligned {
        // Address must be aligned to transfer size
        m_start_addr % (2 ** m_size) == 0;
    }

    // Constructor
    function new(string name = "axi4_smoke_test_sequence");
        super.new(name);
    endfunction

    // Store write data for later verification
    function void store_write_data(bit [31:0] addr, bit [255:0] data);
        m_write_data_map[addr] = data;
    endfunction

    // Get stored write data
    function bit [255:0] get_write_data(bit [31:0] addr);
        if (m_write_data_map.exists(addr)) begin
            return m_write_data_map[addr];
        end else begin
            return {256{1'b0}};
        end
    endfunction

    // Check if address has stored write data
    function bit has_write_data(bit [31:0] addr);
        return m_write_data_map.exists(addr);
    endfunction

    // Body - Write then Read-back with verification
    task body();
        axi4_transaction wr_trans, rd_trans;
        bit [31:0] current_addr;
        bit [31:0] addr_queue[$];  // Queue to store addresses for read-back
        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;

        `uvm_info(get_type_name(), $sformatf(
            "Starting smoke test sequence: %0d transactions, LEN=%0d, SIZE=%0d, ADDR=0x%08h",
            m_num_trans, m_len, m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        == local::m_len;
                m_size       == local::m_size;
                m_burst      == local::m_burst;
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            start_item(wr_trans);
            finish_item(wr_trans);

            // Store write data and address for verification
            if (wr_trans.m_wdata.size() > 0) begin
                store_write_data(current_addr, wr_trans.m_wdata[0]);
                addr_queue.push_back(current_addr);
            end

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, DATA=0x%08h",
                trans_count + 1, wr_trans.m_addr, wr_trans.m_wdata[0][31:0]), UVM_HIGH)

            current_addr += (m_len + 1) * (2 ** m_size);
            trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_trans), UVM_MEDIUM)

        // ============================================================
        // Step 4: Read back and verify data
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        // Read back from each address
        foreach (addr_queue[i]) begin
            rd_trans = axi4_transaction::type_id::create("rd_trans");

            if (!rd_trans.randomize() with {
                m_trans_type == READ;
                m_addr       == local::addr_queue[i];
                m_len        == local::m_len;
                m_size       == local::m_size;
                m_burst      == local::m_burst;
            }) begin
                `uvm_error(get_type_name(), "Read transaction randomization failed")
                return;
            end

            start_item(rd_trans);
            finish_item(rd_trans);

            // Get expected data
            expected_data = get_write_data(addr_queue[i]);

            // Get actual read data from transaction
            if (rd_trans.m_wdata.size() > 0) begin
                actual_data = rd_trans.m_wdata[0];

                // Compare data
                if (actual_data[31:0] == expected_data[31:0]) begin
                    pass_count++;
                    `uvm_info(get_type_name(), $sformatf(
                        "READ PASS #%0d: ADDR=0x%08h, DATA=0x%08h",
                        i + 1, addr_queue[i], actual_data[31:0]), UVM_MEDIUM)
                end else begin
                    fail_count++;
                    `uvm_error(get_type_name(), $sformatf(
                        "READ FAIL #%0d: ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h",
                        i + 1, addr_queue[i], expected_data[31:0], actual_data[31:0]))
                end
            end else begin
                fail_count++;
                `uvm_error(get_type_name(), $sformatf(
                    "READ #%0d: ADDR=0x%08h - No data returned",
                    i + 1, addr_queue[i]))
            end
        end

        // ============================================================
        // Summary - Verification results from sequence
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE, %0d READ",
            m_num_trans, m_num_trans), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_smoke_test_sequence

`endif // AXI4_SEQ_LIB_SV
