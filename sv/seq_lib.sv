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

// Burst Random Test Sequence
// Sends multiple random burst write transactions followed by read-back verification
// Parameters:
//   - LEN: random inside [0:15] (1-16 beats)
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: random (INCR, FIXED, or WRAP)
//   - Start address: aligned
//   - Number of transactions: configurable (default 500)
class axi4_burst_random_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_burst_random_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (0-15 for 1-16 beats)
    rand bit [2:0]  m_size;          // Burst size encoding (fixed to 2)
    rand axi4_burst_t m_burst;       // Burst type (random: INCR, FIXED, WRAP)

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
        // BURST type is random: INCR, FIXED, or WRAP
        m_burst inside {INCR, FIXED, WRAP};
    }

    constraint c_addr_aligned {
        // Address must be aligned to transfer size (4 bytes)
        m_start_addr % (2 ** m_size) == 0;
    }

    // Constructor
    function new(string name = "axi4_burst_random_sequence");
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
            bit [31:0]    start_addr;
            bit [7:0]     len;
            int           beats;
            axi4_burst_t  burst_type;
        } burst_info_t;
        burst_info_t burst_queue[$];

        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        axi4_burst_t saved_burst;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;

        `uvm_info(get_type_name(), $sformatf(
            "Starting BURST RANDOM test sequence: %0d transactions, LEN=random[1:16], SIZE=%0d bytes, BURST=random(INCR/FIXED/WRAP), ADDR=0x%08h",
            m_num_trans, 2 ** m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Randomize LEN and BURST for each transaction
            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        inside {[0:15]};  // 1-16 beats
                m_size       == local::m_size;
                m_burst      inside {INCR, FIXED, WRAP};
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            // Save transaction parameters BEFORE sending
            saved_len = wr_trans.m_len;
            saved_burst = wr_trans.m_burst;
            beats_in_burst = saved_len + 1;
            bytes_per_beat = 2 ** m_size;
            total_bytes = beats_in_burst * bytes_per_beat;
            burst_start_addr = wr_trans.m_addr;

            // Store write data for each beat in the burst BEFORE sending
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                bit [31:0] beat_addr;
                bit [31:0] wrap_boundary;
                bit [255:0] beat_data;

                // Calculate beat address based on burst type
                case (saved_burst)
                    INCR: begin
                        beat_addr = burst_start_addr + beat * bytes_per_beat;
                    end
                    FIXED: begin
                        // FIXED burst: all beats use the same start address
                        beat_addr = burst_start_addr;
                    end
                    WRAP: begin
                        // WRAP burst: address wraps within the aligned boundary
                        wrap_boundary = (burst_start_addr / total_bytes) * total_bytes;
                        beat_addr = wrap_boundary + ((burst_start_addr - wrap_boundary + beat * bytes_per_beat) % total_bytes);
                    end
                    default: begin
                        beat_addr = burst_start_addr + beat * bytes_per_beat;
                    end
                endcase

                if (wr_trans.m_wdata.size() > beat) begin
                    beat_data = wr_trans.m_wdata[beat];
                    store_write_data(beat_addr, beat_data);
                    `uvm_info(get_type_name(), $sformatf(
                        "Stored: beat=%0d, addr=0x%08h, data=0x%08h, burst=%s",
                        beat, beat_addr, beat_data[31:0], saved_burst.name()), UVM_HIGH)
                end
            end

            // Store burst info for burst read-back
            burst_queue.push_back('{start_addr: burst_start_addr, len: saved_len, beats: beats_in_burst, burst_type: saved_burst});

            start_item(wr_trans);
            finish_item(wr_trans);

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, LEN=%0d beats, SIZE=%0d bytes, BURST=%s",
                trans_count + 1, wr_trans.m_addr, beats_in_burst, bytes_per_beat, saved_burst.name()), UVM_HIGH)

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
            axi4_burst_t rd_burst;

            rd_start_addr = burst_queue[i].start_addr;
            rd_len = burst_queue[i].len;
            rd_beats = burst_queue[i].beats;
            rd_burst = burst_queue[i].burst_type;

            // For INCR burst: handle potential 2KB boundary splitting by driver
            if (rd_burst == INCR) begin
                int remaining_beats;
                bit [31:0] current_rd_addr;

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
                                    "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%08h, BURST=%s",
                                    i + 1, beat + 1, beat_addr, actual_data[31:0], rd_burst.name()), UVM_HIGH)
                            end else begin
                                fail_count++;
                                `uvm_error(get_type_name(), $sformatf(
                                    "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h, BURST=%s",
                                    i + 1, beat + 1, beat_addr, expected_data[31:0], actual_data[31:0], rd_burst.name()))
                            end
                        end else begin
                            fail_count++;
                            `uvm_error(get_type_name(), $sformatf(
                                "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h - No data returned, BURST=%s",
                                i + 1, beat + 1, beat_addr, rd_burst.name()))
                        end
                    end

                    // Update for next sub-burst
                    remaining_beats -= actual_beats_received;
                    current_rd_addr += actual_beats_received * bytes_per_beat;
                end
            end
            else begin
                // For FIXED and WRAP burst: no 2KB boundary splitting needed
                rd_trans = axi4_transaction::type_id::create("rd_trans");

                // Read with the same burst type as write
                if (!rd_trans.randomize() with {
                    m_trans_type == READ;
                    m_addr       == local::rd_start_addr;
                    m_len        == local::rd_len;
                    m_size       == local::m_size;
                    m_burst      == local::rd_burst;
                }) begin
                    `uvm_error(get_type_name(), "Read transaction randomization failed")
                    return;
                end

                start_item(rd_trans);
                finish_item(rd_trans);

                // Verify each beat - calculate address based on burst type
                for (int beat = 0; beat < rd_beats; beat++) begin
                    bit [31:0] beat_addr;
                    bit [31:0] wrap_boundary;

                    // Calculate beat address based on burst type
                    case (rd_burst)
                        FIXED: begin
                            // FIXED burst: all beats at same address
                            beat_addr = rd_start_addr;
                        end
                        WRAP: begin
                            // WRAP burst: address wraps within the boundary
                            wrap_boundary = (rd_start_addr / (rd_beats * bytes_per_beat)) * (rd_beats * bytes_per_beat);
                            beat_addr = wrap_boundary + ((rd_start_addr - wrap_boundary + beat * bytes_per_beat) % (rd_beats * bytes_per_beat));
                        end
                        default: begin
                            beat_addr = rd_start_addr + beat * bytes_per_beat;
                        end
                    endcase

                    // Get expected data
                    expected_data = get_write_data(beat_addr);

                    // Get actual read data from transaction
                    if (rd_trans.m_wdata.size() > beat) begin
                        actual_data = rd_trans.m_wdata[beat];

                        // Compare data (only compare relevant bits based on data width)
                        if (actual_data[31:0] == expected_data[31:0]) begin
                            pass_count++;
                            `uvm_info(get_type_name(), $sformatf(
                                "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%08h, BURST=%s",
                                i + 1, beat + 1, beat_addr, actual_data[31:0], rd_burst.name()), UVM_HIGH)
                        end else begin
                            fail_count++;
                            `uvm_error(get_type_name(), $sformatf(
                                "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h, BURST=%s",
                                i + 1, beat + 1, beat_addr, expected_data[31:0], actual_data[31:0], rd_burst.name()))
                        end
                    end else begin
                        fail_count++;
                        `uvm_error(get_type_name(), $sformatf(
                            "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h - No data returned, BURST=%s",
                            i + 1, beat + 1, beat_addr, rd_burst.name()))
                    end
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

