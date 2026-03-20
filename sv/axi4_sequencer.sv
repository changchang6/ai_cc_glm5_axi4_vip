// AXI4 Sequencer
// Simple sequencer extending uvm_sequencer for AXI4 transactions

`ifndef AXI4_SEQUENCER_SV
`define AXI4_SEQUENCER_SV

class axi4_sequencer extends uvm_sequencer #(axi4_transaction);
    `uvm_component_utils(axi4_sequencer)

    // Configuration handle
    axi4_config m_cfg;

    // Constructor
    function new(string name = "axi4_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi4_config)::get(this, "", "m_cfg", m_cfg)) begin
            `uvm_warning(get_type_name(), "Configuration not found, using defaults")
        end
    endfunction

endclass : axi4_sequencer

`endif // AXI4_SEQUENCER_SV