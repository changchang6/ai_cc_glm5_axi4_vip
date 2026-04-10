// AXI4 Monitor
// Observes bus signals, collects transactions, and calculates statistics

`ifndef AXI4_MONITOR_SV
`define AXI4_MONITOR_SV

class axi4_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_monitor)

    // Configuration handle
    axi4_config m_cfg;

    // Virtual interface
    virtual axi4_interface m_vif;

    // Analysis port for collected transactions
    uvm_analysis_port #(axi4_transaction) m_ap;

    // Transaction queues for tracking in-flight transactions
    // Key: ID, Value: transaction
    local axi4_transaction m_wr_trans_q[$];
    local axi4_transaction m_rd_trans_q[$];

    // Latency tracking
    local axi4_latency_stats_t m_rd_latency_stats;
    local axi4_latency_stats_t m_wr_latency_stats;

    // Bandwidth tracking
    local axi4_bandwidth_stats_t m_bw_stats;

    // Timing tracking
    local time m_start_time;
    local real m_total_time_ns;

    // Outstanding transaction tracking for timeout
    local int m_wr_timeout_q[$];  // Stores start cycle for each write
    local int m_rd_timeout_q[$];  // Stores start cycle for each read
    local int m_cycle_count;

    // Timeout ID tracking
    local int m_wr_timeout_id_q[$];  // Stores IDs of write timeouts
    local int m_rd_timeout_id_q[$];  // Stores IDs of read timeouts
    local int m_wr_timeout_count;    // Total write timeout count
    local int m_rd_timeout_count;    // Total read timeout count

    // Track which transactions have received their W data
    bit m_wr_data_done[$];

    // Data-before-addr support: buffer for W data beats that arrive before AW
    typedef struct {
        bit [255:0] wdata;    // Max data width
        bit [31:0]  wstrb;    // Max strobe width
        bit         wlast;
    } w_data_buf_t;
    local w_data_buf_t m_w_data_buf[$];  // Buffer for W data before AW arrives

    // Constructor
    function new(string name = "axi4_monitor", uvm_component parent = null);
        super.new(name, parent);
        m_ap = new("m_ap", this);

        // Initialize latency stats
        m_rd_latency_stats.min_latency = '1;
        m_rd_latency_stats.max_latency = 0;
        m_rd_latency_stats.total_latency = 0;
        m_rd_latency_stats.trans_count = 0;

        m_wr_latency_stats.min_latency = '1;
        m_wr_latency_stats.max_latency = 0;
        m_wr_latency_stats.total_latency = 0;
        m_wr_latency_stats.trans_count = 0;

        // Initialize timeout tracking
        m_wr_timeout_count = 0;
        m_rd_timeout_count = 0;
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_config)::get(this, "", "m_cfg", m_cfg)) begin
            `uvm_warning(get_type_name(), "Configuration not found, using defaults")
        end
    endfunction

    // Connect phase
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (m_cfg != null) begin
            m_vif = m_cfg.m_vif;
        end
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        if (m_vif == null) begin
            `uvm_error(get_type_name(), "Virtual interface not set")
            return;
        end

        m_start_time = $realtime;
        m_cycle_count = 0;

        fork
            // Monitor write address channel
            monitor_aw_channel();

            // Monitor write data channel
            monitor_w_channel();

            // Monitor write response channel
            monitor_b_channel();

            // Monitor read address channel
            monitor_ar_channel();

            // Monitor read data channel
            monitor_r_channel();

            // Cycle counter for timeout
            count_cycles();

            // Check timeouts
            check_timeouts();
        join_none
    endtask

    // Monitor write address channel
    task monitor_aw_channel();
        axi4_transaction trans;
        int addr_accept_cycle;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                m_wr_trans_q.delete();
                continue;
            end

            if (m_vif.monitor_cb.awvalid && m_vif.monitor_cb.awready) begin
                // Create new write transaction
                trans = axi4_transaction::type_id::create("wr_trans");
                trans.m_trans_type = WRITE;
                trans.m_id         = m_vif.monitor_cb.awid;
                trans.m_addr       = m_vif.monitor_cb.awaddr;
                trans.m_len        = m_vif.monitor_cb.awlen;
                trans.m_size       = m_vif.monitor_cb.awsize;
                trans.m_burst      = axi4_burst_t'(m_vif.monitor_cb.awburst);
                trans.m_lock       = m_vif.monitor_cb.awlock;
                trans.m_cache      = m_vif.monitor_cb.awcache;
                trans.m_qos        = m_vif.monitor_cb.awqos;
                trans.m_region     = m_vif.monitor_cb.awregion;
                trans.m_user       = m_vif.monitor_cb.awuser;

                // Initialize data arrays
                trans.m_wdata = new[trans.m_len + 1];
                trans.m_wstrb = new[trans.m_len + 1];

                // Store transaction with cycle count for latency calculation
                trans.m_data_width = m_cfg.m_data_width;
                trans.m_addr_width = m_cfg.m_addr_width;
                trans.m_id_width   = m_cfg.m_id_width;

                m_wr_trans_q.push_back(trans);

                // Track for timeout - start from AW handshake
                m_wr_timeout_q.push_back(m_cycle_count);

                `uvm_info(get_type_name(), $sformatf("AW Channel: ID=%0d, ADDR=0x%08h, LEN=%0d",
                    trans.m_id, trans.m_addr, trans.m_len), UVM_HIGH)

                // Data-before-addr: Check if there's buffered W data to match
                // The buffered W data should match this transaction in FIFO order
                if (m_w_data_buf.size() > 0) begin
                    // Variable declarations must be at the beginning of the block
                    automatic int beat_idx = 0;
                    automatic int beats_to_copy = trans.m_len + 1;
                    automatic w_data_buf_t w_buf;

                    // Copy buffered W data to this transaction
                    while (m_w_data_buf.size() > 0 && beat_idx < beats_to_copy) begin
                        w_buf = m_w_data_buf.pop_front();
                        trans.m_wdata[beat_idx] = w_buf.wdata;
                        trans.m_wstrb[beat_idx] = w_buf.wstrb;

                        `uvm_info(get_type_name(), $sformatf(
                            "AW Channel: Matched buffered W beat %0d, WLAST=%b",
                            beat_idx, w_buf.wlast), UVM_HIGH)

                        beat_idx++;

                        if (w_buf.wlast) begin
                            // This buffered transaction is complete
                            m_wr_data_done.push_back(1);
                            break;
                        end
                    end

                    // If we didn't get all beats, wait for more W data
                    // Will be handled by monitor_w_channel
                end
            end
        end
    endtask

    // Monitor write data channel
    task monitor_w_channel();
        int beat_count;
        int trans_idx;
        w_data_buf_t w_buf;  // Variable for data-before-addr case

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                beat_count = 0;
                trans_idx = 0;
                m_wr_data_done.delete();
                m_w_data_buf.delete();
                continue;
            end

            if (m_vif.monitor_cb.wvalid && m_vif.monitor_cb.wready) begin
                // Find first transaction that hasn't received all its W data
                // In AXI4, W data comes in order of AW addresses
                trans_idx = m_wr_data_done.size();

                if (trans_idx < m_wr_trans_q.size()) begin
                    // Normal case: AW arrived before or at the same time as W data
                    // Store write data
                    m_wr_trans_q[trans_idx].m_wdata[beat_count] = m_vif.monitor_cb.wdata;
                    m_wr_trans_q[trans_idx].m_wstrb[beat_count] = m_vif.monitor_cb.wstrb;

                    `uvm_info(get_type_name(), $sformatf("W Channel: Trans %0d, Beat %0d, WLAST=%b",
                        trans_idx, beat_count, m_vif.monitor_cb.wlast), UVM_HIGH)

                    if (m_vif.monitor_cb.wlast) begin
                        // Mark this transaction as having received all W data
                        m_wr_data_done.push_back(1);
                        beat_count = 0;
                    end else begin
                        beat_count++;
                    end
                end else begin
                    // Data-before-addr case: W data arrived before AW
                    // Buffer the W data for later matching
                    w_buf.wdata = m_vif.monitor_cb.wdata;
                    w_buf.wstrb = m_vif.monitor_cb.wstrb;
                    w_buf.wlast = m_vif.monitor_cb.wlast;
                    m_w_data_buf.push_back(w_buf);

                    `uvm_info(get_type_name(), $sformatf(
                        "W Channel (data-before-addr): Buffered W beat, WLAST=%b, buf_size=%0d",
                        m_vif.monitor_cb.wlast, m_w_data_buf.size()), UVM_HIGH)
                end
            end
        end
    endtask

    // Monitor write response channel
    task monitor_b_channel();
        axi4_transaction trans;
        int latency;
        int trans_idx;
        int start_cycle;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                continue;
            end

            if (m_vif.monitor_cb.bvalid && m_vif.monitor_cb.bready) begin
                // Find matching transaction by BID
                trans = null;
                for (int i = 0; i < m_wr_trans_q.size(); i++) begin
                    if (m_wr_trans_q[i].m_id == m_vif.monitor_cb.bid) begin
                        trans = m_wr_trans_q[i];
                        trans_idx = i;
                        start_cycle = m_wr_timeout_q[i];
                        break;
                    end
                end

                if (trans != null) begin
                    trans.m_resp = axi4_resp_t'(m_vif.monitor_cb.bresp);

                    // Calculate latency (BVALID to last W data already sent)
                    latency = m_cycle_count - start_cycle;

                    // Update statistics
                    update_wr_latency_stats(latency, trans.m_id);

                    // Update bandwidth
                    m_bw_stats.total_bytes += trans.get_transfer_size_bytes();

                    `uvm_info(get_type_name(), $sformatf(
                        "Write Complete: ID=%0d, ADDR=0x%08h, RESP=%s, Latency=%0d cycles",
                        trans.m_id, trans.m_addr, trans.m_resp.name(), latency), UVM_MEDIUM)

                    // Send to analysis port
                    m_ap.write(trans);

                    // Remove from queue (but maintain W data tracking)
                    m_wr_trans_q.delete(trans_idx);
                    m_wr_timeout_q.delete(trans_idx);
                    if (trans_idx < m_wr_data_done.size()) begin
                        m_wr_data_done.delete(trans_idx);
                    end
                end else begin
                    `uvm_warning(get_type_name(), $sformatf(
                        "B response received with unknown BID=%0d", m_vif.monitor_cb.bid))
                end
            end
        end
    endtask

    // Monitor read address channel
    task monitor_ar_channel();
        axi4_transaction trans;
        int addr_accept_cycle;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                m_rd_trans_q.delete();
                continue;
            end

            if (m_vif.monitor_cb.arvalid && m_vif.monitor_cb.arready) begin
                // Create new read transaction
                trans = axi4_transaction::type_id::create("rd_trans");
                trans.m_trans_type = READ;
                trans.m_id         = m_vif.monitor_cb.arid;
                trans.m_addr       = m_vif.monitor_cb.araddr;
                trans.m_len        = m_vif.monitor_cb.arlen;
                trans.m_size       = m_vif.monitor_cb.arsize;
                trans.m_burst      = axi4_burst_t'(m_vif.monitor_cb.arburst);
                trans.m_lock       = m_vif.monitor_cb.arlock;
                trans.m_cache      = m_vif.monitor_cb.arcache;
                trans.m_qos        = m_vif.monitor_cb.arqos;
                trans.m_region     = m_vif.monitor_cb.arregion;
                trans.m_user       = m_vif.monitor_cb.aruser;

                // Initialize data arrays
                trans.m_wdata = new[trans.m_len + 1];
                trans.m_wstrb = new[trans.m_len + 1];

                trans.m_data_width = m_cfg.m_data_width;
                trans.m_addr_width = m_cfg.m_addr_width;
                trans.m_id_width   = m_cfg.m_id_width;

                m_rd_trans_q.push_back(trans);

                // Track for timeout
                m_rd_timeout_q.push_back(m_cycle_count);

                `uvm_info(get_type_name(), $sformatf("AR Channel: ID=%0d, ADDR=0x%08h, LEN=%0d",
                    trans.m_id, trans.m_addr, trans.m_len), UVM_HIGH)
            end
        end
    endtask

    // Monitor read data channel
    task monitor_r_channel();
        axi4_transaction trans;
        int beat_count[$];
        int trans_idx;
        int start_cycle;
        int latency;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                beat_count.delete();
                continue;
            end

            if (m_vif.monitor_cb.rvalid && m_vif.monitor_cb.rready) begin
                // Find matching transaction by RID
                trans = null;
                for (int i = 0; i < m_rd_trans_q.size(); i++) begin
                    if (m_rd_trans_q[i].m_id == m_vif.monitor_cb.rid) begin
                        trans = m_rd_trans_q[i];
                        trans_idx = i;
                        start_cycle = m_rd_timeout_q[i];
                        break;
                    end
                end

                if (trans != null) begin
                    // Ensure beat_count has enough entries
                    while (beat_count.size() <= trans_idx) begin
                        beat_count.push_back(0);
                    end

                    // Store read data
                    trans.m_wdata[beat_count[trans_idx]] = m_vif.monitor_cb.rdata;
                    trans.m_resp = axi4_resp_t'(m_vif.monitor_cb.rresp);

                    `uvm_info(get_type_name(), $sformatf("R Channel: Beat %0d, RLAST=%b",
                        beat_count[trans_idx], m_vif.monitor_cb.rlast), UVM_HIGH)

                    if (m_vif.monitor_cb.rlast) begin
                        // Calculate latency
                        latency = m_cycle_count - start_cycle;

                        // Update statistics
                        update_rd_latency_stats(latency, trans.m_id);

                        // Update bandwidth
                        m_bw_stats.total_bytes += trans.get_transfer_size_bytes();

                        `uvm_info(get_type_name(), $sformatf(
                            "Read Complete: ID=%0d, ADDR=0x%08h, RESP=%s, Latency=%0d cycles",
                            trans.m_id, trans.m_addr, trans.m_resp.name(), latency), UVM_MEDIUM)

                        // Send to analysis port
                        m_ap.write(trans);

                        // Remove from queue
                        m_rd_trans_q.delete(trans_idx);
                        m_rd_timeout_q.delete(trans_idx);
                        beat_count.delete(trans_idx);
                    end else begin
                        beat_count[trans_idx]++;
                    end
                end else begin
                    `uvm_warning(get_type_name(), $sformatf(
                        "R data received with unknown RID=%0d", m_vif.monitor_cb.rid))
                end
            end
        end
    endtask

    // Count cycles
    task count_cycles();
        forever begin
            @(posedge m_vif.ACLK);
            if (m_vif.ARESETn) begin
                m_cycle_count++;
            end else begin
                m_cycle_count = 0;
            end
        end
    endtask

    // Check for timeouts
    task check_timeouts();
        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) continue;

            // Check write timeouts
            for (int i = 0; i < m_wr_timeout_q.size(); i++) begin
                if ((m_cycle_count - m_wr_timeout_q[i]) > m_cfg.m_wtimeout) begin
                    // Record timeout ID for statistics
                    m_wr_timeout_id_q.push_back(m_wr_trans_q[i].m_id);
                    m_wr_timeout_count++;

                    `uvm_error(get_type_name(), $sformatf(
                        "Write timeout detected! AWID=%0d, waited %0d cycles (threshold=%0d)",
                        m_wr_trans_q[i].m_id, m_cycle_count - m_wr_timeout_q[i], m_cfg.m_wtimeout))
                    // Remove timed out transaction
                    m_wr_trans_q.delete(i);
                    m_wr_timeout_q.delete(i);
                    break;
                end
            end

            // Check read timeouts
            for (int i = 0; i < m_rd_timeout_q.size(); i++) begin
                if ((m_cycle_count - m_rd_timeout_q[i]) > m_cfg.m_rtimeout) begin
                    // Record timeout ID for statistics
                    m_rd_timeout_id_q.push_back(m_rd_trans_q[i].m_id);
                    m_rd_timeout_count++;

                    `uvm_error(get_type_name(), $sformatf(
                        "Read timeout detected! ARID=%0d, waited %0d cycles (threshold=%0d)",
                        m_rd_trans_q[i].m_id, m_cycle_count - m_rd_timeout_q[i], m_cfg.m_rtimeout))
                    // Remove timed out transaction
                    m_rd_trans_q.delete(i);
                    m_rd_timeout_q.delete(i);
                    break;
                end
            end
        end
    endtask

    // Update read latency statistics
    function void update_rd_latency_stats(int latency, bit [3:0] id);
        m_rd_latency_stats.total_latency += latency;
        m_rd_latency_stats.trans_count++;

        if (latency < m_rd_latency_stats.min_latency) begin
            m_rd_latency_stats.min_latency = latency;
            m_rd_latency_stats.min_latency_id = id;
        end

        if (latency > m_rd_latency_stats.max_latency) begin
            m_rd_latency_stats.max_latency = latency;
            m_rd_latency_stats.max_latency_id = id;
        end
    endfunction

    // Update write latency statistics
    function void update_wr_latency_stats(int latency, bit [3:0] id);
        m_wr_latency_stats.total_latency += latency;
        m_wr_latency_stats.trans_count++;

        if (latency < m_wr_latency_stats.min_latency) begin
            m_wr_latency_stats.min_latency = latency;
            m_wr_latency_stats.min_latency_id = id;
        end

        if (latency > m_wr_latency_stats.max_latency) begin
            m_wr_latency_stats.max_latency = latency;
            m_wr_latency_stats.max_latency_id = id;
        end
    endfunction

    // Report phase - print statistics
    function void report_phase(uvm_phase phase);
        real avg_rd_latency;
        real avg_wr_latency;
        real bandwidth_mbps;
        real efficiency;
        real total_time_ns;

        super.report_phase(phase);

        total_time_ns = $realtime - m_start_time;  // Already in ns (timescale 1ns/1ps)

        `uvm_info(get_type_name(), "===== AXI4 Monitor Statistics =====", UVM_NONE)
        `uvm_info(get_type_name(), "-----------------------------------", UVM_NONE)

        // Read latency statistics
        if (m_rd_latency_stats.trans_count > 0) begin
            avg_rd_latency = real'(m_rd_latency_stats.total_latency) /
                             real'(m_rd_latency_stats.trans_count);
            `uvm_info(get_type_name(), "Read Latency Statistics:", UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Total Read Transactions: %0d", m_rd_latency_stats.trans_count), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Min Latency: %0d cycles (ARID=%0d)",
                m_rd_latency_stats.min_latency, m_rd_latency_stats.min_latency_id), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Max Latency: %0d cycles (ARID=%0d)",
                m_rd_latency_stats.max_latency, m_rd_latency_stats.max_latency_id), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Avg Latency: %.2f cycles", avg_rd_latency), UVM_NONE)
        end

        // Write latency statistics
        if (m_wr_latency_stats.trans_count > 0) begin
            avg_wr_latency = real'(m_wr_latency_stats.total_latency) /
                             real'(m_wr_latency_stats.trans_count);
            `uvm_info(get_type_name(), "Write Latency Statistics:", UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Total Write Transactions: %0d", m_wr_latency_stats.trans_count), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Min Latency: %0d cycles (AWID=%0d)",
                m_wr_latency_stats.min_latency, m_wr_latency_stats.min_latency_id), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Max Latency: %0d cycles (AWID=%0d)",
                m_wr_latency_stats.max_latency, m_wr_latency_stats.max_latency_id), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Avg Latency: %.2f cycles", avg_wr_latency), UVM_NONE)
        end

        // Bandwidth statistics
        if (m_bw_stats.total_bytes > 0 && total_time_ns > 0) begin
            // Calculate actual bandwidth in MB/s
            // total_time_ns is in nanoseconds, convert to seconds
            bandwidth_mbps = (real'(m_bw_stats.total_bytes) / 1024.0 / 1024.0) /
                             (total_time_ns / 1_000_000_000.0);

            // Calculate theoretical max bandwidth in MB/s
            // clock_freq_mhz * data_width_bytes = MB/s
            m_bw_stats.bandwidth_mbps = real'(m_cfg.m_clock_freq_mhz) *
                                        (real'(m_cfg.m_data_width) / 8.0);

            // Efficiency
            efficiency = (bandwidth_mbps / m_bw_stats.bandwidth_mbps) * 100.0;

            `uvm_info(get_type_name(), "Bandwidth Statistics:", UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Total Bytes Transferred: %0d", m_bw_stats.total_bytes), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Total Time: %.2f ns", total_time_ns), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Actual Bandwidth: %.2f MB/s", bandwidth_mbps), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Theoretical Max: %.2f MB/s", m_bw_stats.bandwidth_mbps), UVM_NONE)
            `uvm_info(get_type_name(), $sformatf(
                "  Bandwidth Efficiency: %.2f%%", efficiency), UVM_NONE)
        end

        // Timeout statistics
        `uvm_info(get_type_name(), "Timeout Statistics:", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "  Write Timeout Count: %0d", m_wr_timeout_count), UVM_NONE)
        if (m_wr_timeout_count > 0) begin
            `uvm_info(get_type_name(), "  Write Timeout IDs:", UVM_NONE)
            foreach (m_wr_timeout_id_q[i]) begin
                `uvm_info(get_type_name(), $sformatf(
                    "    Timeout #%0d: AWID=%0d", i+1, m_wr_timeout_id_q[i]), UVM_NONE)
            end
        end

        `uvm_info(get_type_name(), $sformatf(
            "  Read Timeout Count: %0d", m_rd_timeout_count), UVM_NONE)
        if (m_rd_timeout_count > 0) begin
            `uvm_info(get_type_name(), "  Read Timeout IDs:", UVM_NONE)
            foreach (m_rd_timeout_id_q[i]) begin
                `uvm_info(get_type_name(), $sformatf(
                    "    Timeout #%0d: ARID=%0d", i+1, m_rd_timeout_id_q[i]), UVM_NONE)
            end
        end

        `uvm_info(get_type_name(), "-----------------------------------", UVM_NONE)
    endfunction

endclass : axi4_monitor

`endif // AXI4_MONITOR_SV