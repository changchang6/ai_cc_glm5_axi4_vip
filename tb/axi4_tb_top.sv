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

    // Slave Memory Model
    axi4_slave_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) u_slave_memory (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .axi4_if(axi4_vif)
    );

    // UVM initial block
    initial begin
        // Pass virtual interface to test
        uvm_config_db#(virtual axi4_interface #(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH))::set(
            null, "uvm_test_top", "m_vif", axi4_vif);

        // Run smoke test by default
        run_test("axi4_smoke_test");
    end

    // Timeout
    initial begin
        #100000;
        `uvm_error("TB_TOP", "Simulation timeout reached")
        $finish;
    end

endmodule : axi4_tb_top

// AXI4 Slave Memory Model
// Implements a functional memory that stores written data and returns it on reads
module axi4_slave_memory #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4
)(
    input logic ACLK,
    input logic ARESETn,
    axi4_interface axi4_if
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // Memory array - byte-addressable
    logic [7:0] memory [bit [ADDR_WIDTH-1:0]];

    // Write address channel registers
    logic [ID_WIDTH-1:0]   awid_reg;
    logic [ADDR_WIDTH-1:0] awaddr_reg;
    logic [7:0]            awlen_reg;
    logic [2:0]            awsize_reg;
    logic [1:0]            awburst_reg;
    logic                  awvalid_reg;
    logic [ADDR_WIDTH-1:0] awaddr_base;  // Base address for burst

    // Read address channel registers
    logic [ID_WIDTH-1:0]   arid_reg;
    logic [ADDR_WIDTH-1:0] araddr_reg;
    logic [7:0]            arlen_reg;
    logic [2:0]            arsize_reg;
    logic [1:0]            arburst_reg;
    logic                  arvalid_reg;
    logic [ADDR_WIDTH-1:0] araddr_base;  // Base address for burst

    // Beat counters
    int wr_beat_count;
    int rd_beat_count;

    // Write state machine
    typedef enum bit [1:0] {
        WR_IDLE,
        WR_DATA,
        WR_RESP
    } wr_state_t;
    wr_state_t wr_state;

    // Read state machine
    typedef enum bit [1:0] {
        RD_IDLE,
        RD_DATA
    } rd_state_t;
    rd_state_t rd_state;

    // Function to calculate burst address
    function automatic bit [ADDR_WIDTH-1:0] calc_burst_addr(
        input bit [ADDR_WIDTH-1:0] base_addr,
        input int beat_count,
        input bit [2:0] size,
        input bit [1:0] burst_type,
        input bit [7:0] len
    );
        bit [ADDR_WIDTH-1:0] addr;
        int beat_size;
        int wrap_boundary;
        int wrap_size;

        beat_size = 1 << size;

        case (burst_type)
            2'b00: begin // FIXED
                addr = base_addr;
            end
            2'b01: begin // INCR
                addr = base_addr + beat_count * beat_size;
            end
            2'b10: begin // WRAP
                wrap_size = (len + 1) * beat_size;
                wrap_boundary = (base_addr / wrap_size) * wrap_size;
                addr = wrap_boundary + ((base_addr + beat_count * beat_size) % wrap_size);
            end
            default: begin
                addr = base_addr + beat_count * beat_size;
            end
        endcase

        return addr;
    endfunction

    // Function to write data to memory with WSTRB
    task automatic write_to_memory(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [DATA_WIDTH-1:0] data,
        input bit [STRB_WIDTH-1:0] strb
    );
        for (int i = 0; i < STRB_WIDTH; i++) begin
            if (strb[i]) begin
                memory[addr + i] = data[i*8 +: 8];
            end
        end
    endtask

    // Function to read data from memory
    function automatic bit [DATA_WIDTH-1:0] read_from_memory(
        input bit [ADDR_WIDTH-1:0] addr
    );
        bit [DATA_WIDTH-1:0] data;
        for (int i = 0; i < STRB_WIDTH; i++) begin
            if (memory.exists(addr + i)) begin
                data[i*8 +: 8] = memory[addr + i];
            end else begin
                data[i*8 +: 8] = 8'h00;
            end
        end
        return data;
    endfunction

    // Write channel state machine
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wr_state <= WR_IDLE;
            awvalid_reg <= 0;
            awid_reg <= 0;
            awaddr_reg <= 0;
            awlen_reg <= 0;
            awsize_reg <= 0;
            awburst_reg <= 0;
            awaddr_base <= 0;
            wr_beat_count <= 0;
            axi4_if.awready <= 0;
            axi4_if.wready <= 0;
            axi4_if.bvalid <= 0;
            axi4_if.bid <= 0;
            axi4_if.bresp <= 0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    axi4_if.awready <= 1;
                    axi4_if.wready <= 0;
                    axi4_if.bvalid <= 0;

                    if (axi4_if.awvalid && axi4_if.awready) begin
                        awid_reg <= axi4_if.awid;
                        awaddr_reg <= axi4_if.awaddr;
                        awlen_reg <= axi4_if.awlen;
                        awsize_reg <= axi4_if.awsize;
                        awburst_reg <= axi4_if.awburst;
                        awaddr_base <= axi4_if.awaddr;
                        awvalid_reg <= 1;
                        wr_beat_count <= 0;
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    axi4_if.awready <= 0;
                    axi4_if.wready <= 1;

                    if (axi4_if.wvalid && axi4_if.wready) begin
                        // Calculate address for this beat
                        awaddr_reg = calc_burst_addr(
                            awaddr_base,
                            wr_beat_count,
                            awsize_reg,
                            awburst_reg,
                            awlen_reg
                        );

                        // Write data to memory
                        write_to_memory(awaddr_reg, axi4_if.wdata, axi4_if.wstrb);

                        // Check for last beat
                        if (axi4_if.wlast) begin
                            wr_state <= WR_RESP;
                            awvalid_reg <= 0;
                        end else begin
                            wr_beat_count <= wr_beat_count + 1;
                        end
                    end
                end

                WR_RESP: begin
                    axi4_if.wready <= 0;
                    axi4_if.bvalid <= 1;
                    axi4_if.bid <= awid_reg;
                    axi4_if.bresp <= 2'b00;  // OKAY

                    if (axi4_if.bvalid && axi4_if.bready) begin
                        axi4_if.bvalid <= 0;
                        wr_state <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // Read channel state machine
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_state <= RD_IDLE;
            arvalid_reg <= 0;
            arid_reg <= 0;
            araddr_reg <= 0;
            arlen_reg <= 0;
            arsize_reg <= 0;
            arburst_reg <= 0;
            araddr_base <= 0;
            rd_beat_count <= 0;
            axi4_if.arready <= 0;
            axi4_if.rvalid <= 0;
            axi4_if.rid <= 0;
            axi4_if.rdata <= 0;
            axi4_if.rresp <= 0;
            axi4_if.rlast <= 0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    axi4_if.arready <= 1;
                    axi4_if.rvalid <= 0;

                    if (axi4_if.arvalid && axi4_if.arready) begin
                        arid_reg <= axi4_if.arid;
                        araddr_reg <= axi4_if.araddr;
                        arlen_reg <= axi4_if.arlen;
                        arsize_reg <= axi4_if.arsize;
                        arburst_reg <= axi4_if.arburst;
                        araddr_base <= axi4_if.araddr;
                        arvalid_reg <= 1;
                        rd_beat_count <= 0;
                        rd_state <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    axi4_if.arready <= 0;
                    axi4_if.rvalid <= 1;
                    axi4_if.rid <= arid_reg;

                    // Calculate address for this beat
                    araddr_reg = calc_burst_addr(
                        araddr_base,
                        rd_beat_count,
                        arsize_reg,
                        arburst_reg,
                        arlen_reg
                    );

                    // Read data from memory
                    axi4_if.rdata <= read_from_memory(araddr_reg);
                    axi4_if.rresp <= 2'b00;  // OKAY

                    // Check for last beat
                    if (rd_beat_count == arlen_reg) begin
                        axi4_if.rlast <= 1;
                        if (axi4_if.rvalid && axi4_if.rready) begin
                            axi4_if.rvalid <= 0;
                            axi4_if.rlast <= 0;
                            arvalid_reg <= 0;
                            rd_state <= RD_IDLE;
                        end
                    end else begin
                        axi4_if.rlast <= 0;
                        if (axi4_if.rvalid && axi4_if.rready) begin
                            rd_beat_count <= rd_beat_count + 1;
                        end
                    end
                end
            endcase
        end
    end

    // Debug: Display memory contents on write
    always @(posedge ACLK) begin
        if (ARESETn && axi4_if.wvalid && axi4_if.wready && wr_state == WR_DATA) begin
            $display("[%0t] SLAVE_MEM: Write ADDR=0x%08h DATA=0x%08h STRB=0x%0h",
                $time, awaddr_reg, axi4_if.wdata, axi4_if.wstrb);
        end
    end

    // Debug: Display memory contents on read
    always @(posedge ACLK) begin
        if (ARESETn && axi4_if.rvalid && axi4_if.rready && rd_state == RD_DATA) begin
            $display("[%0t] SLAVE_MEM: Read ADDR=0x%08h DATA=0x%08h",
                $time, araddr_reg, axi4_if.rdata);
        end
    end
    
    initial begin
        string fsdb_file;
        if (!$value$plusargs("FSDB_FILE=%s", fsdb_file))
            fsdb_file = "sim";
        $fsdbDumpfile({fsdb_file, ".fsdb"});
        $fsdbDumpvars(0, axi4_tb_top);
    end
endmodule : axi4_slave_memory
