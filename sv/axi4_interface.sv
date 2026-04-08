// AXI4 Interface
// Contains signal declarations, clocking blocks, and protocol assertions

`ifndef AXI4_INTERFACE_SV
`define AXI4_INTERFACE_SV

`include "axi4_params.svh"
import uvm_pkg::*;
`include "uvm_macros.svh"

interface axi4_interface #(
    parameter int DATA_WIDTH = `AXI4_DATA_WIDTH,
    parameter int ADDR_WIDTH = `AXI4_ADDR_WIDTH,
    parameter int ID_WIDTH = `AXI4_ID_WIDTH
)(
    input logic ACLK,
    input logic ARESETn
);

    // Local parameters
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int USER_WIDTH = 16;

    // Write Address Channel
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
    logic                   awlock;
    logic [3:0]             awcache;
    logic [2:0]             awprot;
    logic [3:0]             awqos;
    logic [3:0]             awregion;
    logic [USER_WIDTH-1:0]  awuser;
    logic                   awvalid;
    logic                   awready;

    // Write Data Channel
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wlast;
    logic [USER_WIDTH-1:0]  wuser;
    logic                   wvalid;
    logic                   wready;

    // Write Response Channel
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic [USER_WIDTH-1:0]  buser;
    logic                   bvalid;
    logic                   bready;

    // Read Address Channel
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [7:0]             arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arlock;
    logic [3:0]             arcache;
    logic [2:0]             arprot;
    logic [3:0]             arqos;
    logic [3:0]             arregion;
    logic [USER_WIDTH-1:0]  aruser;
    logic                   arvalid;
    logic                   arready;

    // Read Data Channel
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic [USER_WIDTH-1:0]  ruser;
    logic                   rvalid;
    logic                   rready;

    // Master clocking block
    clocking master_cb @(posedge ACLK);
        default input #1step output #1step;

        // Write Address Channel
        output awid, awaddr, awlen, awsize, awburst, awlock;
        output awcache, awprot, awqos, awregion, awuser;
        output awvalid;
        input awready;

        // Write Data Channel
        output wdata, wstrb, wlast, wuser, wvalid;
        input wready;

        // Write Response Channel
        output bready;
        input bid, bresp, buser, bvalid;

        // Read Address Channel
        output arid, araddr, arlen, arsize, arburst, arlock;
        output arcache, arprot, arqos, arregion, aruser;
        output arvalid;
        input arready;

        // Read Data Channel
        output rready;
        input rid, rdata, rresp, rlast, ruser, rvalid;
    endclocking : master_cb

    // Monitor clocking block
    clocking monitor_cb @(posedge ACLK);
        default input #1step output #0;

        // Write Address Channel
        input awid, awaddr, awlen, awsize, awburst, awlock;
        input awcache, awprot, awqos, awregion, awuser;
        input awvalid, awready;

        // Write Data Channel
        input wdata, wstrb, wlast, wuser, wvalid, wready;

        // Write Response Channel
        input bid, bresp, buser, bvalid, bready;

        // Read Address Channel
        input arid, araddr, arlen, arsize, arburst, arlock;
        input arcache, arprot, arqos, arregion, aruser;
        input arvalid, arready;

        // Read Data Channel
        input rid, rdata, rresp, rlast, ruser, rvalid, rready;
    endclocking : monitor_cb

    // Protocol Assertions

    // Beat counters for WLAST/RLAST assertion checking
    int w_beat_count;
    int r_beat_count;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_beat_count <= 0;
            r_beat_count <= 0;
        end else begin
            // Count write beats
            if (wvalid && wready) begin
                if (wlast)
                    w_beat_count <= 0;
                else
                    w_beat_count <= w_beat_count + 1;
            end

            // Count read beats
            if (rvalid && rready) begin
                if (rlast)
                    r_beat_count <= 0;
                else
                    r_beat_count <= r_beat_count + 1;
            end
        end
    end

    // Assertion 1: AWVALID stability - Master must hold AWVALID until AWREADY goes high
    property p_awvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        awvalid && !awready |=> awvalid;
    endproperty

    assert property (p_awvalid_stable)
        else `uvm_error("AXI4_ASSERT", "awvalid must remain stable until awready asserted")

    cover property (p_awvalid_stable);

    // Assertion 2: ARVALID stability - Master must hold ARVALID until ARREADY goes high
    property p_arvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        arvalid && !arready |=> arvalid;
    endproperty

    assert property (p_arvalid_stable)
        else `uvm_error("AXI4_ASSERT", "arvalid must remain stable until arready asserted")

    cover property (p_arvalid_stable);

    // Assertion 3: WVALID stability - Master must hold WVALID until WREADY goes high
    property p_wvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        wvalid && !wready |=> wvalid;
    endproperty

    assert property (p_wvalid_stable)
        else `uvm_error("AXI4_ASSERT", "wvalid must remain stable until wready asserted")

    cover property (p_wvalid_stable);

    // Assertion 4: WLAST correctness - WLAST must be high on the last beat of burst
    // For burst with AWLEN=N, there should be N+1 beats, WLAST on last beat
    property p_wlast_correct;
        @(posedge ACLK) disable iff (!ARESETn)
        (wvalid && wready && wlast) |-> w_beat_count == awlen;
    endproperty

    assert property (p_wlast_correct)
        else `uvm_error("AXI4_ASSERT", "wlast must be asserted on the correct beat")

    cover property (p_wlast_correct);

    // Assertion 5: RLAST correctness - Slave must assert RLAST on last beat
    property p_rlast_correct;
        @(posedge ACLK) disable iff (!ARESETn)
        (rvalid && rready && rlast) |-> r_beat_count == arlen;
    endproperty

    assert property (p_rlast_correct)
        else `uvm_error("AXI4_ASSERT", "rlast must be asserted on the correct beat")

    cover property (p_rlast_correct);

    // Assertion 6: AXLEN range validation
    // AWLEN/ARLEN must be 0-255, for FIXED burst <= 15, for WRAP burst must be 1,3,7,15
    property p_awlen_range;
        @(posedge ACLK) disable iff (!ARESETn)
        awvalid |->
            (awlen <= 255) &&
            ((awburst != 2'b00) || (awlen <= 15)) &&  // FIXED
            ((awburst != 2'b10) || (awlen inside {1, 3, 7, 15}));  // WRAP
    endproperty

    assert property (p_awlen_range)
        else `uvm_error("AXI4_ASSERT", "awlen out of valid range for burst type")

    cover property (p_awlen_range);

    property p_arlen_range;
        @(posedge ACLK) disable iff (!ARESETn)
        arvalid |->
            (arlen <= 255) &&
            ((arburst != 2'b00) || (arlen <= 15)) &&  // FIXED
            ((arburst != 2'b10) || (arlen inside {1, 3, 7, 15}));  // WRAP
    endproperty

    assert property (p_arlen_range)
        else `uvm_error("AXI4_ASSERT", "arlen out of valid range for burst type")

    cover property (p_arlen_range);

    // Assertion 7: AXBURST encoding validation
    property p_awburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        awvalid |-> (awburst != 2'b11);
    endproperty

    assert property (p_awburst_valid)
        else `uvm_error("AXI4_ASSERT", "awburst must not be reserved value 2'b11")

    cover property (p_awburst_valid);

    property p_arburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        arvalid |-> (arburst != 2'b11);
    endproperty

    assert property (p_arburst_valid)
        else `uvm_error("AXI4_ASSERT", "arburst must not be reserved value 2'b11")

    cover property (p_arburst_valid);

    // Assertion 8: AXSIZE range validation
    property p_awsize_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        awvalid |-> ((1 << awsize) <= (DATA_WIDTH / 8));
    endproperty

    assert property (p_awsize_valid)
        else `uvm_error("AXI4_ASSERT", "awsize exceeds data width capacity")

    cover property (p_awsize_valid);

    property p_arsize_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        arvalid |-> ((1 << arsize) <= (DATA_WIDTH / 8));
    endproperty

    assert property (p_arsize_valid)
        else `uvm_error("AXI4_ASSERT", "arsize exceeds data width capacity")

    cover property (p_arsize_valid);

    // Assertion 9: W channel data stability
    // From WVALID assertion to WREADY, WDATA/WSTRB/WLAST must remain stable
    property p_wdata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (wvalid && !wready)
        |=> (wvalid && !wready) |-> (($past(wdata) == wdata) &&
                                       ($past(wstrb) == wstrb) &&
                                       ($past(wlast) == wlast));
    endproperty

    assert property (p_wdata_stable)
        else `uvm_error("AXI4_ASSERT", "wdata/wstrb/wlast must remain stable while wvalid asserted and wready not asserted")

    cover property (p_wdata_stable);

    // Assertion 10: AR channel data stability
    property p_ardata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (arvalid && !arready)
        |=> (arvalid && !arready) |-> (
            $past(araddr) == araddr &&
            $past(arid) == arid &&
            $past(arlen) == arlen &&
            $past(arsize) == arsize &&
            $past(arburst) == arburst);
    endproperty

    assert property (p_ardata_stable)
        else `uvm_error("AXI4_ASSERT", "AR channel signals must remain stable while arvalid asserted and arready not asserted")

    cover property (p_ardata_stable);

    // Assertion 11: WSTRB width matching
    property p_wstrb_width;
        @(posedge ACLK) disable iff (!ARESETn)
        1 |-> $bits(wstrb) == (DATA_WIDTH / 8);
    endproperty

    assert property (p_wstrb_width)
        else `uvm_error("AXI4_ASSERT", "wstrb width must equal DATA_WIDTH/8")

    // Assertion 12: Unaligned first beat WSTRB
    // If starting address is unaligned, first beat WSTRB must have lower bytes masked
    // This is checked at the driver level as it requires knowledge of the transfer

    // Assertion 13: 2KB Boundary Crossing Check for Write Burst
    // For INCR burst, the burst must not cross a 2KB boundary after splitting
    // Burst size = (awlen + 1) * (1 << awsize) bytes
    // 2KB = 2048 bytes = 2^11, boundary at address[10:0] == 0
    // We check bits [31:11] to determine 2KB region
    property p_awaddr_2kb_boundary;
        @(posedge ACLK) disable iff (!ARESETn)
        (awvalid && awburst == 2'b01) |->
            // Check that burst doesn't cross 2KB boundary
            // end_addr = awaddr + (awlen+1)*(1<<awsize) - 1
            // Crosses boundary if: awaddr[31:11] != end_addr[31:11]
            // Use 12-bit arithmetic to avoid overflow (2048 needs 12 bits)
            ((awaddr[10:0] + ((awlen + 1) << awsize)) <= 12'd2048);
    endproperty

    assert property (p_awaddr_2kb_boundary)
        else `uvm_error("AXI4_ASSERT", $sformatf("Write burst crosses 2KB boundary: awaddr=0x%0h, awlen=%0d, awsize=%0d", awaddr, awlen, awsize))

    cover property (p_awaddr_2kb_boundary);

    // Assertion 14: 2KB Boundary Crossing Check for Read Burst
    property p_araddr_2kb_boundary;
        @(posedge ACLK) disable iff (!ARESETn)
        (arvalid && arburst == 2'b01) |->
            ((araddr[10:0] + ((arlen + 1) << arsize)) <= 12'd2048);
    endproperty

    assert property (p_araddr_2kb_boundary)
        else `uvm_error("AXI4_ASSERT", $sformatf("Read burst crosses 2KB boundary: araddr=0x%0h, arlen=%0d, arsize=%0d", araddr, arlen, arsize))

    cover property (p_araddr_2kb_boundary);

    // Additional helper tasks
    task automatic wait_for_reset();
        @(posedge ARESETn);
        @(posedge ACLK);
    endtask

    task automatic wait_cycles(int cycles);
        repeat(cycles) @(posedge ACLK);
    endtask

endinterface : axi4_interface

`endif // AXI4_INTERFACE_SV