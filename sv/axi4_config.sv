// AXI4 Configuration Object
// Contains all VIP configuration parameters

`ifndef AXI4_CONFIG_SV
`define AXI4_CONFIG_SV

// AXI4 System Configuration (nested configuration)
class axi4_system_config extends uvm_object;
    `uvm_object_utils(axi4_system_config)

    // Slave overlapping address configuration
    bit allow_slaves_with_overlapping_addr = 0;

    // Watchdog timeout configuration
    int awready_watchdog_timeout = 0;  // 0 means disabled
    int arready_watchdog_timeout = 0;  // 0 means disabled

    // Master configuration array
    // Each master can have its own settings
    bit zero_delay_enable;

    // Constructor
    function new(string name = "axi4_system_config");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("AXI4 System Config:\n");
        s = {s, $sformatf("  Allow Slaves Overlapping Addr: %s\n",
            allow_slaves_with_overlapping_addr ? "Yes" : "No")};
        s = {s, $sformatf("  AWREADY Watchdog Timeout: %0d\n", awready_watchdog_timeout)};
        s = {s, $sformatf("  ARREADY Watchdog Timeout: %0d\n", arready_watchdog_timeout)};
        return s;
    endfunction

endclass : axi4_system_config

// AXI4 Master Environment Configuration
class axi4_config extends uvm_object;
    `uvm_object_utils(axi4_config)

    // Slave configuration
    bit use_slave_with_overlapping_addr = 0;

    // Master/Slave count
    int num_masters = 1;
    int num_slaves = 0;

    // Slave active mode
    bit slave_is_active = 1;

    // AXI4 enable flag
    bit axi4_en = 1;

    // Performance monitor
    bit enable_perf_mon = 0;

    // Per-master configuration arrays (indexed by master ID)
    int master_addr_width[$];     // Address width per master
    int master_data_width[$];     // Data width per master
    int master_id_width[$];       // ID width per master

    // User signal enables per master
    bit ruser_enable[$];          // RUSER signal enable
    bit aruser_enable[$];         // ARUSER signal enable
    bit awuser_enable[$];         // AWUSER signal enable

    // Outstanding transaction limits per master
    int max_read_outstanding[$];   // Max pending read transactions
    int max_write_outstanding[$];  // Max pending write transactions

    // Clock frequency for statistics calculation (in MHz)
    real clk_freq_mhz = 100.0;

    // Legacy compatibility parameters (single master)
    int m_data_width = `AXI4_DATA_WIDTH;
    int m_addr_width = `AXI4_ADDR_WIDTH;
    int m_id_width = `AXI4_ID_WIDTH;

    // Timing parameters
    int m_max_outstanding = 8;         // Max pending transactions
    int m_trans_interval = 0;          // Cycles between transactions

    // Data before address configuration
    bit m_support_data_before_addr = 0;  // Enable data-before-addr mode
    int m_data_before_addr_osd = 4;       // Max outstanding data before addr

    // Timeout configuration (in clock cycles)
    int m_wtimeout = 1000;  // Write timeout threshold
    int m_rtimeout = 1000;  // Read timeout threshold

    // Legacy clock frequency parameter (alias for clk_freq_mhz)
    real m_clock_freq_mhz;

    // Agent configuration
    bit m_is_active = 1;              // Active or passive agent
    bit m_has_coverage = 1;           // Enable coverage collection
    bit m_has_scoreboard = 1;         // Enable scoreboard

    // Master-specific configuration
    bit m_check_protocol = 1;         // Enable protocol assertions

    // Burst split configuration
    bit m_enable_burst_split = 1;     // Enable burst splitting
    int m_max_burst_len = 32;         // Max burst length after split

    // Virtual interface (parameterized via macros)
    virtual axi4_interface #(`AXI4_DATA_WIDTH, `AXI4_ADDR_WIDTH, `AXI4_ID_WIDTH) m_vif;

    // Nested system configuration
    axi4_system_config u_axi_system_cfg;

    // Constructor
    function new(string name = "axi4_config");
        super.new(name);
        u_axi_system_cfg = axi4_system_config::type_id::create("u_axi_system_cfg");
        m_clock_freq_mhz = clk_freq_mhz;
    endfunction

    // Set AXI system configuration (called after all parameters are set)
    function void set_axi_system_cfg();
        // Propagate configuration to system config
        // This can be extended to configure interconnect, slaves, etc.
        `uvm_info(get_type_name(), "AXI system configuration set", UVM_HIGH)
    endfunction

    // Initialize per-master configuration arrays
    function void init_master_config(int num_mst);
        master_addr_width.delete();
        master_data_width.delete();
        master_id_width.delete();
        ruser_enable.delete();
        aruser_enable.delete();
        awuser_enable.delete();
        max_read_outstanding.delete();
        max_write_outstanding.delete();

        for (int i = 0; i < num_mst; i++) begin
            master_addr_width.push_back(m_addr_width);
            master_data_width.push_back(m_data_width);
            master_id_width.push_back(m_id_width);
            ruser_enable.push_back(0);
            aruser_enable.push_back(0);
            awuser_enable.push_back(0);
            max_read_outstanding.push_back(m_max_outstanding);
            max_write_outstanding.push_back(m_max_outstanding);
        end
    endfunction

    // Get master configuration by index
    function void get_master_config(int idx, output int addr_w, output int data_w, output int id_w);
        if (idx < master_addr_width.size()) begin
            addr_w = master_addr_width[idx];
            data_w = master_data_width[idx];
            id_w = master_id_width[idx];
        end else begin
            addr_w = m_addr_width;
            data_w = m_data_width;
            id_w = m_id_width;
        end
    endfunction

    // Set master configuration by index
    function void set_master_config(int idx, int addr_w, int data_w, int id_w);
        // Resize arrays if needed
        while (master_addr_width.size() <= idx) begin
            master_addr_width.push_back(m_addr_width);
            master_data_width.push_back(m_data_width);
            master_id_width.push_back(m_id_width);
            ruser_enable.push_back(0);
            aruser_enable.push_back(0);
            awuser_enable.push_back(0);
            max_read_outstanding.push_back(m_max_outstanding);
            max_write_outstanding.push_back(m_max_outstanding);
        end

        master_addr_width[idx] = addr_w;
        master_data_width[idx] = data_w;
        master_id_width[idx] = id_w;
    endfunction

    // Set outstanding limits for a master
    function void set_outstanding_config(int idx, int rd_osd, int wr_osd);
        while (max_read_outstanding.size() <= idx) begin
            max_read_outstanding.push_back(m_max_outstanding);
            max_write_outstanding.push_back(m_max_outstanding);
        end
        max_read_outstanding[idx] = rd_osd;
        max_write_outstanding[idx] = wr_osd;
    endfunction

    // Set user signal enables for a master
    function void set_user_enable_config(int idx, bit ruser_en, bit aruser_en, bit awuser_en);
        while (ruser_enable.size() <= idx) begin
            ruser_enable.push_back(0);
            aruser_enable.push_back(0);
            awuser_enable.push_back(0);
        end
        ruser_enable[idx] = ruser_en;
        aruser_enable[idx] = aruser_en;
        awuser_enable[idx] = awuser_en;
    endfunction

    // Convert to string
    function string convert2string();
        string s;
        s = $sformatf("AXI4 Config:\n");
        s = {s, $sformatf("  Num Masters: %0d\n", num_masters)};
        s = {s, $sformatf("  Num Slaves: %0d\n", num_slaves)};
        s = {s, $sformatf("  Slave Is Active: %s\n", slave_is_active ? "Yes" : "No")};
        s = {s, $sformatf("  AXI4 Enable: %s\n", axi4_en ? "Yes" : "No")};
        s = {s, $sformatf("  Use Slave Overlapping Addr: %s\n",
            use_slave_with_overlapping_addr ? "Yes" : "No")};
        s = {s, $sformatf("  Enable Perf Mon: %s\n", enable_perf_mon ? "Yes" : "No")};
        s = {s, $sformatf("  Clock Freq: %0.2f MHz\n", clk_freq_mhz)};

        // Per-master configuration
        foreach (master_addr_width[i]) begin
            s = {s, $sformatf("  Master[%0d]: AddrW=%0d, DataW=%0d, IdW=%0d\n",
                i, master_addr_width[i], master_data_width[i], master_id_width[i])};
            s = {s, $sformatf("           RD_OSD=%0d, WR_OSD=%0d\n",
                max_read_outstanding[i], max_write_outstanding[i])};
        end

        s = {s, u_axi_system_cfg.convert2string()};

        // Legacy parameters
        s = {s, $sformatf("  Legacy Data Width: %0d\n", m_data_width)};
        s = {s, $sformatf("  Legacy Addr Width: %0d\n", m_addr_width)};
        s = {s, $sformatf("  Legacy ID Width: %0d\n", m_id_width)};
        s = {s, $sformatf("  Max Outstanding: %0d\n", m_max_outstanding)};
        s = {s, $sformatf("  Trans Interval: %0d\n", m_trans_interval)};
        s = {s, $sformatf("  Data Before Addr: %s\n", m_support_data_before_addr ? "Enabled" : "Disabled")};
        s = {s, $sformatf("  Write Timeout: %0d\n", m_wtimeout)};
        s = {s, $sformatf("  Read Timeout: %0d\n", m_rtimeout)};
        s = {s, $sformatf("  Is Active: %s\n", m_is_active ? "Yes" : "No")};
        s = {s, $sformatf("  Has Coverage: %s\n", m_has_coverage ? "Yes" : "No")};
        s = {s, $sformatf("  Burst Split: %s\n", m_enable_burst_split ? "Enabled" : "Disabled")};
        return s;
    endfunction

    // Do print
    function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_field("Num Masters", num_masters, 32);
        printer.print_field("Num Slaves", num_slaves, 32);
        printer.print_field("Slave Is Active", slave_is_active, 1);
        printer.print_field("AXI4 Enable", axi4_en, 1);
        printer.print_field("Enable Perf Mon", enable_perf_mon, 1);
        printer.print_field("Data Width", m_data_width, 32);
        printer.print_field("Addr Width", m_addr_width, 32);
        printer.print_field("ID Width", m_id_width, 32);
        printer.print_field("Max Outstanding", m_max_outstanding, 32);
        printer.print_field("Trans Interval", m_trans_interval, 32);
        printer.print_field("Data Before Addr", m_support_data_before_addr, 1);
        printer.print_field("Data Before Addr OSD", m_data_before_addr_osd, 32);
        printer.print_field("Write Timeout", m_wtimeout, 32);
        printer.print_field("Read Timeout", m_rtimeout, 32);
        printer.print_field("Is Active", m_is_active, 1);
        printer.print_field("Has Coverage", m_has_coverage, 1);
        printer.print_field("Burst Split", m_enable_burst_split, 1);
    endfunction

endclass : axi4_config

`endif // AXI4_CONFIG_SV