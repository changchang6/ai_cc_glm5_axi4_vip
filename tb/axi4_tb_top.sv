// AXI4 VIP Testbench Top Module
// Demonstrates how to use the AXI4 VIP

`timescale 1ns/1ps
`include "uvm_macros.svh"

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

    // DUT placeholder - in real testbench, connect DUT here
    // For now, we create a simple slave responder
    axi4_slave_responder #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) u_slave_responder (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .axi4_if(axi4_vif)
    );

    // Configuration
    axi4_config m_cfg;

    // UVM initial block
    initial begin
        // Create configuration
        m_cfg = axi4_config::type_id::create("m_cfg");
        m_cfg.m_data_width = DATA_WIDTH;
        m_cfg.m_addr_width = ADDR_WIDTH;
        m_cfg.m_id_width = ID_WIDTH;
        m_cfg.m_max_outstanding = 8;
        m_cfg.m_trans_interval = 0;
        m_cfg.m_support_data_before_addr = 0;
        m_cfg.m_wtimeout = 1000;
        m_cfg.m_rtimeout = 1000;
        m_cfg.m_clock_freq_mhz = 100.0;
        m_cfg.m_is_active = 1;
        m_cfg.m_has_coverage = 1;
        m_cfg.m_enable_burst_split = 1;
        m_cfg.m_vif = axi4_vif;

        // Set configuration
        uvm_config_db#(axi4_config)::set(null, "uvm_test_top", "m_cfg", m_cfg);

        // Run test
        run_test("axi4_base_test");
    end

    // Timeout
    initial begin
        #100000;
        `uvm_error("TB_TOP", "Simulation timeout reached")
        $finish;
    end

endmodule : axi4_tb_top

// Simple AXI4 Slave Responder
// Responds to transactions with OKAY response
module axi4_slave_responder #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4
)(
    input logic ACLK,
    input logic ARESETn,
    axi4_interface axi4_if
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // Write address channel
    logic [ID_WIDTH-1:0]   awid_reg;
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [7:0]            awlen_reg;
    logic [2:0]            awsize_reg;
    logic [1:0]            awburst_reg;
    logic                  awvalid_reg;

    // Read address channel
    logic [ID_WIDTH-1:0]   arid_reg;
    logic [ADDR_WIDTH-1:0] araddr_reg;
    logic [7:0]            arlen_reg;
    logic [2:0]            arsize_reg;
    logic [1:0]            arburst_reg;
    logic                  arvalid_reg;

    // Write data tracking
    int wr_beat_count;
    int rd_beat_count;

    // Memory model (simple)
    logic [7:0] memory [logic [ADDR_WIDTH-1:0]];

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            // Reset write address channel
            axi4_if.AWREADY <= 0;
            awid_reg <= 0;
            awaddr_reg <= 0;
            awlen_reg <= 0;
            awsize_reg <= 0;
            awburst_reg <= 0;
            awvalid_reg <= 0;

            // Reset write data channel
            axi4_if.WREADY <= 0;

            // Reset write response channel
            axi4_if.BID <= 0;
            axi4_if.BRESP <= 0;
            axi4_if.BVALID <= 0;

            // Reset read address channel
            axi4_if.ARREADY <= 0;
            arid_reg <= 0;
            araddr_reg <= 0;
            arlen_reg <= 0;
            arsize_reg <= 0;
            arburst_reg <= 0;
            arvalid_reg <= 0;

            // Reset read data channel
            axi4_if.RID <= 0;
            axi4_if.RDATA <= 0;
            axi4_if.RRESP <= 0;
            axi4_if.RLAST <= 0;
            axi4_if.RVALID <= 0;

            wr_beat_count <= 0;
            rd_beat_count <= 0;
        end else begin
            // Write address channel handling
            if (axi4_if.AWVALID && axi4_if.AWREADY) begin
                awid_reg <= axi4_if.AWID;
                awaddr_reg <= axi4_if.AWADDR;
                awlen_reg <= axi4_if.AWLEN;
                awsize_reg <= axi4_if.AWSIZE;
                awburst_reg <= axi4_if.AWBURST;
                awvalid_reg <= 1;
                wr_beat_count <= 0;
            end
            axi4_if.AWREADY <= 1;

            // Write data channel handling
            if (awvalid_reg) begin
                axi4_if.WREADY <= 1;

                if (axi4_if.WVALID && axi4_if.WREADY) begin
                    // Store data to memory (simplified)
                    // In real implementation, handle burst addresses properly

                    if (axi4_if.WLAST) begin
                        // Transaction complete, send response
                        awvalid_reg <= 0;
                        axi4_if.BID <= awid_reg;
                        axi4_if.BRESP <= 2'b00;  // OKAY
                        axi4_if.BVALID <= 1;
                    end

                    wr_beat_count <= wr_beat_count + 1;
                end
            end else begin
                axi4_if.WREADY <= 0;
            end

            // Write response channel handling
            if (axi4_if.BVALID && axi4_if.BREADY) begin
                axi4_if.BVALID <= 0;
            end

            // Read address channel handling
            if (axi4_if.ARVALID && axi4_if.ARREADY) begin
                arid_reg <= axi4_if.ARID;
                araddr_reg <= axi4_if.ARADDR;
                arlen_reg <= axi4_if.ARLEN;
                arsize_reg <= axi4_if.ARSIZE;
                arburst_reg <= axi4_if.ARBURST;
                arvalid_reg <= 1;
                rd_beat_count <= 0;
            end
            axi4_if.ARREADY <= 1;

            // Read data channel handling
            if (arvalid_reg) begin
                axi4_if.RVALID <= 1;
                axi4_if.RID <= arid_reg;
                axi4_if.RDATA <= {DATA_WIDTH{1'b0}};  // Return zeros
                axi4_if.RRESP <= 2'b00;  // OKAY

                if (rd_beat_count == arlen_reg) begin
                    axi4_if.RLAST <= 1;
                    arvalid_reg <= 0;
                    rd_beat_count <= 0;
                end else begin
                    axi4_if.RLAST <= 0;
                    rd_beat_count <= rd_beat_count + 1;
                end
            end else begin
                axi4_if.RVALID <= 0;
                axi4_if.RLAST <= 0;
            end
        end
    end

endmodule : axi4_slave_responder