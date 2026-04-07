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

// Burst INCR Test Sequence
// Sends multiple INCR burst write transactions followed by read-back verification
// Parameters:
//   - LEN: random inside [1:16] (m_len inside [0:15])
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: INCR
//   - Start address: aligned
//   - Number of transactions: configurable (default 5000)
class axi4_burst_incr_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_burst_incr_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (0-15 for 1-16 beats)
    rand bit [2:0]  m_size;          // Burst size encoding (fixed to 2)
    rand axi4_burst_t m_burst;       // Burst type (fixed to INCR)

    // Write data storage for read-back verification
    // Map: address -> write data array (for burst transfers)
    protected bit [255:0] m_write_data_map[bit [31:0]];

    // Constraints
    constraint c_num_trans {
        m_num_trans inside {[1:10000]};
    }

    constraint c_len {
        // LEN inside [1:16], m_len = LEN - 1, so m_len inside [0:15]
        m_len inside {[0:15]};
    }

    constraint c_size {
        // SIZE = max_width, for 32-bit data width, size = 2 (4 bytes)
        m_size == 2;
    }

    constraint c_burst {
        m_burst == INCR;
    }

    constraint c_addr_aligned {
        // Address must be aligned to transfer size (4 bytes)
        m_start_addr % (2 ** m_size) == 0;
    }

    // Constructor
    function new(string name = "axi4_burst_incr_sequence");
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

        // Burst info storage for read-back verification
        typedef struct {
            bit [31:0] start_addr;
            bit [7:0]  len;
            int        beats;
        } burst_info_t;
        burst_info_t burst_queue[$];

        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;

        `uvm_info(get_type_name(), $sformatf(
            "Starting BURST INCR test sequence: %0d transactions, LEN=random[1:16], SIZE=%0d bytes, BURST=INCR, ADDR=0x%08h",
            m_num_trans, 2 ** m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Randomize LEN for each transaction
            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        inside {[0:15]};  // 1-16 beats
                m_size       == local::m_size;
                m_burst      == INCR;
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            // Save transaction parameters BEFORE sending (wdata may be modified after finish_item)
            saved_len = wr_trans.m_len;
            beats_in_burst = saved_len + 1;
            bytes_per_beat = 2 ** m_size;
            total_bytes = beats_in_burst * bytes_per_beat;
            burst_start_addr = wr_trans.m_addr;  // Use transaction's address

            // Store write data for each beat in the burst BEFORE sending
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                bit [31:0] beat_addr;
                bit [255:0] beat_data;
                beat_addr = burst_start_addr + beat * bytes_per_beat;
                if (wr_trans.m_wdata.size() > beat) begin
                    beat_data = wr_trans.m_wdata[beat];
                    store_write_data(beat_addr, beat_data);
                    `uvm_info(get_type_name(), $sformatf(
                        "Stored: beat=%0d, addr=0x%08h, data=0x%08h",
                        beat, beat_addr, beat_data[31:0]), UVM_HIGH)
                end
            end

            // Store burst info for burst read-back
            burst_queue.push_back('{start_addr: burst_start_addr, len: saved_len, beats: beats_in_burst});

            start_item(wr_trans);
            finish_item(wr_trans);

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, LEN=%0d beats, SIZE=%0d bytes",
                trans_count + 1, wr_trans.m_addr, beats_in_burst, bytes_per_beat), UVM_HIGH)

            // Update current address for next transaction
            current_addr += total_bytes;

            trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_trans), UVM_MEDIUM)

        // ============================================================
        // Step 4: Read back and verify data using BURST reads
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification (BURST mode) ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        // Read back each burst using the same burst pattern as write
        // Note: Driver may split bursts that cross 2KB boundaries
        foreach (burst_queue[i]) begin
            bit [31:0] rd_start_addr;
            bit [7:0]  rd_len;
            int        rd_beats;
            int        remaining_beats;
            bit [31:0] current_rd_addr;

            rd_start_addr = burst_queue[i].start_addr;
            rd_len = burst_queue[i].len;
            rd_beats = burst_queue[i].beats;
            remaining_beats = rd_beats;
            current_rd_addr = rd_start_addr;

            // Handle potential burst splitting by driver (2KB boundary)
            while (remaining_beats > 0) begin
                bit [31:0] next_2kb_boundary;
                int bytes_until_boundary;
                int beats_this_burst;
                int actual_beats_received;

                // Calculate bytes until 2KB boundary
                next_2kb_boundary = ((current_rd_addr / 2048) + 1) * 2048;
                bytes_until_boundary = next_2kb_boundary - current_rd_addr;

                // Calculate beats for this sub-burst (limited by 2KB boundary)
                beats_this_burst = remaining_beats;
                if (bytes_until_boundary < remaining_beats * bytes_per_beat) begin
                    beats_this_burst = bytes_until_boundary / bytes_per_beat;
                    if (beats_this_burst == 0) beats_this_burst = 1;
                end

                rd_trans = axi4_transaction::type_id::create("rd_trans");

                // Read with calculated burst length (may be split)
                if (!rd_trans.randomize() with {
                    m_trans_type == READ;
                    m_addr       == local::current_rd_addr;
                    m_len        == local::beats_this_burst - 1;  // LEN = beats - 1
                    m_size       == local::m_size;
                    m_burst      == INCR;
                }) begin
                    `uvm_error(get_type_name(), "Read transaction randomization failed")
                    return;
                end

                start_item(rd_trans);
                finish_item(rd_trans);

                actual_beats_received = rd_trans.m_wdata.size();

                // Verify each beat in this sub-burst
                for (int beat = 0; beat < actual_beats_received; beat++) begin
                    bit [31:0] beat_addr;
                    beat_addr = current_rd_addr + beat * bytes_per_beat;

                    // Get expected data
                    expected_data = get_write_data(beat_addr);

                    // Get actual read data from transaction
                    if (rd_trans.m_wdata.size() > beat) begin
                        actual_data = rd_trans.m_wdata[beat];

                        // Compare data (only compare relevant bits based on data width)
                        if (actual_data[31:0] == expected_data[31:0]) begin
                            pass_count++;
                            `uvm_info(get_type_name(), $sformatf(
                                "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%08h",
                                i + 1, beat + 1, beat_addr, actual_data[31:0]), UVM_HIGH)
                        end else begin
                            fail_count++;
                            `uvm_error(get_type_name(), $sformatf(
                                "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h",
                                i + 1, beat + 1, beat_addr, expected_data[31:0], actual_data[31:0]))
                        end
                    end else begin
                        fail_count++;
                        `uvm_error(get_type_name(), $sformatf(
                            "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h - No data returned",
                            i + 1, beat + 1, beat_addr))
                    end
                end

                // Update for next sub-burst
                remaining_beats -= actual_beats_received;
                current_rd_addr += actual_beats_received * bytes_per_beat;
            end
        end

        // ============================================================
        // Summary - Verification results from sequence
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE bursts, %0d READ bursts",
            m_num_trans, burst_queue.size()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_burst_incr_sequence

