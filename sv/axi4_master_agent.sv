// AXI4 Master Agent
// Container for driver, sequencer, and monitor

`ifndef AXI4_MASTER_AGENT_SV
`define AXI4_MASTER_AGENT_SV

class axi4_master_agent extends uvm_agent;
    `uvm_component_utils(axi4_master_agent)

    // Configuration handle
    axi4_config m_cfg;

    // Components
    axi4_master_driver m_driver;
    axi4_sequencer     m_sequencer;
    axi4_monitor       m_monitor;

    // Analysis port for monitor output (pass-through)
    uvm_analysis_port #(axi4_transaction) m_ap;

    // Constructor
    function new(string name = "axi4_master_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get configuration
        if (!uvm_config_db#(axi4_config)::get(this, "", "m_cfg", m_cfg)) begin
            `uvm_warning(get_type_name(), "Configuration not found, using defaults")
            m_cfg = axi4_config::type_id::create("m_cfg");
        end

        // Always create monitor
        m_monitor = axi4_monitor::type_id::create("m_monitor", this);
        `uvm_info(get_type_name(), "Created monitor", UVM_HIGH)

        // Create driver and sequencer only in active mode
        if (m_cfg.m_is_active) begin
            m_driver = axi4_master_driver::type_id::create("m_driver", this);
            m_sequencer = axi4_sequencer::type_id::create("m_sequencer", this);
            `uvm_info(get_type_name(), "Created driver and sequencer (active mode)", UVM_HIGH)
        end else begin
            `uvm_info(get_type_name(), "Agent in passive mode - no driver/sequencer", UVM_HIGH)
        end

        // Create analysis port
        m_ap = new("m_ap", this);
    endfunction

    // Connect phase
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect monitor analysis port to agent's analysis port
        m_monitor.m_ap.connect(m_ap);

        // Connect driver and sequencer in active mode
        if (m_cfg.m_is_active) begin
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
            `uvm_info(get_type_name(), "Connected driver to sequencer", UVM_HIGH)
        end
    endfunction

    // Get sequencer handle (for virtual sequence use)
    function uvm_sequencer_base get_sequencer();
        if (m_cfg.m_is_active) begin
            return m_sequencer;
        end else begin
            `uvm_warning(get_type_name(), "Cannot get sequencer in passive mode")
            return null;
        end
    endfunction

    // Report phase
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "Agent configuration: Active=%s, HasCoverage=%s",
            m_cfg.m_is_active ? "Yes" : "No",
            m_cfg.m_has_coverage ? "Yes" : "No"), UVM_HIGH)
    endfunction

endclass : axi4_master_agent

`endif // AXI4_MASTER_AGENT_SV