// AXI4 Environment
// Top-level container for the VIP

`ifndef AXI4_ENV_SV
`define AXI4_ENV_SV

class axi4_env extends uvm_env;
    `uvm_component_utils(axi4_env)

    // Configuration handle
    axi4_config m_cfg;

    // Components
    axi4_master_agent m_master_agent;

    // Analysis ports/exports
    uvm_analysis_port #(axi4_transaction) m_ap;

    // Constructor
    function new(string name = "axi4_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Get configuration
        if (!uvm_config_db#(axi4_config)::get(this, "", "m_cfg", m_cfg)) begin
            `uvm_warning(get_type_name(), "Configuration not found, creating default")
            m_cfg = axi4_config::type_id::create("m_cfg");
        end

        // Create master agent
        m_master_agent = axi4_master_agent::type_id::create("m_master_agent", this);

        // Create analysis port
        m_ap = new("m_ap", this);

        `uvm_info(get_type_name(), "Environment built successfully", UVM_HIGH)
    endfunction

    // Connect phase
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Connect agent analysis port to environment analysis port
        m_master_agent.m_ap.connect(m_ap);

        `uvm_info(get_type_name(), "Environment connected successfully", UVM_HIGH)
    endfunction

    // End of elaboration phase
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);

        // Print topology
        `uvm_info(get_type_name(), "AXI4 VIP Topology:", UVM_MEDIUM)
        uvm_top.print_topology();
    endfunction

    // Report phase
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info(get_type_name(), "===== AXI4 Environment Report =====", UVM_NONE)
        `uvm_info(get_type_name(), "------------------------------------", UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Configuration: DataWidth=%0d, AddrWidth=%0d, IDWidth=%0d",
            m_cfg.m_data_width, m_cfg.m_addr_width, m_cfg.m_id_width), UVM_NONE)
        `uvm_info(get_type_name(), $sformatf(
            "Agent Active: %s, Max Outstanding: %0d",
            m_cfg.m_is_active ? "Yes" : "No", m_cfg.m_max_outstanding), UVM_NONE)
        `uvm_info(get_type_name(), "------------------------------------", UVM_NONE)
    endfunction

endclass : axi4_env

`endif // AXI4_ENV_SV