// Burst FIXED Test Sequence
// Sends multiple FIXED burst write transactions followed by read-back verification
// Parameters:
//   - LEN: random inside [0:15] (1-16 beats)
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: FIXED
//   - Start address: aligned
//   - Number of transactions: configurable (default 500)
class axi4_burst_fixed_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_burst_fixed_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (0-15 for 1-16 beats)
    rand bit [2:0]  m_size;          // Burst size encoding (fixed to 2)
    rand axi4_burst_t m_burst;       // Burst type (fixed to FIXED)

    // Write data storage for read-back verification
    // Map: address -> write data array (for burst transfers)
    protected bit [255:0] m_write_data_map[bit [31:0]];

    // Constraints
    constraint c_num_trans {
        m_num_trans inside {[1:10000]};
    }

    constraint c_len {
        // LEN inside [0:15], so m_len inside [0:15]
        m_len inside {[0:15]};
    }

    constraint c_size {
        // SIZE = max_width, for 32-bit data width, size = 2 (4 bytes)
        m_size == 2;
    }

    constraint c_burst {
        m_burst == FIXED;
    }

    constraint c_addr_aligned {
        // Address must be aligned to transfer size (4 bytes)
        m_start_addr % (2 ** m_size) == 0;
    }

    // Constructor
    function new(string name = "axi4_burst_fixed_sequence");
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

        // Burst info storage for read-back verification
        typedef struct {
            bit [31:0] start_addr;
            bit [7:0]  len;
            int        beats;
        } burst_info_t;
        burst_info_t burst_queue[$];

        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;

        `uvm_info(get_type_name(), $sformatf(
            "Starting BURST FIXED test sequence: %0d transactions, LEN=random[1:16], SIZE=%0d bytes, BURST=FIXED, ADDR=0x%08h",
            m_num_trans, 2 ** m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Randomize LEN for each transaction
            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        inside {[0:15]};  // 1-16 beats
                m_size       == local::m_size;
                m_burst      == FIXED;
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            // Save transaction parameters BEFORE sending (wdata may be modified after finish_item)
            saved_len = wr_trans.m_len;
            beats_in_burst = saved_len + 1;
            bytes_per_beat = 2 ** m_size;
            total_bytes = beats_in_burst * bytes_per_beat;
            burst_start_addr = wr_trans.m_addr;  // Use transaction's address

            // Store write data for each beat in the burst BEFORE sending
            // For FIXED burst, all beats are written to the SAME address
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                bit [31:0] beat_addr;
                bit [255:0] beat_data;
                // FIXED burst: all beats use the same start address
                beat_addr = burst_start_addr;
                if (wr_trans.m_wdata.size() > beat) begin
                    beat_data = wr_trans.m_wdata[beat];
                    store_write_data(beat_addr, beat_data);
                    `uvm_info(get_type_name(), $sformatf(
                        "Stored: beat=%0d, addr=0x%08h, data=0x%08h",
                        beat, beat_addr, beat_data[31:0]), UVM_HIGH)
                end
            end

            // Store burst info for burst read-back
            burst_queue.push_back('{start_addr: burst_start_addr, len: saved_len, beats: beats_in_burst});

            start_item(wr_trans);
            finish_item(wr_trans);

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, LEN=%0d beats, SIZE=%0d bytes",
                trans_count + 1, wr_trans.m_addr, beats_in_burst, bytes_per_beat), UVM_HIGH)

            // Update current address for next transaction
            // For FIXED burst, each transaction still advances to avoid overlap
            current_addr += total_bytes;

            trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_trans), UVM_MEDIUM)

        // ============================================================
        // Step 4: Read back and verify data using BURST reads
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification (BURST mode) ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        // Read back each burst using the same burst pattern as write
        foreach (burst_queue[i]) begin
            bit [31:0] rd_start_addr;
            bit [7:0]  rd_len;
            int        rd_beats;

            rd_start_addr = burst_queue[i].start_addr;
            rd_len = burst_queue[i].len;
            rd_beats = burst_queue[i].beats;

            rd_trans = axi4_transaction::type_id::create("rd_trans");

            // Read with FIXED burst type
            if (!rd_trans.randomize() with {
                m_trans_type == READ;
                m_addr       == local::rd_start_addr;
                m_len        == local::rd_len;
                m_size       == local::m_size;
                m_burst      == FIXED;
            }) begin
                `uvm_error(get_type_name(), "Read transaction randomization failed")
                return;
            end

            start_item(rd_trans);
            finish_item(rd_trans);

            // Verify each beat - for FIXED burst, all reads return data from the same address
            for (int beat = 0; beat < rd_beats; beat++) begin
                bit [31:0] beat_addr;
                beat_addr = rd_start_addr;  // FIXED burst: all beats at same address

                // Get expected data (last written data to this address)
                expected_data = get_write_data(beat_addr);

                // Get actual read data from transaction
                if (rd_trans.m_wdata.size() > beat) begin
                    actual_data = rd_trans.m_wdata[beat];

                    // Compare data (only compare relevant bits based on data width)
                    if (actual_data[31:0] == expected_data[31:0]) begin
                        pass_count++;
                        `uvm_info(get_type_name(), $sformatf(
                            "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%08h",
                            i + 1, beat + 1, beat_addr, actual_data[31:0]), UVM_HIGH)
                    end else begin
                        fail_count++;
                        `uvm_error(get_type_name(), $sformatf(
                            "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h",
                            i + 1, beat + 1, beat_addr, expected_data[31:0], actual_data[31:0]))
                    end
                end else begin
                    fail_count++;
                    `uvm_error(get_type_name(), $sformatf(
                        "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h - No data returned",
                        i + 1, beat + 1, beat_addr))
                end
            end
        end

        // ============================================================
        // Summary - Verification results from sequence
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE bursts, %0d READ bursts",
            m_num_trans, burst_queue.size()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_burst_fixed_sequence

