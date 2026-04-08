// AXI4 Master Driver
// Drives AXI4 bus signals with support for burst splitting, unaligned transfers,
// data-before-addr mode, and timeout detection

`ifndef AXI4_MASTER_DRIVER_SV
`define AXI4_MASTER_DRIVER_SV

class axi4_master_driver extends uvm_driver #(axi4_transaction);
    `uvm_component_utils(axi4_master_driver)

    // Configuration handle
    axi4_config m_cfg;

    // Virtual interface (parameterized via macros)
    virtual axi4_interface #(`AXI4_DATA_WIDTH, `AXI4_ADDR_WIDTH, `AXI4_ID_WIDTH) m_vif;

    // Burst split transaction tracking
    local axi4_transaction m_split_trans_q[$];
    local int m_current_id;

    // Outstanding transaction counters
    local int m_aw_outstanding;
    local int m_ar_outstanding;
    local int m_w_outstanding;  // For data-before-addr mode

    // Latency tracking
    local axi4_latency_stats_t m_rd_latency_stats;
    local axi4_latency_stats_t m_wr_latency_stats;

    // Bandwidth tracking
    local axi4_bandwidth_stats_t m_bw_stats;
    local time m_start_time;

    // Timeout tracking
    local int m_wr_start_cycle[$];  // Start cycle for each write
    local int m_rd_start_cycle[$];  // Start cycle for each read
    local int m_cycle_count;

    // Semaphore for ID allocation
    local semaphore m_id_sem;

    // Mailbox for read data response
    local mailbox #(axi4_transaction) m_rd_rsp_mbox;

    // Constructor
    function new(string name = "axi4_master_driver", uvm_component parent = null);
        super.new(name, parent);
        m_id_sem = new(1);
        m_rd_rsp_mbox = new();

        // Initialize latency stats
        m_rd_latency_stats.min_latency = '1;
        m_rd_latency_stats.max_latency = 0;
        m_rd_latency_stats.total_latency = 0;
        m_rd_latency_stats.trans_count = 0;

        m_wr_latency_stats.min_latency = '1;
        m_wr_latency_stats.max_latency = 0;
        m_wr_latency_stats.total_latency = 0;
        m_wr_latency_stats.trans_count = 0;

        m_current_id = 0;
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

        // Reset signals
        reset_signals();

        fork
            // Main driver process
            drive_transactions();

            // Response handling processes
            handle_b_channel();
            handle_r_channel();

            // Cycle counter
            count_cycles();

            // Timeout checker
            check_timeouts();
        join_none
    endtask

    // Reset all signals
    task reset_signals();
        m_vif.master_cb.awid     <= '0;
        m_vif.master_cb.awaddr   <= '0;
        m_vif.master_cb.awlen    <= '0;
        m_vif.master_cb.awsize   <= '0;
        m_vif.master_cb.awburst  <= '0;
        m_vif.master_cb.awlock   <= '0;
        m_vif.master_cb.awcache  <= '0;
        m_vif.master_cb.awprot   <= '0;
        m_vif.master_cb.awqos    <= '0;
        m_vif.master_cb.awregion <= '0;
        m_vif.master_cb.awuser   <= '0;
        m_vif.master_cb.awvalid  <= '0;

        m_vif.master_cb.wdata    <= '0;
        m_vif.master_cb.wstrb    <= '0;
        m_vif.master_cb.wlast    <= '0;
        m_vif.master_cb.wuser    <= '0;
        m_vif.master_cb.wvalid   <= '0;

        m_vif.master_cb.bready   <= '0;

        m_vif.master_cb.arid     <= '0;
        m_vif.master_cb.araddr   <= '0;
        m_vif.master_cb.arlen    <= '0;
        m_vif.master_cb.arsize   <= '0;
        m_vif.master_cb.arburst  <= '0;
        m_vif.master_cb.arlock   <= '0;
        m_vif.master_cb.arcache  <= '0;
        m_vif.master_cb.arprot   <= '0;
        m_vif.master_cb.arqos    <= '0;
        m_vif.master_cb.arregion <= '0;
        m_vif.master_cb.aruser   <= '0;
        m_vif.master_cb.arvalid  <= '0;

        m_vif.master_cb.rready   <= '0;

        m_aw_outstanding = 0;
        m_ar_outstanding = 0;
        m_w_outstanding = 0;
    endtask

    // Main driver task
    task drive_transactions();
        axi4_transaction trans;
        axi4_transaction split_trans[$];

        forever begin
            // Wait for reset
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) begin
                reset_signals();
                continue;
            end

            // Get next transaction
            seq_item_port.try_next_item(trans);

            if (trans != null) begin
                `uvm_info(get_type_name(), $sformatf(
                    "Driving transaction: %s", trans.convert2string()), UVM_HIGH)

                // Check if burst needs splitting
                if (m_cfg.m_enable_burst_split && needs_splitting(trans)) begin
                    split_burst(trans, split_trans);

                    `uvm_info(get_type_name(), $sformatf(
                        "Splitting burst into %0d sub-bursts", split_trans.size()), UVM_MEDIUM)

                    // Drive each split transaction
                    foreach (split_trans[i]) begin
                        drive_single_transaction(split_trans[i]);
                    end

                    // For READ transactions, merge read data back to original transaction
                    if (trans.m_trans_type == READ) begin
                        int total_beats;
                        int beat_idx;
                        total_beats = trans.m_len + 1;
                        trans.m_wdata = new[total_beats];
                        beat_idx = 0;

                        foreach (split_trans[i]) begin
                            foreach (split_trans[i].m_wdata[j]) begin
                                trans.m_wdata[beat_idx] = split_trans[i].m_wdata[j];
                                beat_idx++;
                            end
                        end
                    end
                end else begin
                    drive_single_transaction(trans);
                end

                seq_item_port.item_done();
            end
        end
    endtask

    // Check if burst needs splitting
    function bit needs_splitting(axi4_transaction trans);
        // Split if: INCR burst with length > 16, or crosses 2KB boundary
        if (trans.m_burst == INCR) begin
            if (trans.m_len > 15) return 1;
            if (trans.crosses_2kb_boundary()) return 1;
        end
        return 0;
    endfunction

    // Split burst into multiple sub-bursts
    // For unaligned transfers, only the first sub-burst has unaligned start address
    // Subsequent sub-bursts have aligned start addresses
    task split_burst(axi4_transaction trans, ref axi4_transaction split_q[$]);
        int remaining_beats;
        int current_addr;
        int aligned_start;       // Aligned start address for beat calculation
        int beat_count_sent;     // Number of beats already sent
        int beat_size;
        int beats_this_burst;
        int max_beats_per_burst;
        int split_id;
        int bytes_this_burst;
        int next_2kb_boundary;
        int bytes_until_boundary;

        split_q.delete();
        remaining_beats = trans.m_len + 1;
        current_addr = trans.m_addr;
        // Calculate aligned start address for beat address calculation
        aligned_start = (trans.m_addr >> trans.m_size) << trans.m_size;
        beat_count_sent = 0;
        beat_size = 1 << trans.m_size;
        max_beats_per_burst = m_cfg.m_max_burst_len;

        while (remaining_beats > 0) begin
            axi4_transaction split_trans;
            split_trans = axi4_transaction::type_id::create("split_trans");
            split_trans.copy(trans);

            // Allocate unique ID for each split
            m_id_sem.get();
            split_trans.m_id = m_current_id;
            m_current_id = (m_current_id + 1) % (1 << m_cfg.m_id_width);
            m_id_sem.put();

            // For first sub-burst, use original unaligned address
            // For subsequent sub-bursts, use aligned address
            if (beat_count_sent == 0) begin
                split_trans.m_addr = current_addr;  // Original unaligned address
            end else begin
                // Calculate aligned address for subsequent sub-bursts
                split_trans.m_addr = aligned_start + beat_count_sent * beat_size;
            end

            // Calculate next 2KB boundary address
            // 2KB = 2048 bytes = 2^11
            // next_2kb_boundary = ((addr >> 11) + 1) << 11
            next_2kb_boundary = ((split_trans.m_addr >> 11) + 1) << 11;
            bytes_until_boundary = next_2kb_boundary - split_trans.m_addr;

            // Determine beats for this burst
            beats_this_burst = remaining_beats;

            // Limit by max burst length
            if (beats_this_burst > max_beats_per_burst) begin
                beats_this_burst = max_beats_per_burst;
            end

            // Limit by 2KB boundary - must not cross boundary
            bytes_this_burst = beats_this_burst * beat_size;
            if (bytes_this_burst > bytes_until_boundary) begin
                beats_this_burst = bytes_until_boundary / beat_size;
                // Ensure at least 1 beat
                if (beats_this_burst == 0) beats_this_burst = 1;
            end

            split_trans.m_len = beats_this_burst - 1;

            // Copy appropriate data for writes
            if (trans.m_trans_type == WRITE) begin
                int start_idx;
                start_idx = beat_count_sent;
                split_trans.m_wdata = new[beats_this_burst];
                split_trans.m_wstrb = new[beats_this_burst];

                for (int i = 0; i < beats_this_burst; i++) begin
                    split_trans.m_wdata[i] = trans.m_wdata[start_idx + i];
                    // Copy WSTRB from original transaction for all beats
                    // WSTRB has already been correctly calculated in post_randomize()
                    // based on transfer size and address offset
                    split_trans.m_wstrb[i] = trans.m_wstrb[start_idx + i];
                end
            end

            split_q.push_back(split_trans);

            // Update for next iteration
            remaining_beats -= beats_this_burst;
            beat_count_sent += beats_this_burst;
            current_addr = aligned_start + beat_count_sent * beat_size;
        end
    endtask

    // Drive a single transaction
    task drive_single_transaction(axi4_transaction trans);
        fork
            if (trans.m_trans_type == WRITE) begin
                if (m_cfg.m_support_data_before_addr) begin
                    fork
                        drive_write_data(trans);
                        drive_write_addr(trans);
                    join
                end else begin
                    drive_write_addr(trans);
                    drive_write_data(trans);
                end
            end else begin
                drive_read_transaction(trans);
            end
        join

        // For read transactions, wait for read data to be collected
        if (trans.m_trans_type == READ) begin
            axi4_transaction rsp_trans;
            m_rd_rsp_mbox.get(rsp_trans);
            // Copy read data to original transaction
            trans.m_wdata = rsp_trans.m_wdata;
            trans.m_resp = rsp_trans.m_resp;
        end

        // Wait for transaction interval
        if (m_cfg.m_trans_interval > 0) begin
            repeat(m_cfg.m_trans_interval) @(posedge m_vif.ACLK);
        end
    endtask

    // Drive write address channel
    task drive_write_addr(axi4_transaction trans);
        // Wait for outstanding limit
        while (m_aw_outstanding >= m_cfg.m_max_outstanding) begin
            @(posedge m_vif.ACLK);
        end

        // Calculate WSTRB for unaligned first beat only
        // Per AXI4 protocol: only the first beat of an unaligned burst has special WSTRB
        // All subsequent beats (including first beats of split sub-bursts) have aligned addresses
        if (trans.is_unaligned()) begin
            trans.m_wstrb[0] = trans.calc_unaligned_wstrb(
                trans.m_addr, trans.m_size, trans.m_data_width);
        end

        // Drive address channel signals
        m_vif.master_cb.awid     <= trans.m_id;
        m_vif.master_cb.awaddr   <= trans.m_addr;
        m_vif.master_cb.awlen    <= trans.m_len;
        m_vif.master_cb.awsize   <= trans.m_size;
        m_vif.master_cb.awburst  <= trans.m_burst;
        m_vif.master_cb.awlock   <= trans.m_lock;
        m_vif.master_cb.awcache  <= trans.m_cache;
        m_vif.master_cb.awprot   <= {trans.m_prot.privilege, trans.m_prot.secure, trans.m_prot.data};
        m_vif.master_cb.awqos    <= trans.m_qos;
        m_vif.master_cb.awregion <= trans.m_region;
        m_vif.master_cb.awuser   <= trans.m_user;
        m_vif.master_cb.awvalid  <= 1;

        m_aw_outstanding++;

        `uvm_info(get_type_name(), $sformatf(
            "Driving AW: ID=%0d, ADDR=0x%08h, LEN=%0d, SIZE=%0d",
            trans.m_id, trans.m_addr, trans.m_len, trans.m_size), UVM_HIGH)

        // Wait for handshake (awvalid must remain stable until awready asserted)
        @(posedge m_vif.ACLK);
        while (!(m_vif.master_cb.awready)) begin
            @(posedge m_vif.ACLK);
        end

        // Track start cycle for latency
        m_wr_start_cycle.push_back(m_cycle_count);

        // De-assert awvalid after handshake completes
        m_vif.master_cb.awvalid <= 0;
    endtask

    // Drive write data channel
    task drive_write_data(axi4_transaction trans);
        int beat_count;
        int beats_to_send;

        beat_count = 0;
        beats_to_send = trans.m_len + 1;

        // Wait for data-before-addr outstanding limit
        if (m_cfg.m_support_data_before_addr) begin
            while (m_w_outstanding >= m_cfg.m_data_before_addr_osd) begin
                @(posedge m_vif.ACLK);
            end
            m_w_outstanding++;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Driving W data: %0d beats", beats_to_send), UVM_HIGH)

        while (beat_count < beats_to_send) begin
            // Track if this is the last beat locally
            bit is_last_beat;
            is_last_beat = (beat_count == beats_to_send - 1);

            // Drive write data
            m_vif.master_cb.wdata  <= trans.m_wdata[beat_count];
            m_vif.master_cb.wstrb  <= trans.m_wstrb[beat_count];
            m_vif.master_cb.wlast  <= is_last_beat;  // 只在最后1 beat拉高
            m_vif.master_cb.wuser  <= trans.m_user;
            m_vif.master_cb.wvalid <= 1;

            `uvm_info(get_type_name(), $sformatf(
                "Driving W beat %0d/%0d, WLAST=%b",
                beat_count + 1, beats_to_send, is_last_beat), UVM_HIGH)

            // Wait for handshake (wvalid must remain stable until wready asserted)
            @(posedge m_vif.ACLK);
            while (!(m_vif.master_cb.wready)) begin
                @(posedge m_vif.ACLK);
            end

            beat_count++;
        end

        // 传输结束后清零信号
        m_vif.master_cb.wvalid <= 0;
        m_vif.master_cb.wlast  <= 0;
    endtask

    // Handle write response channel
    task handle_b_channel();
        int latency;

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) continue;

            // Assert BREADY
            m_vif.master_cb.bready <= 1;

            if (m_vif.master_cb.bvalid) begin
                // Calculate latency
                if (m_wr_start_cycle.size() > 0) begin
                    latency = m_cycle_count - m_wr_start_cycle.pop_front();
                    update_wr_latency_stats(latency, m_vif.master_cb.bid);
                end

                m_aw_outstanding--;
                if (m_cfg.m_support_data_before_addr && m_w_outstanding > 0) begin
                    m_w_outstanding--;
                end

                // Update bandwidth
                m_bw_stats.total_bytes += (m_vif.master_cb.bid + 1) * 4;  // Approximate

                `uvm_info(get_type_name(), $sformatf(
                    "B response received: BID=%0d, BRESP=%0d, Latency=%0d",
                    m_vif.master_cb.bid, m_vif.master_cb.bresp, latency), UVM_HIGH)
            end
        end
    endtask

    // Drive read transaction
    task drive_read_transaction(axi4_transaction trans);
        // Wait for outstanding limit
        while (m_ar_outstanding >= m_cfg.m_max_outstanding) begin
            @(posedge m_vif.ACLK);
        end

        // Drive address channel signals
        m_vif.master_cb.arid     <= trans.m_id;
        m_vif.master_cb.araddr   <= trans.m_addr;
        m_vif.master_cb.arlen    <= trans.m_len;
        m_vif.master_cb.arsize   <= trans.m_size;
        m_vif.master_cb.arburst  <= trans.m_burst;
        m_vif.master_cb.arlock   <= trans.m_lock;
        m_vif.master_cb.arcache  <= trans.m_cache;
        m_vif.master_cb.arprot   <= {trans.m_prot.privilege, trans.m_prot.secure, trans.m_prot.data};
        m_vif.master_cb.arqos    <= trans.m_qos;
        m_vif.master_cb.arregion <= trans.m_region;
        m_vif.master_cb.aruser   <= trans.m_user;
        m_vif.master_cb.arvalid  <= 1;

        m_ar_outstanding++;

        `uvm_info(get_type_name(), $sformatf(
            "Driving AR: ID=%0d, ADDR=0x%08h, LEN=%0d, SIZE=%0d",
            trans.m_id, trans.m_addr, trans.m_len, trans.m_size), UVM_HIGH)

        // Wait for handshake (arvalid must remain stable until arready asserted)
        @(posedge m_vif.ACLK);
        while (!(m_vif.master_cb.arready)) begin
            @(posedge m_vif.ACLK);
        end

        // Track start cycle for latency
        m_rd_start_cycle.push_back(m_cycle_count);

        // De-assert arvalid after handshake completes
        m_vif.master_cb.arvalid <= 0;
    endtask

    // Handle read data channel
    task handle_r_channel();
        int beat_count;
        int latency;
        axi4_transaction rd_trans;
        bit [255:0] rdata_queue[$];

        forever begin
            @(posedge m_vif.ACLK);
            if (!m_vif.ARESETn) continue;

            // Assert RREADY
            m_vif.master_cb.rready <= 1;

            if (m_vif.master_cb.rvalid) begin
                `uvm_info(get_type_name(), $sformatf(
                    "R data received: RID=%0d, RDATA=0x%08h, RLAST=%b",
                    m_vif.master_cb.rid, m_vif.master_cb.rdata, m_vif.master_cb.rlast), UVM_HIGH)

                // Collect read data
                rdata_queue.push_back(m_vif.master_cb.rdata);

                if (m_vif.master_cb.rlast) begin
                    m_ar_outstanding--;

                    // Create response transaction
                    rd_trans = axi4_transaction::type_id::create("rd_trans");
                    rd_trans.m_wdata = new[rdata_queue.size()];
                    foreach (rdata_queue[i]) begin
                        rd_trans.m_wdata[i] = rdata_queue[i];
                    end
                    rd_trans.m_resp = axi4_resp_t'(m_vif.master_cb.rresp);

                    // Send to mailbox
                    m_rd_rsp_mbox.put(rd_trans);

                    // Clear queue
                    rdata_queue.delete();

                    // Calculate latency
                    if (m_rd_start_cycle.size() > 0) begin
                        latency = m_cycle_count - m_rd_start_cycle.pop_front();
                        update_rd_latency_stats(latency, m_vif.master_cb.rid);
                    end

                    // Update bandwidth
                    m_bw_stats.total_bytes += (m_vif.master_cb.rid + 1) * 4;  // Approximate
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

            // Check write timeouts (waiting for BVALID)
            for (int i = 0; i < m_wr_start_cycle.size(); i++) begin
                if ((m_cycle_count - m_wr_start_cycle[i]) > m_cfg.m_wtimeout) begin
                    `uvm_error(get_type_name(), $sformatf(
                        "Write timeout! Waiting for BVALID, elapsed=%0d cycles (threshold=%0d)",
                        m_cycle_count - m_wr_start_cycle[i], m_cfg.m_wtimeout))
                    m_wr_start_cycle.delete(i);
                    break;
                end
            end

            // Check read timeouts (waiting for RLAST)
            for (int i = 0; i < m_rd_start_cycle.size(); i++) begin
                if ((m_cycle_count - m_rd_start_cycle[i]) > m_cfg.m_rtimeout) begin
                    `uvm_error(get_type_name(), $sformatf(
                        "Read timeout! Waiting for RLAST, elapsed=%0d cycles (threshold=%0d)",
                        m_cycle_count - m_rd_start_cycle[i], m_cfg.m_rtimeout))
                    m_rd_start_cycle.delete(i);
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

        total_time_ns = ($realtime - m_start_time) / 1000.0;

        `uvm_info(get_type_name(), "===== AXI4 Driver Statistics =====", UVM_NONE)
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
            bandwidth_mbps = (real'(m_bw_stats.total_bytes) * 8.0) /
                             (total_time_ns / 1000.0) / 1.0e6;

            m_bw_stats.bandwidth_mbps = m_cfg.m_clock_freq_mhz * m_cfg.m_data_width;
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

        `uvm_info(get_type_name(), "-----------------------------------", UVM_NONE)
    endfunction

endclass : axi4_master_driver

`endif // AXI4_MASTER_DRIVER_SV