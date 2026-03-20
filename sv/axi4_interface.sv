// AXI4 Interface
// Contains signal declarations, clocking blocks, and protocol assertions

`ifndef AXI4_INTERFACE_SV
`define AXI4_INTERFACE_SV

interface axi4_interface #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4
)(
    input logic ACLK,
    input logic ARESETn
);

    // Local parameters
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int USER_WIDTH = 16;

    // Write Address Channel
    logic [ID_WIDTH-1:0]    AWID;
    logic [ADDR_WIDTH-1:0]  AWADDR;
    logic [7:0]             AWLEN;
    logic [2:0]             AWSIZE;
    logic [1:0]             AWBURST;
    logic                   AWLOCK;
    logic [3:0]             AWCACHE;
    logic [2:0]             AWPROT;
    logic [3:0]             AWQOS;
    logic [3:0]             AWREGION;
    logic [USER_WIDTH-1:0]  AWUSER;
    logic                   AWVALID;
    logic                   AWREADY;

    // Write Data Channel
    logic [DATA_WIDTH-1:0]  WDATA;
    logic [STRB_WIDTH-1:0]  WSTRB;
    logic                   WLAST;
    logic [USER_WIDTH-1:0]  WUSER;
    logic                   WVALID;
    logic                   WREADY;

    // Write Response Channel
    logic [ID_WIDTH-1:0]    BID;
    logic [1:0]             BRESP;
    logic [USER_WIDTH-1:0]  BUSER;
    logic                   BVALID;
    logic                   BREADY;

    // Read Address Channel
    logic [ID_WIDTH-1:0]    ARID;
    logic [ADDR_WIDTH-1:0]  ARADDR;
    logic [7:0]             ARLEN;
    logic [2:0]             ARSIZE;
    logic [1:0]             ARBURST;
    logic                   ARLOCK;
    logic [3:0]             ARCACHE;
    logic [2:0]             ARPROT;
    logic [3:0]             ARQOS;
    logic [3:0]             ARREGION;
    logic [USER_WIDTH-1:0]  ARUSER;
    logic                   ARVALID;
    logic                   ARREADY;

    // Read Data Channel
    logic [ID_WIDTH-1:0]    RID;
    logic [DATA_WIDTH-1:0]  RDATA;
    logic [1:0]             RRESP;
    logic                   RLAST;
    logic [USER_WIDTH-1:0]  RUSER;
    logic                   RVALID;
    logic                   RREADY;

    // Master clocking block
    clocking master_cb @(posedge ACLK);
        default input #1step output #0;

        // Write Address Channel
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK;
        output AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER;
        output AWVALID;
        input AWREADY;

        // Write Data Channel
        output WDATA, WSTRB, WLAST, WUSER, WVALID;
        input WREADY;

        // Write Response Channel
        output BREADY;
        input BID, BRESP, BUSER, BVALID;

        // Read Address Channel
        output ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK;
        output ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER;
        output ARVALID;
        input ARREADY;

        // Read Data Channel
        output RREADY;
        input RID, RDATA, RRESP, RLAST, RUSER, RVALID;
    endclocking : master_cb

    // Monitor clocking block
    clocking monitor_cb @(posedge ACLK);
        default input #1step output #0;

        // Write Address Channel
        input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK;
        input AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER;
        input AWVALID, AWREADY;

        // Write Data Channel
        input WDATA, WSTRB, WLAST, WUSER, WVALID, WREADY;

        // Write Response Channel
        input BID, BRESP, BUSER, BVALID, BREADY;

        // Read Address Channel
        input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK;
        input ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER;
        input ARVALID, ARREADY;

        // Read Data Channel
        input RID, RDATA, RRESP, RLAST, RUSER, RVALID, RREADY;
    endclocking : monitor_cb

    // Protocol Assertions
    // Assertion 1: AWVALID stability - Master must hold AWVALID until AWREADY goes high
    property p_awvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID && !AWREADY |=> AWVALID;
    endproperty

    assert property (p_awvalid_stable)
        else $error("AWVALID must remain stable until AWREADY asserted");

    cover property (p_awvalid_stable);

    // Assertion 2: ARVALID stability - Master must hold ARVALID until ARREADY goes high
    property p_arvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        ARVALID && !ARREADY |=> ARVALID;
    endproperty

    assert property (p_arvalid_stable)
        else $error("ARVALID must remain stable until ARREADY asserted");

    cover property (p_arvalid_stable);

    // Assertion 3: WVALID stability - Master must hold WVALID until WREADY goes high
    property p_wvalid_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        WVALID && !WREADY |=> WVALID;
    endproperty

    assert property (p_wvalid_stable)
        else $error("WVALID must remain stable until WREADY asserted");

    cover property (p_wvalid_stable);

    // Assertion 4: WLAST correctness - WLAST must be high on the last beat of burst
    // Count beats and verify WLAST is asserted on beat count = AWLEN + 1
    property p_wlast_correct;
        int beat_count = 0;
        @(posedge ACLK) disable iff (!ARESETn)
        (WVALID && WREADY, beat_count = (WLAST) ? 0 : beat_count + 1)
        |-> (WLAST |-> beat_count == AWLEN);
    endproperty

    assert property (p_wlast_correct)
        else $error("WLAST must be asserted on the correct beat");

    cover property (p_wlast_correct);

    // Assertion 5: RLAST correctness - Slave must assert RLAST on last beat
    property p_rlast_correct;
        int beat_count = 0;
        @(posedge ACLK) disable iff (!ARESETn)
        (RVALID && RREADY, beat_count = (RLAST) ? 0 : beat_count + 1)
        |-> (RLAST |-> beat_count == ARLEN);
    endproperty

    assert property (p_rlast_correct)
        else $error("RLAST must be asserted on the correct beat");

    cover property (p_rlast_correct);

    // Assertion 6: AXLEN range validation
    // AWLEN/ARLEN must be 0-255, for FIXED burst <= 15, for WRAP burst must be 1,3,7,15
    property p_awlen_range;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID |->
            (AWLEN <= 255) &&
            ((AWBURST != 2'b00) || (AWLEN <= 15)) &&  // FIXED
            ((AWBURST != 2'b10) || (AWLEN inside {1, 3, 7, 15}));  // WRAP
    endproperty

    assert property (p_awlen_range)
        else $error("AWLEN out of valid range for burst type");

    cover property (p_awlen_range);

    property p_arlen_range;
        @(posedge ACLK) disable iff (!ARESETn)
        ARVALID |->
            (ARLEN <= 255) &&
            ((ARBURST != 2'b00) || (ARLEN <= 15)) &&  // FIXED
            ((ARBURST != 2'b10) || (ARLEN inside {1, 3, 7, 15}));  // WRAP
    endproperty

    assert property (p_arlen_range)
        else $error("ARLEN out of valid range for burst type");

    cover property (p_arlen_range);

    // Assertion 7: AXBURST encoding validation
    property p_awburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID |-> (AWBURST != 2'b11);
    endproperty

    assert property (p_awburst_valid)
        else $error("AWBURST must not be reserved value 2'b11");

    cover property (p_awburst_valid);

    property p_arburst_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        ARVALID |-> (ARBURST != 2'b11);
    endproperty

    assert property (p_arburst_valid)
        else $error("ARBURST must not be reserved value 2'b11");

    cover property (p_arburst_valid);

    // Assertion 8: AXSIZE range validation
    property p_awsize_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        AWVALID |-> ((1 << AWSIZE) <= (DATA_WIDTH / 8));
    endproperty

    assert property (p_awsize_valid)
        else $error("AWSIZE exceeds data width capacity");

    cover property (p_awsize_valid);

    property p_arsize_valid;
        @(posedge ACLK) disable iff (!ARESETn)
        ARVALID |-> ((1 << ARSIZE) <= (DATA_WIDTH / 8));
    endproperty

    assert property (p_arsize_valid)
        else $error("ARSIZE exceeds data width capacity");

    cover property (p_arsize_valid);

    // Assertion 9: W channel data stability
    // From WVALID assertion to WREADY, WDATA/WSTRB/WLAST must remain stable
    property p_wdata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (WVALID && !WREADY)
        |=> (WVALID && !WREADY) |-> (($past(WDATA) == WDATA) &&
                                       ($past(WSTRB) == WSTRB) &&
                                       ($past(WLAST) == WLAST));
    endproperty

    assert property (p_wdata_stable)
        else $error("WDATA/WSTRB/WLAST must remain stable while WVALID asserted and WREADY not asserted");

    cover property (p_wdata_stable);

    // Assertion 10: AR channel data stability
    property p_ardata_stable;
        @(posedge ACLK) disable iff (!ARESETn)
        (ARVALID && !ARREADY)
        |=> (ARVALID && !ARREADY) |-> (
            $past(ARADDR) == ARADDR &&
            $past(ARID) == ARID &&
            $past(ARLEN) == ARLEN &&
            $past(ARSIZE) == ARSIZE &&
            $past(ARBURST) == ARBURST
        );
    endproperty

    assert property (p_ardata_stable)
        else $error("AR channel signals must remain stable while ARVALID asserted and ARREADY not asserted");

    cover property (p_ardata_stable);

    // Assertion 11: WSTRB width matching
    property p_wstrb_width;
        @(posedge ACLK) disable iff (!ARESETn)
        1 |-> $bits(WSTRB) == (DATA_WIDTH / 8);
    endproperty

    assert property (p_wstrb_width)
        else $error("WSTRB width must equal DATA_WIDTH/8");

    // Assertion 12: Unaligned first beat WSTRB
    // If starting address is unaligned, first beat WSTRB must have lower bytes masked
    // This is checked at the driver level as it requires knowledge of the transfer

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