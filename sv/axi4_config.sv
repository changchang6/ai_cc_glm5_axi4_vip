// AXI4 Configuration Class
// This file contains the configuration class for AXI4 VIP

`ifndef AXI4_CONFIG_SV
`define AXI4_CONFIG_SV

class axi4_config extends uvm_object;

  // Bus width configuration
  rand int data_width;      // Data bus width (default: 128 bits)
  rand int addr_width;      // Address bus width (default: 32 bits)
  rand int id_width;        // ID bus width (default: 4 bits)
  rand int user_width;      // User signal width (default: 4 bits)

  // Master agent configuration
  rand int max_outstanding; // Maximum number of outstanding transactions
  rand int min_interval;    // Minimum interval between transactions (cycles)

  // Timeout configuration
  rand int rtimeout;        // Read transaction timeout threshold (cycles)
  rand int wtimeout;        // Write transaction timeout threshold (cycles)

  // Burst split configuration
  rand bit enable_split;       // Enable burst splitting for large bursts
  rand int  split_burst_len;   // Maximum burst length after splitting (default: 32)

  // Data before address configuration
  rand bit support_data_before_addr; // Support sending write data before address
  rand int  data_before_addr_osd;    // Maximum outstanding data before address

  // Agent active mode
  rand uvm_active_passive_enum is_active; // Active or passive mode

  // Default constraints
  constraint valid_data_width_c {
    data_width inside {32, 64, 128, 256, 512, 1024};
  }

  constraint valid_addr_width_c {
    addr_width inside {32, 40, 48, 64};
  }

  constraint valid_id_width_c {
    id_width inside {1, 2, 4, 8, 16};
  }

  constraint valid_user_width_c {
    user_width >= 0;
    user_width <= 64;
  }

  constraint valid_outstanding_c {
    max_outstanding >= 1;
    max_outstanding <= 16;
  }

  constraint valid_interval_c {
    min_interval >= 0;
    min_interval <= 16;
  }

  constraint valid_timeout_c {
    rtimeout >= 0;
    wtimeout >= 0;
    rtimeout <= 10000;
    wtimeout <= 10000;
  }

  constraint valid_split_c {
    if (enable_split) {
      split_burst_len inside {1, 2, 4, 8, 16, 32};
    }
  }

  constraint valid_data_before_addr_c {
    if (support_data_before_addr) {
      data_before_addr_osd >= 1;
      data_before_addr_osd <= max_outstanding;
    }
  }

  // Default values
  constraint default_c {
    soft data_width == 128;
    soft addr_width == 32;
    soft id_width == 4;
    soft user_width == 4;
    soft max_outstanding == 8;
    soft min_interval == 0;
    soft rtimeout == 1000;
    soft wtimeout == 1000;
    soft enable_split == 1;
    soft split_burst_len == 32;
    soft support_data_before_addr == 0;
    soft data_before_addr_osd == 1;
    soft is_active == UVM_ACTIVE;
  }

  `uvm_object_utils_begin(axi4_config)
    `uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(addr_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(id_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(user_width, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(max_outstanding, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(min_interval, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(rtimeout, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(wtimeout, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(enable_split, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(split_burst_len, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(support_data_before_addr, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(data_before_addr_osd, UVM_DEFAULT | UVM_DEC)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi4_config");
    super.new(name);
  endfunction

  // Print configuration summary
  function void print_config();
    `uvm_info(get_type_name(), $sformatf("AXI4 Configuration:"), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Data Width:      %0d bits", data_width), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Address Width:   %0d bits", addr_width), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  ID Width:        %0d bits", id_width), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  User Width:      %0d bits", user_width), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Max Outstanding: %0d", max_outstanding), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Min Interval:    %0d cycles", min_interval), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Read Timeout:    %0d cycles", rtimeout), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Write Timeout:   %0d cycles", wtimeout), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Enable Split:    %0b", enable_split), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Split Burst Len: %0d", split_burst_len), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Data Before Addr: %0b", support_data_before_addr), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  Active Mode:      %s", is_active.name()), UVM_LOW)
  endfunction

endclass

`endif // AXI4_CONFIG_SV