// AXI4 VIP Testbench Top Module
// Demonstrates how to use the AXI4 VIP

`timescale 1ns/1ps
`include "uvm_macros.svh"

// Import packages first
import uvm_pkg::*;
import axi4_pkg::*;

// Then include test library
`include "test_lib.sv"

module axi4_tb_top;

    // Import AXI4 package
    import axi4_pkg::*;
    import uvm_pkg::*;

    // Parameters
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 32;
    parameter int ID_WIDTH = 4;

    // Clock and reset
    logic ACLK;
    logic ARESETn;

    // Clock generation - 100MHz
    initial begin
        ACLK = 0;
        forever #5 ACLK = ~ACLK;
    end

    // Reset generation
    initial begin
        ARESETn = 0;
        repeat(10) @(posedge ACLK);
        ARESETn = 1;
    end

    // AXI4 Interface instance
    axi4_interface #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) axi4_vif (
        .ACLK(ACLK),
        .ARESETn(ARESETn)
    );

    //-------------------------------------------------------------------------
    // Simple Slave Model with Memory (based on ai_cc_opus_axi4_vip reference)
    //-------------------------------------------------------------------------
    // Memory model: associative array indexed by byte address
    logic [7:0] mem [logic [ADDR_WIDTH-1:0]];

    // Write channel state - support outstanding transactions
    typedef struct {
        logic [ID_WIDTH-1:0]   id;
        logic [ADDR_WIDTH-1:0] addr;
        logic [ADDR_WIDTH-1:0] aligned_start;
        logic [7:0]            len;
        logic [2:0]            size;
        logic [1:0]            burst;
        logic [7:0]            beat_cnt;
    } aw_info_t;

    aw_info_t aw_queue[$];
    aw_info_t current_aw;
    logic     aw_active;

    // AW channel: always ready
    assign axi4_vif.awready = 1'b1;

    // W channel: ready signal always high
    assign axi4_vif.wready = 1'b1;

    // B channel
    logic                s_bvalid;
    logic [ID_WIDTH-1:0] s_bid;
    logic [1:0]          s_bresp;

    assign axi4_vif.bvalid = s_bvalid;
    assign axi4_vif.bid    = s_bid;
    assign axi4_vif.bresp  = s_bresp;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            s_bvalid     <= 0;
            s_bid        <= '0;
            s_bresp      <= 2'b00;
            aw_queue     = {};
            current_aw   = '{default: '0};
            aw_active    = 0;
        end else begin
            // Capture AW channel and push to queue
            if (axi4_vif.awvalid && axi4_vif.awready) begin
                aw_info_t aw_info;
                aw_info.id           = axi4_vif.awid;
                aw_info.addr         = axi4_vif.awaddr;
                aw_info.len          = axi4_vif.awlen;
                aw_info.size         = axi4_vif.awsize;
                aw_info.burst        = axi4_vif.awburst;
                aw_info.beat_cnt     = 0;
                aw_info.aligned_start = (aw_info.addr >> aw_info.size) << aw_info.size;
                aw_queue.push_back(aw_info);
            end

            // Process W channel
            if (axi4_vif.wvalid && axi4_vif.wready) begin
                logic [ADDR_WIDTH-1:0] wr_addr;

                // Get new transaction from queue if no active transaction
                if (!aw_active) begin
                    if (aw_queue.size() > 0) begin
                        current_aw = aw_queue.pop_front();
                        aw_active = 1;
                    end
                end

                // Only process W data if we have an active AW
                if (aw_active) begin
                    // Calculate address for current beat
                    if (current_aw.beat_cnt == 0) begin
                        wr_addr = current_aw.addr;
                    end else if (current_aw.burst == 2'b01) begin  // INCR
                        wr_addr = current_aw.aligned_start + current_aw.beat_cnt * (1 << current_aw.size);
                    end else if (current_aw.burst == 2'b10) begin  // WRAP
                        logic [ADDR_WIDTH-1:0] wrap_boundary;
                        int wrap_size;
                        wrap_size = (current_aw.len + 1) * (1 << current_aw.size);
                        wrap_boundary = (current_aw.addr / wrap_size) * wrap_size;
                        wr_addr = wrap_boundary + ((current_aw.addr - wrap_boundary + current_aw.beat_cnt * (1 << current_aw.size)) % wrap_size);
                    end else begin  // FIXED
                        wr_addr = current_aw.addr;
                    end

                    // Write to memory: only write bytes indicated by size
                    begin
                        int bytes_per_beat;
                        bytes_per_beat = 1 << current_aw.size;
                        for (int i = 0; i < bytes_per_beat; i++) begin
                            if (axi4_vif.wstrb[i])
                                mem[wr_addr + i] = axi4_vif.wdata[i*8 +: 8];
                        end
                    end

                    if (axi4_vif.wlast) begin
                        s_bvalid  <= 1;
                        s_bid     <= current_aw.id;
                        s_bresp   <= 2'b00;
                        aw_active = 0;
                    end else begin
                        current_aw.beat_cnt = current_aw.beat_cnt + 1;
                    end
                end
            end

            if (s_bvalid && axi4_vif.bready)
                s_bvalid <= 0;
        end
    end

    // AR channel: always ready
    assign axi4_vif.arready = 1'b1;

    // R channel: read from memory
    logic                  s_rvalid;
    logic [ID_WIDTH-1:0]   s_rid;
    logic [DATA_WIDTH-1:0] s_rdata;
    logic [1:0]            s_rresp;
    logic                  s_rlast;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [ADDR_WIDTH-1:0] rd_start_addr;      // Start address for wrap calculation
    logic [ADDR_WIDTH-1:0] rd_aligned_start;
    logic [7:0]            rd_len;
    logic [2:0]            rd_size;
    logic [1:0]            rd_burst;
    logic [7:0]            rd_beat_cnt;

    assign axi4_vif.rvalid = s_rvalid;
    assign axi4_vif.rid    = s_rid;
    assign axi4_vif.rdata  = s_rdata;
    assign axi4_vif.rresp  = s_rresp;
    assign axi4_vif.rlast  = s_rlast;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            s_rvalid    <= 0;
            s_rid       <= '0;
            s_rdata     <= '0;
            s_rresp     <= 2'b00;
            s_rlast     <= 0;
            rd_addr         <= '0;
            rd_start_addr   <= '0;
            rd_aligned_start <= '0;
            rd_len      <= '0;
            rd_size     <= '0;
            rd_burst    <= '0;
            rd_beat_cnt <= '0;
        end else begin
            if (axi4_vif.arvalid && axi4_vif.arready && !s_rvalid) begin
                // Capture AR channel and start read response
                logic [ADDR_WIDTH-1:0] first_addr;
                first_addr       = axi4_vif.araddr;
                rd_addr          <= first_addr;
                rd_start_addr    <= first_addr;  // Save start address for wrap calculation
                rd_aligned_start <= (first_addr >> axi4_vif.arsize) << axi4_vif.arsize;
                rd_len      <= axi4_vif.arlen;
                rd_size     <= axi4_vif.arsize;
                rd_burst    <= axi4_vif.arburst;
                rd_beat_cnt <= 0;
                s_rvalid    <= 1;
                s_rid       <= axi4_vif.arid;
                s_rresp     <= 2'b00;
                s_rlast     <= (axi4_vif.arlen == 0);

                // Read first beat from memory
                begin
                    int bytes_per_beat;
                    bytes_per_beat = 1 << axi4_vif.arsize;
                    for (int i = 0; i < bytes_per_beat; i++)
                        s_rdata[i*8 +: 8] <= mem.exists(first_addr + i) ? mem[first_addr + i] : 8'h00;
                    for (int i = bytes_per_beat; i < DATA_WIDTH/8; i++)
                        s_rdata[i*8 +: 8] <= 8'h00;
                end
            end else if (s_rvalid && axi4_vif.rready) begin
                if (s_rlast) begin
                    s_rvalid <= 0;
                    s_rlast  <= 0;
                end else begin
                    logic [ADDR_WIDTH-1:0] next_addr;

                    rd_beat_cnt <= rd_beat_cnt + 1;
                    s_rlast     <= (rd_beat_cnt + 1 >= rd_len);

                    // Calculate next address based on burst type
                    if (rd_burst == 2'b01) begin  // INCR
                        next_addr = rd_aligned_start + (rd_beat_cnt + 1) * (1 << rd_size);
                    end else if (rd_burst == 2'b10) begin  // WRAP
                        logic [ADDR_WIDTH-1:0] wrap_boundary;
                        int wrap_size;
                        wrap_size = (rd_len + 1) * (1 << rd_size);
                        wrap_boundary = (rd_start_addr / wrap_size) * wrap_size;  // Use start address
                        next_addr = wrap_boundary + ((rd_start_addr - wrap_boundary + (rd_beat_cnt + 1) * (1 << rd_size)) % wrap_size);
                    end else begin  // FIXED
                        next_addr = rd_addr;
                    end
                    rd_addr <= next_addr;

                    // Read next beat from memory
                    begin
                        int bytes_per_beat;
                        bytes_per_beat = 1 << rd_size;
                        for (int i = 0; i < bytes_per_beat; i++)
                            s_rdata[i*8 +: 8] <= mem.exists(next_addr + i) ? mem[next_addr + i] : 8'h00;
                        for (int i = bytes_per_beat; i < DATA_WIDTH/8; i++)
                            s_rdata[i*8 +: 8] <= 8'h00;
                    end
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Waveform dump
    //-------------------------------------------------------------------------
    initial begin
        string fsdb_file;
        if (!$value$plusargs("FSDB_FILE=%s", fsdb_file))
            fsdb_file = "sim";
        $fsdbDumpfile({fsdb_file, ".fsdb"});
        $fsdbDumpvars(0, axi4_tb_top);
    end

    // UVM initial block
    initial begin
        // Pass virtual interface to test
        uvm_config_db#(virtual axi4_interface #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH))::set(
            null, "uvm_test_top", "m_vif", axi4_vif);

        // Run burst_incr_test by default
        run_test("axi4_burst_incr_test");
    end

    // Timeout
    initial begin
        #500000000;  // 500us timeout for large number of transactions
        `uvm_error("TB_TOP", "Simulation timeout reached")
        $finish;
    end

endmodule : axi4_tb_top