// Burst WRAP Test Sequence
// Sends multiple WRAP burst write transactions followed by read-back verification
// Parameters:
//   - LEN: random inside {2, 4, 8, 16} beats (m_len inside {1, 3, 7, 15})
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: WRAP
//   - Start address: aligned to transfer size
//   - Number of transactions: configurable (default 500)
class axi4_burst_wrap_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_burst_wrap_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (1, 3, 7, 15 for 2, 4, 8, 16 beats)
    rand bit [2:0]  m_size;          // Burst size encoding (fixed to 2)
    rand axi4_burst_t m_burst;       // Burst type (fixed to WRAP)

    // Write data storage for read-back verification
    // Map: address -> write data array (for burst transfers)
    protected bit [255:0] m_write_data_map[bit [31:0]];

    // Constraints
    constraint c_num_trans {
        m_num_trans inside {[1:10000]};
    }

    constraint c_len {
        // LEN inside {2, 4, 8, 16}, m_len = LEN - 1, so m_len inside {1, 3, 7, 15}
        m_len inside {1, 3, 7, 15};
    }

    constraint c_size {
        // SIZE = max_width, for 32-bit data width, size = 2 (4 bytes)
        m_size == 2;
    }

    constraint c_burst {
        m_burst == WRAP;
    }

    constraint c_addr_aligned {
        // Address must be aligned to transfer size (4 bytes)
        m_start_addr % (2 ** m_size) == 0;
    }

    // Constructor
    function new(string name = "axi4_burst_wrap_sequence");
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

        // Burst info storage for read-back verification
        typedef struct {
            bit [31:0] start_addr;
            bit [7:0]  len;
            int        beats;
        } burst_info_t;
        burst_info_t burst_queue[$];

        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;

        `uvm_info(get_type_name(), $sformatf(
            "Starting BURST WRAP test sequence: %0d transactions, LEN=random{2,4,8,16}, SIZE=%0d bytes, BURST=WRAP, ADDR=0x%08h",
            m_num_trans, 2 ** m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Randomize LEN for each transaction from {2, 4, 8, 16} beats
            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        inside {1, 3, 7, 15};  // 2, 4, 8, 16 beats
                m_size       == local::m_size;
                m_burst      == WRAP;
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            // Save transaction parameters BEFORE sending (wdata may be modified after finish_item)
            saved_len = wr_trans.m_len;
            beats_in_burst = saved_len + 1;
            bytes_per_beat = 2 ** m_size;
            total_bytes = beats_in_burst * bytes_per_beat;
            burst_start_addr = wr_trans.m_addr;  // Use transaction's address

            // Store write data for each beat in the burst BEFORE sending
            // For WRAP burst, address wraps within a boundary aligned to total_bytes
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                bit [31:0] beat_addr;
                bit [31:0] wrap_boundary;
                bit [255:0] beat_data;

                // WRAP burst: address wraps within the aligned boundary
                wrap_boundary = (burst_start_addr / total_bytes) * total_bytes;
                beat_addr = wrap_boundary + ((burst_start_addr - wrap_boundary + beat * bytes_per_beat) % total_bytes);

                if (wr_trans.m_wdata.size() > beat) begin
                    beat_data = wr_trans.m_wdata[beat];
                    store_write_data(beat_addr, beat_data);
                    `uvm_info(get_type_name(), $sformatf(
                        "Stored: beat=%0d, addr=0x%08h, data=0x%08h",
                        beat, beat_addr, beat_data[31:0]), UVM_HIGH)
                end
            end

            // Store burst info for burst read-back
            burst_queue.push_back('{start_addr: burst_start_addr, len: saved_len, beats: beats_in_burst});

            start_item(wr_trans);
            finish_item(wr_trans);

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, LEN=%0d beats, SIZE=%0d bytes",
                trans_count + 1, wr_trans.m_addr, beats_in_burst, bytes_per_beat), UVM_HIGH)

            // Update current address for next transaction
            current_addr += total_bytes;

            trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_trans), UVM_MEDIUM)

        // ============================================================
        // Step 4: Read back and verify data using BURST reads
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification (BURST mode) ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        // Read back each burst using the same burst pattern as write
        foreach (burst_queue[i]) begin
            bit [31:0] rd_start_addr;
            bit [7:0]  rd_len;
            int        rd_beats;

            rd_start_addr = burst_queue[i].start_addr;
            rd_len = burst_queue[i].len;
            rd_beats = burst_queue[i].beats;

            rd_trans = axi4_transaction::type_id::create("rd_trans");

            // Read with WRAP burst type
            if (!rd_trans.randomize() with {
                m_trans_type == READ;
                m_addr       == local::rd_start_addr;
                m_len        == local::rd_len;
                m_size       == local::m_size;
                m_burst      == WRAP;
            }) begin
                `uvm_error(get_type_name(), "Read transaction randomization failed")
                return;
            end

            start_item(rd_trans);
            finish_item(rd_trans);

            // Verify each beat - for WRAP burst, addresses wrap within the boundary
            for (int beat = 0; beat < rd_beats; beat++) begin
                bit [31:0] beat_addr;
                bit [31:0] wrap_boundary;

                // WRAP burst: address wraps within the aligned boundary
                wrap_boundary = (rd_start_addr / (rd_beats * bytes_per_beat)) * (rd_beats * bytes_per_beat);
                beat_addr = wrap_boundary + ((rd_start_addr - wrap_boundary + beat * bytes_per_beat) % (rd_beats * bytes_per_beat));

                // Get expected data
                expected_data = get_write_data(beat_addr);

                // Get actual read data from transaction
                if (rd_trans.m_wdata.size() > beat) begin
                    actual_data = rd_trans.m_wdata[beat];

                    // Compare data (only compare relevant bits based on data width)
                    if (actual_data[31:0] == expected_data[31:0]) begin
                        pass_count++;
                        `uvm_info(get_type_name(), $sformatf(
                            "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%08h",
                            i + 1, beat + 1, beat_addr, actual_data[31:0]), UVM_HIGH)
                    end else begin
                        fail_count++;
                        `uvm_error(get_type_name(), $sformatf(
                            "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h",
                            i + 1, beat + 1, beat_addr, expected_data[31:0], actual_data[31:0]))
                    end
                end else begin
                    fail_count++;
                    `uvm_error(get_type_name(), $sformatf(
                        "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h - No data returned",
                        i + 1, beat + 1, beat_addr))
                end
            end
        end

        // ============================================================
        // Summary - Verification results from sequence
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE bursts, %0d READ bursts",
            m_num_trans, burst_queue.size()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_burst_wrap_sequence

`endif // AXI4_SEQ_LIB_SV
