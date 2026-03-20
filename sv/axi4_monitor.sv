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

            if (m_vif.monitor_cb.AWVALID && m_vif.monitor_cb.AWREADY) begin
                // Create new write transaction
                trans = axi4_transaction::type_id::create("wr_trans");
                trans.m_trans_type = WRITE;
                trans.m_id         = m_vif.monitor_cb.AWID;
                trans.m_addr       = m_vif.monitor_cb.AWADDR;
                trans.m_len        = m_vif.monitor_cb.AWLEN;
                trans.m_size       = m_vif.monitor_cb.AWSIZE;
                trans.m_burst      = axi4_burst_t'(m_vif.monitor_cb.AWBURST);
                trans.m_lock       = m_vif.monitor_cb.AWLOCK;
                trans.m_cache      = m_vif.monitor_cb.AWCACHE;
                trans.m_qos        = m_vif.monitor_cb.AWQOS;
                trans.m_region     = m_vif.monitor_cb.AWREGION;
                trans.m_user       = m_vif.monitor_cb.AWUSER;

                // Initialize data arrays
                trans.m_wdata = new[trans.m_len + 1];
                trans.m_wstrb = new[trans.m_len + 1];

                // Store transaction with cycle count for latency calculation
                trans.m_data_width = m_cfg.m_data_width;
                trans.m_addr_width = m_cfg.m_addr_width;
                trans.m_id_width   = m_cfg.m_id_width;

                m_wr_trans_q.push_back(trans);

                // Track for timeout
                m_wr_timeout_q.push_back(m_cycle_count);

                `uvm_info(get_type_name(), $sformatf("AW Channel: ID=%0d, ADDR=0x%08h, LEN=%0d",
                    trans.m_id, trans.m_addr, trans.m_len), UVM_HIGH)
            end
        end
    endtask

    // Monitor write data channel
    task monitor_w_channel();
        int beat_count[$];
        int trans_idx;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                beat_count.delete();
                continue;
            end

            if (m_vif.monitor_cb.WVALID && m_vif.monitor_cb.WREADY) begin
                // Find matching transaction (by order, could be enhanced with WID if available)
                if (m_wr_trans_q.size() > 0) begin
                    // For now, assume in-order write data
                    // In real AXI4, WID was removed, data must match address order
                    trans_idx = 0;

                    // Store write data
                    m_wr_trans_q[trans_idx].m_wdata[beat_count[trans_idx]] = m_vif.monitor_cb.WDATA;
                    m_wr_trans_q[trans_idx].m_wstrb[beat_count[trans_idx]] = m_vif.monitor_cb.WSTRB;

                    `uvm_info(get_type_name(), $sformatf("W Channel: Beat %0d, WLAST=%b",
                        beat_count[trans_idx], m_vif.monitor_cb.WLAST), UVM_HIGH)

                    if (m_vif.monitor_cb.WLAST) begin
                        beat_count[trans_idx] = 0;
                    end else begin
                        beat_count[trans_idx]++;
                    end
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

            if (m_vif.monitor_cb.BVALID && m_vif.monitor_cb.BREADY) begin
                // Find matching transaction by BID
                trans = null;
                for (int i = 0; i < m_wr_trans_q.size(); i++) begin
                    if (m_wr_trans_q[i].m_id == m_vif.monitor_cb.BID) begin
                        trans = m_wr_trans_q[i];
                        trans_idx = i;
                        start_cycle = m_wr_timeout_q[i];
                        break;
                    end
                end

                if (trans != null) begin
                    trans.m_resp = axi4_resp_t'(m_vif.monitor_cb.BRESP);

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

                    // Remove from queue
                    m_wr_trans_q.delete(trans_idx);
                    m_wr_timeout_q.delete(trans_idx);
                end else begin
                    `uvm_warning(get_type_name(), $sformatf(
                        "B response received with unknown BID=%0d", m_vif.monitor_cb.BID))
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

            if (m_vif.monitor_cb.ARVALID && m_vif.monitor_cb.ARREADY) begin
                // Create new read transaction
                trans = axi4_transaction::type_id::create("rd_trans");
                trans.m_trans_type = READ;
                trans.m_id         = m_vif.monitor_cb.ARID;
                trans.m_addr       = m_vif.monitor_cb.ARADDR;
                trans.m_len        = m_vif.monitor_cb.ARLEN;
                trans.m_size       = m_vif.monitor_cb.ARSIZE;
                trans.m_burst      = axi4_burst_t'(m_vif.monitor_cb.ARBURST);
                trans.m_lock       = m_vif.monitor_cb.ARLOCK;
                trans.m_cache      = m_vif.monitor_cb.ARCACHE;
                trans.m_qos        = m_vif.monitor_cb.ARQOS;
                trans.m_region     = m_vif.monitor_cb.ARREGION;
                trans.m_user       = m_vif.monitor_cb.ARUSER;

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

            if (m_vif.monitor_cb.RVALID && m_vif.monitor_cb.RREADY) begin
                // Find matching transaction by RID
                trans = null;
                for (int i = 0; i < m_rd_trans_q.size(); i++) begin
                    if (m_rd_trans_q[i].m_id == m_vif.monitor_cb.RID) begin
                        trans = m_rd_trans_q[i];
                        trans_idx = i;
                        start_cycle = m_rd_timeout_q[i];
                        break;
                    end
                end

                if (trans != null) begin
                    // Store read data
                    trans.m_wdata[beat_count[trans_idx]] = m_vif.monitor_cb.RDATA;
                    trans.m_resp = axi4_resp_t'(m_vif.monitor_cb.RRESP);

                    `uvm_info(get_type_name(), $sformatf("R Channel: Beat %0d, RLAST=%b",
                        beat_count[trans_idx], m_vif.monitor_cb.RLAST), UVM_HIGH)

                    if (m_vif.monitor_cb.RLAST) begin
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
                        "R data received with unknown RID=%0d", m_vif.monitor_cb.RID))
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

        total_time_ns = ($realtime - m_start_time) / 1000.0;  // Convert to ns

        `uvm_info(get_type_name(), "===== AXI4 Monitor Statistics =====", UVM_NONE)
        `uvm_info(get_type_name(), "-----------------------------------", UVM_NONE)

        // Read latency statistics
        if (m_rd_latency_stats.trans_count > 0) begin
            avg_rd_latency = real'(m_rd_latency_stats.total_latency) /
                             real'(m_rd_latency_stats.trans_count);
            `uvm_info(get_type_name(), $sformatf(
                "Read Latency Statistics:", UVM_NONE), UVM_NONE)
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
            `uvm_info(get_type_name(), $sformatf(
                "Write Latency Statistics:", UVM_NONE), UVM_NONE)
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
            // Bandwidth in MB/s
            bandwidth_mbps = (real'(m_bw_stats.total_bytes) * 8.0) /
                             (total_time_ns / 1000.0) / 1.0e6;

            // Theoretical max bandwidth
            m_bw_stats.bandwidth_mbps = m_cfg.m_clock_freq_mhz * m_cfg.m_data_width;

            // Efficiency
            efficiency = (bandwidth_mbps / m_bw_stats.bandwidth_mbps) * 100.0;

            `uvm_info(get_type_name(), $sformatf(
                "Bandwidth Statistics:", UVM_NONE), UVM_NONE)
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

        `uvm_info(get_type_name(), "-----------------------------------", UVM_NONE)
    endfunction

endclass : axi4_monitor

`endif // AXI4_MONITOR_SV