// AXI4 Transaction Class
// Extends uvm_sequence_item with constraints for burst types

`ifndef AXI4_TRANSACTION_SV
`define AXI4_TRANSACTION_SV

class axi4_transaction extends uvm_sequence_item;
    `uvm_object_utils(axi4_transaction)

    // Transaction type
    rand axi4_trans_t m_trans_type;

    // Address channel signals
    rand bit [`AXI4_ADDR_WIDTH-1:0] m_addr;
    rand bit [`AXI4_ID_WIDTH-1:0]   m_id;
    rand bit [7:0]  m_len;      // Burst length - 1 (0-255)
    rand bit [2:0]  m_size;     // Burst size (1, 2, 4, 8, 16, 32, 64, 128 bytes)
    rand axi4_burst_t m_burst;
    rand bit        m_lock;
    rand bit [3:0]  m_cache;
    rand axi4_prot_t m_prot;
    rand bit [3:0]  m_qos;
    rand bit [3:0]  m_region;
    rand bit [15:0] m_user;

    // Write data channel signals
    rand bit [255:0] m_wdata[];
    rand bit [31:0]  m_wstrb[];

    // Response signals
    rand axi4_resp_t m_resp;

    // Configuration parameters (non-randomized, using macros)
    int m_data_width = `AXI4_DATA_WIDTH;
    int m_addr_width = `AXI4_ADDR_WIDTH;
    int m_id_width = `AXI4_ID_WIDTH;

    // Constraints for burst length based on burst type
    constraint c_len_fixed {
        (m_burst == FIXED) -> (m_len <= 15);
    }

    constraint c_len_wrap {
        (m_burst == WRAP) -> (m_len inside {1, 3, 7, 15});
    }

    constraint c_len_incr {
        (m_burst == INCR) -> (m_len <= 255);
    }

    // Constraint for valid burst encoding (not reserved)
    constraint c_burst_valid {
        m_burst != RESV;
    }

    // Constraint for burst size not exceeding data width
    constraint c_size_valid {
        (2 ** m_size) <= (m_data_width / 8);
        m_size <= 5; // Max 128 bytes per beat
    }

    // Constraint for aligned address for WRAP burst
    constraint c_wrap_addr_aligned {
        (m_burst == WRAP) -> (m_addr % (2 ** m_size) == 0);
    }

    // Constraint for data array size matching burst length
    constraint c_data_array_size {
        m_wdata.size() == m_len + 1;
        m_wstrb.size() == m_len + 1;
    }

    // Constraint for WSTRB - removed, will be calculated in post_randomize
    // WSTRB is now properly calculated based on address offset, size, and burst type
    // to support narrow transfers and unaligned accesses per AXI4 protocol

    // Constraint for address alignment with size
    // Note: This is soft constraint, can be disabled for unaligned transfers
    constraint c_addr_aligned_soft {
        soft m_addr % (2 ** m_size) == 0;
    }

    // Constraint for ID width
    constraint c_id_width {
        m_id < (1 << m_id_width);
    }

    // Constraint for half_word (2-byte) transfer WSTRB
    // WSTRB must have exactly 2 contiguous bits set to 1 (either 'b0011 or 'b1100 for 32-bit bus)
    // For wider buses, the pattern can be shifted based on address offset
    constraint c_half_word_wstrb {
        (m_size == 1 && m_trans_type == WRITE) -> {
            foreach (m_wstrb[i]) $countones(m_wstrb[i]) == 2;
        }
    }

    // Constraint to disable cache, lock, prot signals for current test scenarios
    constraint c_disable_cache_lock_prot {
        m_lock  == 1'b0;
        m_cache == 4'b0000;
        m_prot.privilege == 1'b0;
        m_prot.secure    == 1'b0;
        m_prot.data      == 1'b0;
    }

    // Function to calculate WSTRB for unaligned first beat
    function bit [31:0] calc_unaligned_wstrb(bit [31:0] addr, int size, int data_width);
        int offset;
        int strb_width;
        bit [31:0] mask;

        offset = addr % (1 << size);
        strb_width = data_width / 8;
        mask = (1 << strb_width) - 1;

        // Create mask that zeros out lower bytes based on offset
        calc_unaligned_wstrb = mask << offset;
    endfunction

    // Function to check if transfer is unaligned
    function bit is_unaligned();
        return (m_addr % (2 ** m_size)) != 0;
    endfunction

    // Function to get number of beats
    function int get_beat_count();
        return m_len + 1;
    endfunction

    // Function to get transfer size in bytes
    function int get_transfer_size_bytes();
        return (m_len + 1) * (2 ** m_size);
    endfunction

    // Function to check if address crosses 2KB boundary
    // For INCR burst, a transfer must not cross a 4KB boundary per AXI4 spec
    // This function checks for 2KB boundary crossing as required by specific use cases
    // 2KB = 2048 bytes = 2^11, so boundary is at every address where [10:0] == 0
    // We check bits [31:11] to determine 2KB region
    function bit crosses_2kb_boundary();
        bit [31:0] start_addr;
        bit [31:0] end_addr;
        bit [31:0] transfer_size;

        start_addr = m_addr;
        transfer_size = get_transfer_size_bytes();
        end_addr = start_addr + transfer_size - 1;

        // Check if start and end addresses are in different 2KB regions
        // 2KB = 2048 bytes, boundary at address[10:0] == 0
        // Crossing occurs when bits [31:11] of start and end are different
        if (start_addr[31:11] != end_addr[31:11]) begin
            return 1;
        end

        return 0;
    endfunction

    // Post-randomize function to calculate WSTRB per AXI4 protocol
    // For narrow transfers and unaligned accesses, WSTRB indicates valid byte lanes
    // Data is shifted to correct byte lane position based on address offset
    //
    // AXI4 Protocol Rules for WSTRB:
    // 1. WSTRB bits must be contiguous (no gaps between set bits)
    // 2. Number of set bits = transfer size (bytes_per_beat)
    // 3. For unaligned first beat, WSTRB is shifted by address offset
    // 4. For narrow transfers, WSTRB width = bytes_per_beat (not data bus width)
    function void post_randomize();
        localparam int STRB_W = 32;  // Max strobe width (256-bit data / 8 = 32 bytes)
        int bytes_per_beat;
        int byte_offset;
        int valid_bytes;
        bit [31:0] addr;

        super.post_randomize();

        // Only calculate WSTRB for WRITE transactions
        if (m_trans_type != WRITE) return;

        bytes_per_beat = 1 << m_size;
        addr = m_addr;

        for (int i = 0; i <= m_len; i++) begin
            // Calculate byte offset within the data bus for this beat
            // For narrow transfers, this determines where data appears on the bus
            byte_offset = int'(addr) % (m_data_width / 8);

            // For all beats, valid_bytes equals bytes_per_beat
            // WSTRB width is always equal to transfer size (narrow transfer support)
            valid_bytes = bytes_per_beat;

            // Calculate WSTRB: create mask for valid_bytes and shift to byte_offset position
            // This ensures WSTRB has exactly bytes_per_beat contiguous bits set
            m_wstrb[i] = ((1 << valid_bytes) - 1) << byte_offset;

            // Shift data to correct byte lane position
            // Data is initially in lower bytes, shift it to match WSTRB position
            m_wdata[i] = (m_wdata[i] & ((256'h1 << (valid_bytes * 8)) - 1)) << (byte_offset * 8);

            // Update address for next beat based on burst type
            if (m_burst == INCR) begin
                addr += bytes_per_beat;
            end
            // For FIXED burst, address stays the same
        end
    endfunction

    // Function to calculate address for WRAP burst
    function bit [31:0] calc_wrap_addr(int beat_index);
        bit [31:0] aligned_addr;
        bit [31:0] wrap_boundary;
        int wrap_size;

        aligned_addr = (m_addr >> m_size) << m_size;
        wrap_size = (m_len + 1) * (2 ** m_size);
        wrap_boundary = (aligned_addr / wrap_size) * wrap_size;

        calc_wrap_addr = wrap_boundary + ((m_addr + beat_index * (2 ** m_size)) % wrap_size);
    endfunction

    // Constructor
    function new(string name = "axi4_transaction");
        super.new(name);
    endfunction

    // Convert to string for debugging
    function string convert2string();
        string s;
        s = $sformatf("AXI4 Transaction:\n");
        s = {s, $sformatf("  Type: %s\n", m_trans_type.name())};
        s = {s, $sformatf("  ID: %0d\n", m_id)};
        s = {s, $sformatf("  Address: 0x%08h\n", m_addr)};
        s = {s, $sformatf("  Length: %0d beats\n", m_len + 1)};
        s = {s, $sformatf("  Size: %0d bytes\n", 2 ** m_size)};
        s = {s, $sformatf("  Burst: %s\n", m_burst.name())};
        s = {s, $sformatf("  Total bytes: %0d\n", get_transfer_size_bytes())};
        return s;
    endfunction

    // Do copy
    function void do_copy(uvm_object rhs);
        axi4_transaction rhs_tr;

        if (!$cast(rhs_tr, rhs)) begin
            `uvm_error(get_type_name(), "Cast failed in do_copy")
            return;
        end

        super.do_copy(rhs);

        m_trans_type = rhs_tr.m_trans_type;
        m_addr       = rhs_tr.m_addr;
        m_id         = rhs_tr.m_id;
        m_len        = rhs_tr.m_len;
        m_size       = rhs_tr.m_size;
        m_burst      = rhs_tr.m_burst;
        m_lock       = rhs_tr.m_lock;
        m_cache      = rhs_tr.m_cache;
        m_prot       = rhs_tr.m_prot;
        m_qos        = rhs_tr.m_qos;
        m_region     = rhs_tr.m_region;
        m_user       = rhs_tr.m_user;
        m_resp       = rhs_tr.m_resp;
        m_data_width = rhs_tr.m_data_width;
        m_addr_width = rhs_tr.m_addr_width;
        m_id_width   = rhs_tr.m_id_width;

        m_wdata = rhs_tr.m_wdata;
        m_wstrb = rhs_tr.m_wstrb;
    endfunction

    // Do compare
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_transaction rhs_tr;

        if (!$cast(rhs_tr, rhs)) begin
            `uvm_error(get_type_name(), "Cast failed in do_compare")
            return 0;
        end

        do_compare = super.do_compare(rhs, comparer);

        do_compare &= (m_trans_type === rhs_tr.m_trans_type);
        do_compare &= (m_addr       === rhs_tr.m_addr);
        do_compare &= (m_id         === rhs_tr.m_id);
        do_compare &= (m_len        === rhs_tr.m_len);
        do_compare &= (m_size       === rhs_tr.m_size);
        do_compare &= (m_burst      === rhs_tr.m_burst);
        do_compare &= (m_resp       === rhs_tr.m_resp);
    endfunction

    // Do print
    function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string("Trans Type", m_trans_type.name());
        printer.print_field("ID", m_id, 4);
        printer.print_field("Address", m_addr, 32);
        printer.print_field("Length", m_len, 8);
        printer.print_field("Size", m_size, 3);
        printer.print_string("Burst", m_burst.name());
        printer.print_string("Response", m_resp.name());
    endfunction

    // Do record
    function void do_record(uvm_recorder recorder);
        super.do_record(recorder);
        recorder.record_string("trans_type", m_trans_type.name());
        recorder.record_field("id", m_id, 4);
        recorder.record_field("addr", m_addr, 32);
        recorder.record_field("len", m_len, 8);
        recorder.record_field("size", m_size, 3);
        recorder.record_string("burst", m_burst.name());
    endfunction

endclass : axi4_transaction

`endif // AXI4_TRANSACTION_SV