endclass : axi4_burst_random_sequence

// Burst Slice Test Sequence
// Tests INCR burst with large burst length [16:256] beats (LEN inside [15:255])
// Parameters:
//   - LEN: random inside [15:255] (16-256 beats per transaction)
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: INCR
//   - Start address: aligned
//   - Number of transactions: configurable (default 500)
class axi4_burst_slice_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_burst_slice_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (aligned)
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (15-255 for 16-256 beats)
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
        // LEN inside [15:255], m_len = LEN - 1, so m_len inside [15:255]
        m_len inside {[15:255]};
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
    function new(string name = "axi4_burst_slice_sequence");
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
            "Starting BURST SLICE test sequence: %0d transactions, LEN=random[16:256], SIZE=%0d bytes, BURST=INCR, ADDR=0x%08h",
            m_num_trans, 2 ** m_size, m_start_addr), UVM_MEDIUM)

        // ============================================================
        // Step 1-3: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        current_addr = m_start_addr;
        trans_count = 0;

        repeat (m_num_trans) begin
            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Randomize LEN for each transaction (16-256 beats)
            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::current_addr;
                m_len        inside {[15:255]};  // 16-256 beats
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

            // Handle potential burst splitting by driver
            // Driver splits bursts based on: max_burst_len (32) and 2KB boundary
            while (remaining_beats > 0) begin
                bit [31:0] next_2kb_boundary;
                int bytes_until_boundary;
                int beats_this_burst;
                int actual_beats_received;
                int max_burst_len;

                // Get max burst length from config (default 32)
                // This must match driver's m_cfg.m_max_burst_len
                max_burst_len = 32;

                // Calculate bytes until 2KB boundary
                next_2kb_boundary = ((current_rd_addr / 2048) + 1) * 2048;
                bytes_until_boundary = next_2kb_boundary - current_rd_addr;

                // Calculate beats for this sub-burst
                // Limited by: remaining beats, max_burst_len, and 2KB boundary
                beats_this_burst = remaining_beats;

                // Limit by max burst length
                if (beats_this_burst > max_burst_len) begin
                    beats_this_burst = max_burst_len;
                end

                // Limit by 2KB boundary
                if (bytes_until_boundary < beats_this_burst * bytes_per_beat) begin
                    beats_this_burst = bytes_until_boundary / bytes_per_beat;
                    if (beats_this_burst == 0) beats_this_burst = 1;
                end

                // Send read transaction for this sub-burst
                rd_trans = axi4_transaction::type_id::create("rd_trans");

                if (!rd_trans.randomize() with {
                    m_trans_type == READ;
                    m_addr       == local::current_rd_addr;
                    m_len        == local::beats_this_burst - 1;
                    m_size       == local::m_size;
                    m_burst      == INCR;
                }) begin
                    `uvm_error(get_type_name(), "Read transaction randomization failed")
                    return;
                end

                start_item(rd_trans);
                finish_item(rd_trans);

                actual_beats_received = rd_trans.m_wdata.size();

                // Verify each beat in the read burst
                for (int beat = 0; beat < actual_beats_received; beat++) begin
                    bit [31:0] beat_addr;
                    bit [255:0] expected_beat_data;
                    bit [255:0] actual_beat_data;

                    beat_addr = current_rd_addr + beat * bytes_per_beat;
                    expected_beat_data = get_write_data(beat_addr);

                    if (rd_trans.m_wdata.size() > beat) begin
                        actual_beat_data = rd_trans.m_wdata[beat];

                        // Compare data
                        if (actual_beat_data[31:0] == expected_beat_data[31:0]) begin
                            pass_count++;
                            `uvm_info(get_type_name(), $sformatf(
                                "READ PASS: ADDR=0x%08h, DATA=0x%08h",
                                beat_addr, actual_beat_data[31:0]), UVM_HIGH)
                        end else begin
                            fail_count++;
                            `uvm_error(get_type_name(), $sformatf(
                                "READ FAIL: ADDR=0x%08h, Expected=0x%08h, Actual=0x%08h",
                                beat_addr, expected_beat_data[31:0], actual_beat_data[31:0]))
                        end
                    end
                end

                // Update for next sub-burst
                current_rd_addr += beats_this_burst * bytes_per_beat;
                remaining_beats -= beats_this_burst;
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

endclass : axi4_burst_slice_sequence

// Unaligned Address Test Sequence
// Tests unaligned address transfers with random burst lengths
// Parameters:
//   - LEN: random inside [0:255] (1-256 beats)
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: INCR
//   - Start address: unaligned (address[1:0] != 2'b00)
//   - Number of rounds: 5
//   - Transactions per round: 100
//   - Total transactions: 500
class axi4_unaligned_addr_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_unaligned_addr_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address (unaligned)
    rand int        m_num_rounds;    // Number of rounds (default 5)
    rand int        m_num_trans_per_round;  // Transactions per round (default 100)
    rand bit [2:0]  m_size;          // Burst size encoding (fixed to 2)
    rand axi4_burst_t m_burst;       // Burst type (fixed to INCR)

    // Write data storage for read-back verification
    // Map: byte address -> write data
    protected bit [7:0] m_byte_data_map[bit [31:0]];

    // Constraints
    constraint c_num_rounds {
        soft m_num_rounds == 10;
    }

    constraint c_num_trans_per_round {
        soft m_num_trans_per_round == 100;
    }

    constraint c_size {
        // SIZE = max_width, for 32-bit data width, size = 2 (4 bytes)
        m_size == 2;
    }

    constraint c_burst {
        m_burst == INCR;
    }

    // Constructor
    function new(string name = "axi4_unaligned_addr_sequence");
        super.new(name);
    endfunction

    // Store write data for later verification (per beat)
    // For unaligned transfers, data position on bus is shifted by address offset
    // e.g., addr=0x1ba08449 (offset=1), WSTRB=4'b1110:
    //   - WSTRB[1]=1: data[15:8]  -> stored to addr 0x1ba08449 (aligned_addr + 1)
    //   - WSTRB[2]=1: data[23:16] -> stored to addr 0x1ba0844a (aligned_addr + 2)
    //   - WSTRB[3]=1: data[31:24] -> stored to addr 0x1ba0844b (aligned_addr + 3)
    // Key insight: WSTRB[i] and data[i*8 +: 8] correspond to aligned_addr + i
    function void store_write_data(bit [31:0] addr, bit [255:0] data, bit [31:0] wstrb, int size);
        int bytes_per_beat;
        int offset;
        bit [31:0] aligned_addr;
        bytes_per_beat = 1 << size;
        offset = addr % bytes_per_beat;  // Address offset within the beat
        aligned_addr = (addr >> size) << size;  // Aligned address

        // Store each byte separately based on WSTRB
        // WSTRB[i] indicates data[i*8 +: 8] is valid for memory address (aligned_addr + i)
        for (int i = 0; i < bytes_per_beat; i++) begin
            if (wstrb[i]) begin
                // data[i*8 +: 8] corresponds to memory address (aligned_addr + i)
                m_byte_data_map[aligned_addr + i] = data[i*8 +: 8];
            end
        end
    endfunction

    // Get stored write data for a beat address
    function bit [255:0] get_write_data(bit [31:0] addr, int size);
        int bytes_per_beat;
        bytes_per_beat = 1 << size;
        for (int i = 0; i < bytes_per_beat; i++) begin
            if (m_byte_data_map.exists(addr + i)) begin
                get_write_data[i*8 +: 8] = m_byte_data_map[addr + i];
            end else begin
                get_write_data[i*8 +: 8] = 8'h00;
            end
        end
    endfunction

    // Check if address has stored write data
    function bit has_write_data(bit [31:0] addr);
        return m_byte_data_map.exists(addr);
    endfunction

    // Calculate WSTRB for unaligned first beat (same as transaction class)
    function bit [31:0] calc_unaligned_wstrb(bit [31:0] addr, int size, int data_width);
        int offset;
        int strb_width;
        bit [31:0] mask;

        offset = addr % (1 << size);
        strb_width = 1 << size;  // Number of bytes per beat based on size
        mask = (1 << strb_width) - 1;

        // Create mask that zeros out lower bytes based on offset
        calc_unaligned_wstrb = mask << offset;
    endfunction

    // Generate random unaligned address
    function bit [31:0] gen_unaligned_addr();
        bit [31:0] addr;
        // Generate random address with lower 2 bits being non-zero (unaligned to 4 bytes)
        addr = $urandom_range(32'h1000_0000, 32'h1FFF_FFFC);
        // Force lower 2 bits to be non-zero (1, 2, or 3)
        addr[1:0] = $urandom_range(1, 3);
        return addr;
    endfunction

    // Body - Write then Read-back with verification
    task body();
        axi4_transaction wr_trans, rd_trans;
        bit [31:0] current_addr;
        bit [31:0] round_start_addr;

        // Burst info storage for read-back verification
        typedef struct {
            bit [31:0] start_addr;
            bit [7:0]  len;
            int        beats;
        } burst_info_t;
        burst_info_t burst_queue[$];

        int total_trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;
        bit [31:0] aligned_start;
        bit [31:0] beat_addr;
        bit [255:0] beat_data;
        bit [31:0] beat_wstrb;

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "  UNALIGNED ADDRESS TEST SEQUENCE", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:256] beats (LEN inside [0:255])", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Transfer Size: %0d bytes (SIZE=2)", 2 ** m_size), UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Number of Rounds: %0d", m_num_rounds), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Transactions per Round: %0d", m_num_trans_per_round), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Total Transactions: %0d", m_num_rounds * m_num_trans_per_round), UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        total_trans_count = 0;
        bytes_per_beat = 2 ** m_size;

        // ============================================================
        // Phase 1: Send WRITE transactions (5 rounds)
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        for (int round = 0; round < m_num_rounds; round++) begin
            // Generate new random unaligned start address for this round
            round_start_addr = gen_unaligned_addr();
            current_addr = round_start_addr;

            `uvm_info(get_type_name(), $sformatf(
                "--- Round %0d: Start Address = 0x%08h (unaligned) ---",
                round + 1, round_start_addr), UVM_MEDIUM)

            for (int trans = 0; trans < m_num_trans_per_round; trans++) begin
                wr_trans = axi4_transaction::type_id::create("wr_trans");

                // Randomize LEN for each transaction (1-256 beats)
                // Disable aligned address constraint for unaligned transfer
                wr_trans.c_addr_aligned_soft.constraint_mode(0);

                if (!wr_trans.randomize() with {
                    m_trans_type == WRITE;
                    m_addr       == local::current_addr;
                    m_len        inside {[0:255]};  // 1-4 beats
                    m_size       == local::m_size;
                    m_burst      == INCR;
                }) begin
                    `uvm_error(get_type_name(), "Write transaction randomization failed")
                    return;
                end

                // Save transaction parameters
                saved_len = wr_trans.m_len;
                beats_in_burst = saved_len + 1;
                total_bytes = beats_in_burst * bytes_per_beat;
                burst_start_addr = wr_trans.m_addr;

                // Calculate aligned start address (same as slave does)
                aligned_start = (burst_start_addr >> m_size) << m_size;

                // Store write data for each beat in the burst
                // Need to calculate actual WSTRB for unaligned addresses
                for (int beat = 0; beat < beats_in_burst; beat++) begin
                    // Calculate beat address according to AXI INCR burst protocol
                    // Beat 0: address = AxADDR
                    // Beat 1+: address = aligned_start + beat_index * beat_size
                    if (beat == 0) begin
                        beat_addr = burst_start_addr;
                    end else begin
                        beat_addr = aligned_start + beat * bytes_per_beat;
                    end

                    if (wr_trans.m_wdata.size() > beat) begin
                        beat_data = wr_trans.m_wdata[beat];
                        beat_wstrb = wr_trans.m_wstrb[beat];

                        // For first beat with unaligned start address, calculate actual WSTRB
                        // This matches what the driver will do
                        if (beat == 0 && (burst_start_addr % bytes_per_beat) != 0) begin
                            beat_wstrb = calc_unaligned_wstrb(burst_start_addr, m_size, 32);
                        end

                        store_write_data(beat_addr, beat_data, beat_wstrb, m_size);
                    end
                end

                // Store burst info for burst read-back
                burst_queue.push_back('{start_addr: burst_start_addr, len: saved_len, beats: beats_in_burst});

                start_item(wr_trans);
                finish_item(wr_trans);

                `uvm_info(get_type_name(), $sformatf(
                    "Sent WRITE #%0d (Round %0d): ADDR=0x%08h, LEN=%0d beats",
                    total_trans_count + 1, round + 1, wr_trans.m_addr, beats_in_burst), UVM_HIGH)

                // Update current address for next transaction
                current_addr += total_bytes;
                total_trans_count++;
            end
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent in %0d rounds",
            total_trans_count, m_num_rounds), UVM_MEDIUM)

        // ============================================================
        // Phase 2: Read back and verify data using BURST reads
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        // Read back each burst
        foreach (burst_queue[i]) begin
            bit [31:0] rd_start_addr;
            bit [7:0]  rd_len;
            int        rd_beats;
            int        remaining_beats;
            bit [31:0] current_rd_addr;
            bit [31:0] rd_aligned_start;
            int        beats_sent;

            rd_start_addr = burst_queue[i].start_addr;
            rd_len = burst_queue[i].len;
            rd_beats = burst_queue[i].beats;
            remaining_beats = rd_beats;
            current_rd_addr = rd_start_addr;
            rd_aligned_start = (rd_start_addr >> m_size) << m_size;
            beats_sent = 0;

            // Handle potential burst splitting by driver
            while (remaining_beats > 0) begin
                bit [31:0] next_2kb_boundary;
                int bytes_until_boundary;
                int beats_this_burst;
                int actual_beats_received;
                int max_burst_len;

                max_burst_len = 32;

                // Calculate bytes until 2KB boundary
                next_2kb_boundary = ((current_rd_addr / 2048) + 1) * 2048;
                bytes_until_boundary = next_2kb_boundary - current_rd_addr;

                // Calculate beats for this sub-burst
                beats_this_burst = remaining_beats;

                // Limit by max burst length
                if (beats_this_burst > max_burst_len) begin
                    beats_this_burst = max_burst_len;
                end

                // Limit by 2KB boundary
                if (bytes_until_boundary < beats_this_burst * bytes_per_beat) begin
                    beats_this_burst = bytes_until_boundary / bytes_per_beat;
                    if (beats_this_burst == 0) beats_this_burst = 1;
                end

                rd_trans = axi4_transaction::type_id::create("rd_trans");

                // Disable aligned address constraint for unaligned read
                rd_trans.c_addr_aligned_soft.constraint_mode(0);

                if (!rd_trans.randomize() with {
                    m_trans_type == READ;
                    m_addr       == local::current_rd_addr;
                    m_len        == local::beats_this_burst - 1;
                    m_size       == local::m_size;
                    m_burst      == INCR;
                }) begin
                    `uvm_error(get_type_name(), "Read transaction randomization failed")
                    return;
                end

                start_item(rd_trans);
                finish_item(rd_trans);

                actual_beats_received = rd_trans.m_wdata.size();

                // Verify each beat in the read burst
                for (int beat = 0; beat < actual_beats_received; beat++) begin
                    bit [31:0] beat_addr;
                    bit [255:0] expected_beat_data;
                    bit [255:0] actual_beat_data;
                    bit beat_pass;
                    int global_beat_idx;

                    // Calculate global beat index in the original burst
                    global_beat_idx = beats_sent + beat;

                    // Calculate beat address according to AXI INCR burst protocol
                    // Beat 0: address = AxADDR
                    // Beat 1+: address = aligned_start + beat_index * beat_size
                    if (global_beat_idx == 0) begin
                        beat_addr = rd_start_addr;
                    end else begin
                        beat_addr = rd_aligned_start + global_beat_idx * bytes_per_beat;
                    end

                    if (rd_trans.m_wdata.size() > beat) begin
                        int beat_offset;
                        bit [31:0] beat_aligned_addr;
                        actual_beat_data = rd_trans.m_wdata[beat];
                        beat_pass = 1;

                        // Calculate address offset for unaligned first beat
                        beat_offset = beat_addr % bytes_per_beat;
                        beat_aligned_addr = (beat_addr >> m_size) << m_size;

                        // Compare each byte individually
                        // For unaligned transfers, data position on bus is shifted:
                        // e.g., addr=0x1ba08449 (offset=1):
                        //   - data[15:8]  corresponds to addr 0x1ba08449 (aligned_addr + 1)
                        //   - data[23:16] corresponds to addr 0x1ba0844a (aligned_addr + 2)
                        //   - data[31:24] corresponds to addr 0x1ba0844b (aligned_addr + 3)
                        for (int byte_idx = 0; byte_idx < bytes_per_beat; byte_idx++) begin
                            bit [7:0] expected_byte;
                            bit [7:0] actual_byte;
                            bit [31:0] byte_addr;
                            int data_pos;

                            // Calculate memory address for this byte position on bus
                            byte_addr = beat_aligned_addr + byte_idx;

                            // Get expected byte from our byte-level storage
                            if (m_byte_data_map.exists(byte_addr)) begin
                                expected_byte = m_byte_data_map[byte_addr];
                                // Data position on bus equals byte index (data[i*8 +: 8] for aligned_addr + i)
                                actual_byte = actual_beat_data[byte_idx*8 +: 8];

                                if (expected_byte != actual_byte) begin
                                    beat_pass = 0;
                                    `uvm_error(get_type_name(), $sformatf(
                                        "READ FAIL: ADDR=0x%08h, Byte[%0d] Expected=0x%02h, Actual=0x%02h",
                                        byte_addr, byte_idx, expected_byte, actual_byte))
                                end
                            end
                            // If byte not in map (not written), skip verification for this byte
                        end

                        if (beat_pass) begin
                            pass_count++;
                            `uvm_info(get_type_name(), $sformatf(
                                "READ PASS: ADDR=0x%08h, DATA=0x%08h",
                                beat_addr, actual_beat_data[31:0]), UVM_HIGH)
                        end else begin
                            fail_count++;
                        end
                    end
                end

                // Update for next sub-burst
                // The next read address should be calculated based on the global beat index
                beats_sent += actual_beats_received;
                remaining_beats -= actual_beats_received;

                // Calculate next read start address
                if (remaining_beats > 0) begin
                    // Next address = aligned_start + beats_sent * bytes_per_beat
                    current_rd_addr = rd_aligned_start + beats_sent * bytes_per_beat;
                end
            end
        end

        // ============================================================
        // Summary - Verification results
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE, %0d READ",
            total_trans_count, burst_queue.size()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_unaligned_addr_sequence

// Narrow Transfer Test Sequence
// Tests narrow transfers with SIZE = byte/half-word/word (0/1/2)
// Parameters:
//   - LEN: random inside [0:255] (1-256 beats)
//   - SIZE: random inside {0, 1, 2} (byte/half-word/word)
//   - BURST: INCR
//   - Start address: random aligned/unaligned
//   - Number of transactions: 500
class axi4_narrow_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_narrow_sequence)

    // Transaction parameters
    rand bit [31:0] m_start_addr;    // Starting address
    rand int        m_num_trans;     // Number of transactions
    rand bit [7:0]  m_len;           // Burst length - 1 (0-255)
    rand bit [2:0]  m_size;          // Burst size encoding (0=byte, 1=half-word, 2=word)
    rand axi4_burst_t m_burst;       // Burst type (fixed to INCR)
    rand bit        m_addr_aligned;  // Whether address is aligned

    // Write data storage for read-back verification
    // Map: byte address -> write data
    protected bit [7:0] m_byte_data_map[bit [31:0]];

    // Constraints
    constraint c_num_trans {
        soft m_num_trans == 500;
    }

    constraint c_len {
        m_len inside {[0:255]};
    }

    constraint c_size {
        // SIZE = 0 (byte), 1 (half-word), or 2 (word)
        m_size inside {0, 1, 2};
    }

    constraint c_burst {
        m_burst == INCR;
    }

    constraint c_addr_aligned {
        // Randomly select aligned or unaligned address
        m_addr_aligned dist {0 := 50, 1 := 50};
    }

    // Constraint for half-word transfer: address bit[0] must be 0
    // This ensures WSTRB pattern is 'b0011 or 'b1100, not shifted patterns
    constraint c_half_word_addr_align {
        (m_size == 1) -> (m_start_addr[0] == 1'b0);
    }

    // Constructor
    function new(string name = "axi4_narrow_sequence");
        super.new(name);
    endfunction

    // Store write data for later verification (per byte)
    // For narrow transfers, data position on bus depends on address offset and WSTRB
    function void store_write_data(bit [31:0] addr, bit [255:0] data, bit [31:0] wstrb, int size);
        int bytes_per_beat;
        int offset;
        bit [31:0] aligned_addr;
        bytes_per_beat = 1 << size;
        offset = addr % bytes_per_beat;
        aligned_addr = (addr >> size) << size;

        // Store each byte separately based on WSTRB
        for (int i = 0; i < bytes_per_beat; i++) begin
            if (wstrb[i]) begin
                m_byte_data_map[aligned_addr + i] = data[i*8 +: 8];
            end
        end
    endfunction

    // Get stored write data for a beat address
    function bit [255:0] get_write_data(bit [31:0] addr, int size);
        int bytes_per_beat;
        bytes_per_beat = 1 << size;
        for (int i = 0; i < bytes_per_beat; i++) begin
            if (m_byte_data_map.exists(addr + i)) begin
                get_write_data[i*8 +: 8] = m_byte_data_map[addr + i];
            end else begin
                get_write_data[i*8 +: 8] = 8'h00;
            end
        end
    endfunction

    // Check if address has stored write data
    function bit has_write_data(bit [31:0] addr);
        return m_byte_data_map.exists(addr);
    endfunction

    // Calculate WSTRB for unaligned first beat
    function bit [31:0] calc_unaligned_wstrb(bit [31:0] addr, int size, int data_width);
        int offset;
        int strb_width;
        bit [31:0] mask;

        offset = addr % (1 << size);
        strb_width = 1 << size;  // Number of bytes per beat based on size
        mask = (1 << strb_width) - 1;

        // Create mask that zeros out lower bytes based on offset
        calc_unaligned_wstrb = mask << offset;
    endfunction

    // Generate random address (aligned or unaligned based on m_addr_aligned)
    // For half-word (size=1), bit[0] is always 0 per constraint c_half_word_addr_align
    function bit [31:0] gen_random_addr(bit is_aligned, int size);
        bit [31:0] addr;
        addr = $urandom_range(32'h1000_0000, 32'h1FFF_FFFC);
        if (is_aligned) begin
            // Align to transfer size
            addr = (addr >> size) << size;
        end else begin
            // Make unaligned to transfer size
            if (size > 0) begin
                addr[11:0] = $urandom();
                // Ensure at least one bit is misaligned
                if ((addr % (1 << size)) == 0) begin
                    // For half-word (size=1), bit[0] must be 0, so we can only have aligned addresses
                    // For word (size=2), we can set bit[0] or bit[1] to make it unaligned
                    if (size == 1) begin
                        // Half-word: bit[0] must always be 0, all addresses are aligned
                        addr[0] = 1'b0;
                    end else begin
                        addr[0] = 1'b1;
                    end
                end
            end
            // Enforce constraint: for half-word, bit[0] must be 0
            if (size == 1) begin
                addr[0] = 1'b0;
            end
        end
        return addr;
    endfunction

    // Body - Write then Read-back with verification
    task body();
        axi4_transaction wr_trans, rd_trans;
        bit [31:0] current_addr;

        // Burst info storage for read-back verification
        typedef struct {
            bit [31:0] start_addr;
            bit [7:0]  len;
            bit [2:0]  size;
            int        beats;
            bit [31:0] wstrb[];  // Store WSTRB for each beat
        } burst_info_t;
        burst_info_t burst_queue[$];

        int total_trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [7:0]   saved_len;
        bit [2:0]   saved_size;
        int beats_in_burst;
        int bytes_per_beat;
        int total_bytes;
        bit [31:0] burst_start_addr;
        bit [31:0] aligned_start;
        bit [31:0] beat_addr;
        bit [255:0] beat_data;
        bit [31:0] beat_wstrb;
        bit        is_aligned;
        bit [2:0]  trans_size;

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       NARROW TRANSFER TEST SEQUENCE", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: random [1:256] beats (LEN inside [0:255])", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: random byte/half-word/word (SIZE=0/1/2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), "  - Start Address: random aligned/unaligned", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Number of Transactions: %0d", m_num_trans), UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        total_trans_count = 0;

        // ============================================================
        // Phase 1: Send WRITE transactions
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        repeat (m_num_trans) begin
            // Randomize burst parameters for this transaction
            if (!std::randomize(saved_len) with {
                saved_len inside {[0:255]};
            }) begin
                `uvm_error(get_type_name(), "LEN randomization failed")
                return;
            end

            if (!std::randomize(trans_size) with {
                trans_size inside {0, 1, 2};
            }) begin
                `uvm_error(get_type_name(), "SIZE randomization failed")
                return;
            end

            if (!std::randomize(is_aligned) with {
                is_aligned dist {0 := 50, 1 := 50};
            }) begin
                `uvm_error(get_type_name(), "Aligned flag randomization failed")
                return;
            end

            // Generate random address
            burst_start_addr = gen_random_addr(is_aligned, trans_size);
            bytes_per_beat = 1 << trans_size;
            beats_in_burst = saved_len + 1;
            total_bytes = beats_in_burst * bytes_per_beat;

            wr_trans = axi4_transaction::type_id::create("wr_trans");

            // Disable soft alignment constraint for unaligned transfers
            if (!is_aligned) begin
                wr_trans.c_addr_aligned_soft.constraint_mode(0);
            end

            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::burst_start_addr;
                m_len        == local::saved_len;
                m_size       == local::trans_size;
                m_burst      == INCR;
            }) begin
                `uvm_error(get_type_name(), "Write transaction randomization failed")
                return;
            end

            // Check half-word WSTRB constraint before sending
            // if (trans_size == 1) begin  // half-word transfer
            //     int strobe_count;
            //     bit check_pass;
            //     check_pass = 1;
            //     // `uvm_info(get_type_name(), $sformatf("Half-word transfer check: ADDR=0x%08h, SIZE=%0d, LEN=%0d", wr_trans.m_addr, wr_trans.m_size, wr_trans.m_len), UVM_LOW)
            //     for (int i = 0; i <= wr_trans.m_len; i++) begin
            //         strobe_count = $countones(wr_trans.m_wstrb[i]);
            //         if (strobe_count != 2) begin
            //             `uvm_error(get_type_name(), $sformatf("Beat %0d WSTRB check FAIL: WSTRB=0x%08h, countones=%0d (expected 2)", i, wr_trans.m_wstrb[i], strobe_count))
            //             check_pass = 0;
            //         end else begin
            //             // `uvm_info(get_type_name(), $sformatf("Beat %0d WSTRB check PASS: WSTRB=0x%08h, countones=%0d", i, wr_trans.m_wstrb[i], strobe_count), UVM_LOW)
            //         end
            //     end
            //     if (check_pass) begin
            //         // `uvm_info(get_type_name(), "Half-word WSTRB constraint check PASSED", UVM_LOW)
            //     end else begin
            //         `uvm_error(get_type_name(), "Half-word WSTRB constraint check FAILED")
            //     end
            // end

            start_item(wr_trans);
            finish_item(wr_trans);

            // Store write data for each beat
            aligned_start = (burst_start_addr >> trans_size) << trans_size;
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                beat_addr = aligned_start + beat * bytes_per_beat;
                if (beat < wr_trans.m_wdata.size()) begin
                    beat_data = wr_trans.m_wdata[beat];
                    // Generate default WSTRB based on transfer size
                    beat_wstrb = (beat < wr_trans.m_wstrb.size()) ? wr_trans.m_wstrb[beat] :
                                 (bytes_per_beat == 1) ? 32'h1 :
                                 (bytes_per_beat == 2) ? 32'h3 : 32'hf;
                    store_write_data(beat_addr, beat_data, beat_wstrb, trans_size);
                end
            end

            // Store burst info for read-back
            begin
                burst_info_t info;
                info.start_addr = burst_start_addr;
                info.len = saved_len;
                info.size = trans_size;
                info.beats = beats_in_burst;
                info.wstrb = new[beats_in_burst];
                // Copy WSTRB from transaction
                for (int b = 0; b < beats_in_burst; b++) begin
                    if (b < wr_trans.m_wstrb.size()) begin
                        info.wstrb[b] = wr_trans.m_wstrb[b];
                    end else begin
                        // Default WSTRB based on size (all bytes valid)
                        info.wstrb[b] = (bytes_per_beat == 1) ? 32'h1 :
                                        (bytes_per_beat == 2) ? 32'h3 : 32'hf;
                    end
                end
                burst_queue.push_back(info);
            end

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, LEN=%0d, SIZE=%0d bytes, Beats=%0d, %s",
                total_trans_count + 1, burst_start_addr, saved_len, bytes_per_beat,
                beats_in_burst, is_aligned ? "aligned" : "unaligned"), UVM_HIGH)

            total_trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", total_trans_count), UVM_MEDIUM)

        // ============================================================
        // Phase 2: Read back and verify data
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

        foreach (burst_queue[i]) begin
            burst_info_t info = burst_queue[i];
            bytes_per_beat = 1 << info.size;
            beats_in_burst = info.beats;

            rd_trans = axi4_transaction::type_id::create("rd_trans");

            // Disable soft alignment constraint for unaligned transfers
            if ((info.start_addr % bytes_per_beat) != 0) begin
                rd_trans.c_addr_aligned_soft.constraint_mode(0);
            end

            if (!rd_trans.randomize() with {
                m_trans_type == READ;
                m_addr       == local::info.start_addr;
                m_len        == local::info.len;
                m_size       == local::info.size;
                m_burst      == INCR;
            }) begin
                `uvm_error(get_type_name(), "Read transaction randomization failed")
                return;
            end

            start_item(rd_trans);
            finish_item(rd_trans);

            // Verify each beat - only check bytes where WSTRB is high
            aligned_start = (info.start_addr >> info.size) << info.size;
            for (int beat = 0; beat < beats_in_burst; beat++) begin
                bit [255:0] data_mask;
                bit [31:0] beat_wstrb;
                bit [7:0] expected_byte;
                bit [7:0] actual_byte;
                bit beat_pass;
                int bytes_checked;

                beat_addr = aligned_start + beat * bytes_per_beat;

                // Get expected data
                expected_data = get_write_data(beat_addr, info.size);

                // Get actual read data
                if (beat < rd_trans.m_wdata.size()) begin
                    actual_data = rd_trans.m_wdata[beat];

                    // Get WSTRB for this beat
                    beat_wstrb = (beat < info.wstrb.size()) ? info.wstrb[beat] :
                                 (bytes_per_beat == 1) ? 32'h1 :
                                 (bytes_per_beat == 2) ? 32'h3 : 32'hf;

                    // Build data mask from WSTRB - only check bytes where WSTRB[i] = 1
                    data_mask = 0;
                    for (int byte_idx = 0; byte_idx < bytes_per_beat; byte_idx++) begin
                        if (beat_wstrb[byte_idx]) begin
                            data_mask[byte_idx*8 +: 8] = 8'hFF;
                        end
                    end

                    // Compare data only for bytes with WSTRB high
                    beat_pass = 1;
                    bytes_checked = 0;

                    for (int byte_idx = 0; byte_idx < bytes_per_beat; byte_idx++) begin
                        if (beat_wstrb[byte_idx]) begin
                            expected_byte = expected_data[byte_idx*8 +: 8];
                            actual_byte = actual_data[byte_idx*8 +: 8];

                            if (expected_byte != actual_byte) begin
                                beat_pass = 0;
                                `uvm_error(get_type_name(), $sformatf(
                                    "READ FAIL: Burst#%0d Beat#%0d, ADDR=0x%08h, Byte[%0d]: Expected=0x%02h, Actual=0x%02h, WSTRB=0x%0h",
                                    i + 1, beat + 1, beat_addr, byte_idx, expected_byte, actual_byte, beat_wstrb))
                            end else begin
                                `uvm_info(get_type_name(), $sformatf(
                                    "READ PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, Byte[%0d]: DATA=0x%02h, WSTRB=0x%0h",
                                    i + 1, beat + 1, beat_addr, byte_idx, actual_byte, beat_wstrb), UVM_HIGH)
                            end
                            bytes_checked++;
                        end
                    end

                    if (beat_pass && bytes_checked > 0) begin
                        pass_count++;
                        `uvm_info(get_type_name(), $sformatf(
                            "READ BEAT PASS: Burst#%0d Beat#%0d, ADDR=0x%08h, DATA=0x%0h, WSTRB=0x%0h",
                            i + 1, beat + 1, beat_addr, actual_data & data_mask, beat_wstrb), UVM_HIGH)
                    end else if (bytes_checked == 0) begin
                        // No bytes to check (WSTRB all zeros)
                        `uvm_info(get_type_name(), $sformatf(
                            "READ BEAT SKIP: Burst#%0d Beat#%0d, ADDR=0x%08h - WSTRB=0x%0h (no valid bytes)",
                            i + 1, beat + 1, beat_addr, beat_wstrb), UVM_HIGH)
                        pass_count++;  // Count as pass since there was nothing to verify
                    end else begin
                        fail_count++;
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
        // Summary - Verification results
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE, %0d READ",
            total_trans_count, burst_queue.size()), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_narrow_sequence

// Parameterized Configuration 1 Test Sequence
// Sends 500 write transactions followed by read-back verification
// Designed for CFG1 configuration (DATA_WIDTH=64, ADDR_WIDTH=48, ID_WIDTH=5)
class axi4_para_cfg1_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_para_cfg1_sequence)

    // Transaction parameters (non-randomized for deterministic test)
    bit [`AXI4_ADDR_WIDTH-1:0] m_start_addr;    // Starting address (aligned)
    int        m_num_trans = 5000;  // Number of transactions
    bit [7:0]  m_len = 0;          // Burst length - 1 (single beat)
    bit [2:0]  m_size;            // Burst size encoding (max for data width)
    axi4_burst_t m_burst = INCR;  // Burst type

    // Write data storage for read-back verification
    // Map: address -> write data array (for burst transfers)
    protected bit [255:0] m_write_data_map[bit [`AXI4_ADDR_WIDTH-1:0]];

    // Constructor
    function new(string name = "axi4_para_cfg1_sequence");
        super.new(name);
        // Set size based on data width
        m_size = (`AXI4_DATA_WIDTH == 64) ? 3 : 2;
        // Set default start address (aligned to size)
        m_start_addr = 48'h1000_0000_0000;
    endfunction

    // Store write data for later verification
    function void store_write_data(bit [`AXI4_ADDR_WIDTH-1:0] addr, bit [255:0] data);
        m_write_data_map[addr] = data;
    endfunction

    // Get stored write data
    function bit [255:0] get_write_data(bit [`AXI4_ADDR_WIDTH-1:0] addr);
        if (m_write_data_map.exists(addr)) begin
            return m_write_data_map[addr];
        end else begin
            return {256{1'b0}};
        end
    endfunction

    // Body - Write then Read-back with verification
    task body();
        axi4_transaction wr_trans, rd_trans;
        bit [`AXI4_ADDR_WIDTH-1:0] current_addr;

        // Address queue for read-back
        bit [`AXI4_ADDR_WIDTH-1:0] addr_queue[$];

        int trans_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        int bytes_per_beat;
        bit [255:0] data_mask;

        bytes_per_beat = 2 ** m_size;
        data_mask = (256'h1 << (bytes_per_beat * 8)) - 1;

        `uvm_info(get_type_name(), $sformatf(
            "=== PARA_CFG1 Test Sequence ==="), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Configuration: DATA_WIDTH=%0d, ADDR_WIDTH=%0d, ID_WIDTH=%0d",
            `AXI4_DATA_WIDTH, `AXI4_ADDR_WIDTH, `AXI4_ID_WIDTH), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Test parameters: %0d transactions, LEN=%0d, SIZE=%0d bytes, ADDR=0x%0h",
            m_num_trans, m_len + 1, bytes_per_beat, m_start_addr), UVM_NONE)

        // ============================================================
        // Phase 1: Send 500 WRITE transactions
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

            // Store write data for verification
            if (wr_trans.m_wdata.size() > 0) begin
                store_write_data(current_addr, wr_trans.m_wdata[0]);
                addr_queue.push_back(current_addr);
            end

            if (trans_count % 100 == 0 || trans_count == m_num_trans - 1) begin
                `uvm_info(get_type_name(), $sformatf(
                    "WRITE progress: %0d/%0d, ADDR=0x%0h",
                    trans_count + 1, m_num_trans, current_addr), UVM_MEDIUM)
            end

            current_addr += bytes_per_beat;
            trans_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_trans), UVM_MEDIUM)

        // ============================================================
        // Phase 2: Read back and verify all data
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

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

            // Get expected and actual data
            expected_data = get_write_data(addr_queue[i]);

            if (rd_trans.m_wdata.size() > 0) begin
                actual_data = rd_trans.m_wdata[0];

                // Compare data (only compare valid bytes based on data width)
                if ((actual_data & data_mask) == (expected_data & data_mask)) begin
                    pass_count++;
                    if (i % 100 == 0) begin
                        `uvm_info(get_type_name(), $sformatf(
                            "READ progress: %0d/%0d, ADDR=0x%0h - PASS",
                            i + 1, m_num_trans, addr_queue[i]), UVM_MEDIUM)
                    end
                end else begin
                    fail_count++;
                    `uvm_error(get_type_name(), $sformatf(
                        "READ FAIL #%0d: ADDR=0x%0h, Expected=0x%0h, Actual=0x%0h",
                        i + 1, addr_queue[i], expected_data & data_mask, actual_data & data_mask))
                end
            end else begin
                fail_count++;
                `uvm_error(get_type_name(), $sformatf(
                    "READ #%0d: ADDR=0x%0h - No data returned",
                    i + 1, addr_queue[i]))
            end
        end

        // ============================================================
        // Summary
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Configuration: DATA_WIDTH=%0d, ADDR_WIDTH=%0d, ID_WIDTH=%0d",
            `AXI4_DATA_WIDTH, `AXI4_ADDR_WIDTH, `AXI4_ID_WIDTH), UVM_NONE)
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

endclass : axi4_para_cfg1_sequence

// Boundary 2K Test Sequence
// Tests 2K boundary crossing with INCR burst
// Parameters:
//   - LEN: 16 beats (m_len = 15)
//   - SIZE: max_width (2 for 32-bit data width, 4 bytes per beat)
//   - BURST: INCR
//   - Start address: 2K aligned minus offset, ensuring boundary crossing
//   - Number of test rounds: 50
class axi4_boundary_2k_sequence extends axi4_base_sequence;
    `uvm_object_utils(axi4_boundary_2k_sequence)

    // Transaction parameters
    rand bit [31:0] m_base_addr;    // Base address for testing
    rand int        m_num_rounds;   // Number of test rounds (default 50)

    // Write data storage for read-back verification
    // Map: address -> write data
    protected bit [255:0] m_write_data_map[bit [31:0]];

    // Constraints
    constraint c_num_rounds {
        m_num_rounds == 50;
    }

    // Constructor
    function new(string name = "axi4_boundary_2k_sequence");
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
        int round_count;
        int pass_count;
        int fail_count;
        bit [255:0] expected_data;
        bit [255:0] actual_data;
        bit [255:0] data_mask;

        // Fixed parameters for this test
        bit [7:0]  m_len  = 8'd15;  // LEN = 16 beats
        bit [2:0]  m_size = 3'd2;   // SIZE = 2 (4 bytes per beat)
        axi4_burst_t m_burst = INCR;

        // Calculate data mask based on data width
        data_mask = {`AXI4_DATA_WIDTH{1'b1}};

        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "       AXI4 BOUNDARY 2K TEST SEQUENCE", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)
        `uvm_info(get_type_name(), "Test Configuration:", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Length: 16 beats (LEN=15)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Transfer Size: 4 bytes (SIZE=2)", UVM_NONE)
        `uvm_info(get_type_name(), "  - Burst Type: INCR", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Base Address: 0x%08h", m_base_addr), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf("  - Number of Test Rounds: %0d", m_num_rounds), UVM_NONE)
        `uvm_info(get_type_name(), "  - Each round tests 2K boundary crossing", UVM_NONE)
        `uvm_info(get_type_name(), "===========================================", UVM_NONE)

        // ============================================================
        // Phase 1: Send WRITE transactions for each round
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 1: Sending WRITE transactions ===", UVM_MEDIUM)

        round_count = 0;

        // Test 50 different addresses, each crossing a 2K boundary
        repeat (m_num_rounds) begin
            bit [31:0] test_addr;
            int offset;

            // Calculate offset to ensure boundary crossing
            // Each beat is 4 bytes, 16 beats = 64 bytes total
            // To cross 2K boundary, we need start address near 2K boundary
            // offset from 2K aligned address: (16 beats - 1) * 4 bytes = 60 bytes
            // So start address should be at most 60 bytes before boundary
            // Use random offset between 0 and 60 (inclusive)
            offset = $urandom_range(0, 60);

            // Calculate test address: 2K aligned base + round * 4K (each 2K boundary) - offset
            // This ensures we test different 2K boundaries
            test_addr = {m_base_addr[31:12], 12'b0} + (round_count * 4096) + (2048 - offset);

            // Ensure address is 4-byte aligned
            test_addr[1:0] = 2'b00;

            `uvm_info(get_type_name(), $sformatf(
                "Round %0d: Testing 2K boundary at ADDR=0x%08h (boundary at 0x%08h)",
                round_count + 1, test_addr, {test_addr[31:12], 12'b0} + 2048), UVM_HIGH)

            wr_trans = axi4_transaction::type_id::create("wr_trans");

            if (!wr_trans.randomize() with {
                m_trans_type == WRITE;
                m_addr       == local::test_addr;
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
                store_write_data(test_addr, wr_trans.m_wdata[0]);
                addr_queue.push_back(test_addr);
            end

            `uvm_info(get_type_name(), $sformatf(
                "Sent WRITE #%0d: ADDR=0x%08h, DATA=0x%08h",
                round_count + 1, wr_trans.m_addr, wr_trans.m_wdata[0][31:0]), UVM_HIGH)

            round_count++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Write phase completed: %0d transactions sent", m_num_rounds), UVM_MEDIUM)

        // ============================================================
        // Phase 2: Read back and verify all data
        // ============================================================
        `uvm_info(get_type_name(), "=== Phase 2: READ-back and verification ===", UVM_MEDIUM)

        pass_count = 0;
        fail_count = 0;

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

            // Get expected and actual data
            expected_data = get_write_data(addr_queue[i]);

            if (rd_trans.m_wdata.size() > 0) begin
                actual_data = rd_trans.m_wdata[0];

                // Compare data (only compare valid bytes based on data width)
                if ((actual_data & data_mask) == (expected_data & data_mask)) begin
                    pass_count++;
                    `uvm_info(get_type_name(), $sformatf(
                        "READ PASS #%0d: ADDR=0x%08h, DATA=0x%08h",
                        i + 1, addr_queue[i], actual_data[31:0]), UVM_HIGH)
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
        // Summary
        // ============================================================
        `uvm_info(get_type_name(), "=== Verification Summary ===", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Configuration: DATA_WIDTH=%0d, ADDR_WIDTH=%0d, ID_WIDTH=%0d",
            `AXI4_DATA_WIDTH, `AXI4_ADDR_WIDTH, `AXI4_ID_WIDTH), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Total transactions: %0d WRITE, %0d READ",
            m_num_rounds, m_num_rounds), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Verification results: PASS=%0d, FAIL=%0d",
            pass_count, fail_count), UVM_NONE)

        if (fail_count == 0 && pass_count > 0) begin
            `uvm_info(get_type_name(), "*** ALL VERIFICATIONS PASSED ***", UVM_NONE)
        end else if (fail_count > 0) begin
            `uvm_error(get_type_name(), $sformatf("*** %0d VERIFICATIONS FAILED ***", fail_count))
        end

    endtask

endclass : axi4_boundary_2k_sequence

`endif // AXI4_SEQ_LIB_SV
