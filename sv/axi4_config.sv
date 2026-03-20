// AXI4 Configuration Object
// Contains all VIP configuration parameters

`ifndef AXI4_CONFIG_SV
`define AXI4_CONFIG_SV

class axi4_config extends uvm_object;
    `uvm_object_utils(axi4_config)

    // Bus width parameters
    int m_data_width = 32;
    int m_addr_width = 32;
    int m_id_width = 4;

    // Timing parameters
    int m_max_outstanding = 8;         // Max pending transactions
    int m_trans_interval = 0;          // Cycles between transactions

    // Data before address configuration
    bit m_support_data_before_addr = 0;  // Enable data-before-addr mode
    int m_data_before_addr_osd = 4;       // Max outstanding data before addr

    // Timeout configuration (in clock cycles)
    int m_wtimeout = 1000;  // Write timeout threshold
    int m_rtimeout = 1000;  // Read timeout threshold

    // Clock frequency for statistics calculation (in MHz)
    real m_clock_freq_mhz = 100.0;

    // Agent configuration
    bit m_is_active = 1;              // Active or passive agent
    bit m_has_coverage = 1;           // Enable coverage collection
    bit m_has_scoreboard = 1;         // Enable scoreboard

    // Master-specific configuration
    bit m_check_protocol = 1;         // Enable protocol assertions

    // Burst split configuration
    bit m_enable_burst_split = 1;     // Enable burst splitting
    int m_max_burst_len = 32;          // Max burst length after split

    // Virtual interface (parameterized)
    virtual axi4_interface #(32, 32, 4) m_vif;

    // Constructor
    function new(string name = "axi4_config");
        super.new(name);
    endfunction

    // Convert to string
    function string convert2string();
        string s;
        s = $sformatf("AXI4 Config:\n");
        s = {s, $sformatf("  Data Width: %0d\n", m_data_width)};
        s = {s, $sformatf("  Addr Width: %0d\n", m_addr_width)};
        s = {s, $sformatf("  ID Width: %0d\n", m_id_width)};
        s = {s, $sformatf("  Max Outstanding: %0d\n", m_max_outstanding)};
        s = {s, $sformatf("  Trans Interval: %0d\n", m_trans_interval)};
        s = {s, $sformatf("  Data Before Addr: %s\n", m_support_data_before_addr ? "Enabled" : "Disabled")};
        s = {s, $sformatf("  Data Before Addr OSD: %0d\n", m_data_before_addr_osd)};
        s = {s, $sformatf("  Write Timeout: %0d\n", m_wtimeout)};
        s = {s, $sformatf("  Read Timeout: %0d\n", m_rtimeout)};
        s = {s, $sformatf("  Clock Freq: %0.2f MHz\n", m_clock_freq_mhz)};
        s = {s, $sformatf("  Is Active: %s\n", m_is_active ? "Yes" : "No")};
        s = {s, $sformatf("  Has Coverage: %s\n", m_has_coverage ? "Yes" : "No")};
        s = {s, $sformatf("  Burst Split: %s\n", m_enable_burst_split ? "Enabled" : "Disabled")};
        return s;
    endfunction

    // Do print
    function void do_print(uvm_printer printer);
        super.do_print(printer);
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