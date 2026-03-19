// AXI4 Transaction Class
// This file contains the transaction class for AXI4 VIP

`ifndef AXI4_TRANSACTION_SV
`define AXI4_TRANSACTION_SV

class axi4_transaction extends uvm_sequence_item;

  // Transaction type
  rand axi4_transaction_type_e trans_type;

  // Address channel signals
  rand logic [`AXI4_ADDR_WIDTH-1:0] addr;
  rand logic [7:0]                   len;      // Burst length (0-255, actual beats = len+1)
  rand logic [2:0]                   size;     // Transfer size (bytes per beat = 2^size)
  rand axi4_burst_type_e             burst;
  rand logic [`AXI4_ID_WIDTH-1:0]    id;
  rand logic [3:0]                   cache;
  rand logic [2:0]                   prot;
  rand logic [1:0]                   lock;
  rand logic [3:0]                   qos;      // Quality of Service
  rand logic [3:0]                   region;   // Region identifier
  rand logic [`AXI4_USER_WIDTH-1:0] user;

  // Write data channel signals
  rand logic [`AXI4_DATA_WIDTH-1:0] wdata[];
  rand logic [(`AXI4_DATA_WIDTH/8)-1:0] wstrb[];
  rand bit                           wlast;

  // Read data channel signals
  rand logic [`AXI4_DATA_WIDTH-1:0] rdata[];
  axi4_resp_type_e                   rresp[];
  bit                                rlast;

  // Response signals
  axi4_resp_type_e                   bresp;
  logic [`AXI4_ID_WIDTH-1:0]         bid;

  // Timing statistics
  time start_time;
  time end_time;
  int  latency_cycles;
  int  addr_accepted_cycle;  // Cycle when address was accepted
  int  last_data_cycle;      // Cycle when last data was transferred

  // Constraints
  constraint valid_len_c {
    if (burst == AXI4_BURST_FIXED)
      len <= 15;  // FIXED burst max 16 beats
    else if (burst == AXI4_BURST_WRAP)
      len inside {1, 3, 7, 15};  // WRAP burst: 2, 4, 8, 16 beats
    else
      len <= 255;  // INCR burst max 256 beats
  }

  constraint valid_size_c {
    size <= $clog2(`AXI4_DATA_WIDTH/8);  // Size cannot exceed bus width
  }

  constraint valid_data_array_size_c {
    wdata.size() == len + 1;
    wstrb.size() == len + 1;
    rdata.size() == len + 1;
    rresp.size() == len + 1;
  }

  constraint valid_wstrb_c {
    foreach (wstrb[i]) {
      wstrb[i] inside {[0:(1<<(`AXI4_DATA_WIDTH/8))-1]};
    }
  }

  // Burst length helper (returns actual number of beats)
  function int get_burst_length();
    return int'(len) + 1;
  endfunction

  // Transfer size in bytes helper
  function int get_transfer_size();
    return 1 << size;
  endfunction

  // Calculate total transfer bytes
  function int get_total_bytes();
    return get_burst_length() * get_transfer_size();
  endfunction

  // Calculate latency (cycles from address accepted to last data)
  function int get_latency();
    if (last_data_cycle > 0 && addr_accepted_cycle > 0)
      return last_data_cycle - addr_accepted_cycle;
    else
      return 0;
  endfunction

  `uvm_object_utils_begin(axi4_transaction)
    `uvm_field_enum(axi4_transaction_type_e, trans_type, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(len, UVM_DEFAULT)
    `uvm_field_int(size, UVM_DEFAULT)
    `uvm_field_enum(axi4_burst_type_e, burst, UVM_DEFAULT)
    `uvm_field_int(id, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(cache, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(prot, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(lock, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(qos, UVM_DEFAULT)
    `uvm_field_int(region, UVM_DEFAULT)
    `uvm_field_int(user, UVM_DEFAULT | UVM_HEX)
    `uvm_field_array_int(wdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_array_int(wstrb, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(wlast, UVM_DEFAULT)
    `uvm_field_array_int(rdata, UVM_DEFAULT | UVM_HEX)
    `uvm_field_array_enum(axi4_resp_type_e, rresp, UVM_DEFAULT)
    `uvm_field_int(rlast, UVM_DEFAULT)
    `uvm_field_enum(axi4_resp_type_e, bresp, UVM_DEFAULT)
    `uvm_field_int(bid, UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(start_time, UVM_DEFAULT)
    `uvm_field_int(end_time, UVM_DEFAULT)
    `uvm_field_int(latency_cycles, UVM_DEFAULT)
    `uvm_field_int(addr_accepted_cycle, UVM_DEFAULT)
    `uvm_field_int(last_data_cycle, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "axi4_transaction");
    super.new(name);
    start_time = 0;
    end_time = 0;
    latency_cycles = 0;
    addr_accepted_cycle = 0;
    last_data_cycle = 0;
    wlast = 1;
    rlast = 1;
  endfunction

  // Deep copy function
  function void do_copy(uvm_object rhs);
    axi4_transaction rhs_txn;
    super.do_copy(rhs);
    $cast(rhs_txn, rhs);
    trans_type         = rhs_txn.trans_type;
    addr               = rhs_txn.addr;
    len                = rhs_txn.len;
    size               = rhs_txn.size;
    burst              = rhs_txn.burst;
    id                 = rhs_txn.id;
    cache              = rhs_txn.cache;
    prot               = rhs_txn.prot;
    lock               = rhs_txn.lock;
    qos                = rhs_txn.qos;
    region             = rhs_txn.region;
    user               = rhs_txn.user;
    wdata              = rhs_txn.wdata;
    wstrb              = rhs_txn.wstrb;
    wlast              = rhs_txn.wlast;
    rdata              = rhs_txn.rdata;
    rresp              = rhs_txn.rresp;
    rlast              = rhs_txn.rlast;
    bresp              = rhs_txn.bresp;
    bid                = rhs_txn.bid;
    start_time         = rhs_txn.start_time;
    end_time           = rhs_txn.end_time;
    latency_cycles     = rhs_txn.latency_cycles;
    addr_accepted_cycle = rhs_txn.addr_accepted_cycle;
    last_data_cycle    = rhs_txn.last_data_cycle;
  endfunction

  // Convert transaction to string for display
  function string convert2string();
    string s;
    s = super.convert2string();
    s = {s, $sformatf("\n  trans_type=%s", trans_type.name())};
    s = {s, $sformatf("\n  addr=0x%0h, len=%0d, size=%0d, burst=%s",
                      addr, len, size, burst.name())};
    s = {s, $sformatf("\n  id=0x%0h, cache=0x%0h, prot=0x%0h, qos=0x%0h",
                      id, cache, prot, qos)};
    return s;
  endfunction

endclass

`endif // AXI4_TRANSACTION_SV