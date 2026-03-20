# AXI4 VIP Makefile
# Supports compilation and simulation with various simulators

# Simulator selection (vcs, questasim, xrun)
SIMULATOR ?= vcs

# File lists
PKG_FILES = sv/axi4_types.sv \
            sv/axi4_config.sv \
            sv/axi4_transaction.sv \
            sv/axi4_sequencer.sv \
            sv/axi4_sequence.sv \
            sv/axi4_monitor.sv \
            sv/axi4_master_driver.sv \
            sv/axi4_master_agent.sv \
            sv/axi4_env.sv

IF_FILES = sv/axi4_interface.sv

TB_FILES = tb/axi4_test.sv \
           tb/axi4_tb_top.sv

# UVM home (adjust as needed)
UVM_HOME ?= $(VCS_HOME)/etc/uvm-1.2

# Output directory
OUT_DIR ?= work

# Test selection
TEST ?= axi4_base_test

# Simulation options
GUI ?= 0
COVERAGE ?= 0

.PHONY: all clean compile sim vcs questa xrun

all: compile

# VCS compilation and simulation
vcs: compile_vcs
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_MEDIUM

compile_vcs:
	mkdir -p $(OUT_DIR)
	vcs -full64 -sverilog -ntb_opts uvm-1.2 \
		-k $(OUT_DIR)/vcs.log \
		-lca \
		-LDFLAGS -Wl,--no-as-needed \
		-timescale=1ns/1ps \
		+incdir+sv \
		+incdir+tb \
		$(IF_FILES) \
		sv/axi4_pkg.sv \
		$(TB_FILES) \
		-o simv \
		-l compile.log

# Questa Sim compilation and simulation
questa: compile_questa
	vsim -c -do "run -all; quit" work.axi4_tb_top +UVM_TESTNAME=$(TEST)

compile_questa:
	mkdir -p $(OUT_DIR)
	vlib work
	vlog -sv \
		+incdir+sv \
		+incdir+tb \
		$(IF_FILES) \
		sv/axi4_pkg.sv \
		$(TB_FILES) \
		-l compile.log

# Xcelium compilation and simulation
xrun: compile_xrun

compile_xrun:
	mkdir -p $(OUT_DIR)
	xrun -64bit -sv -uvm \
		+incdir+sv \
		+incdir+tb \
		$(IF_FILES) \
		sv/axi4_pkg.sv \
		$(TB_FILES) \
		+UVM_TESTNAME=$(TEST) \
		-l xrun.log

# Generic compile target
compile:
ifeq ($(SIMULATOR),vcs)
	$(MAKE) compile_vcs
else ifeq ($(SIMULATOR),questa)
	$(MAKE) compile_questa
else ifeq ($(SIMULATOR),xrun)
	$(MAKE) compile_xrun
else
	$(error Unknown simulator: $(SIMULATOR))
endif

# Run simulation
sim:
ifeq ($(SIMULATOR),vcs)
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_MEDIUM
else ifeq ($(SIMULATOR),questa)
	vsim -c -do "run -all; quit" work.axi4_tb_top +UVM_TESTNAME=$(TEST)
else ifeq ($(SIMULATOR),xrun)
	$(MAKE) compile_xrun
endif

# Run specific tests
test_single_write:
	$(MAKE) sim TEST=axi4_single_write_test

test_single_read:
	$(MAKE) sim TEST=axi4_single_read_test

test_random:
	$(MAKE) sim TEST=axi4_random_burst_test

test_fixed:
	$(MAKE) sim TEST=axi4_fixed_burst_test

test_wrap:
	$(MAKE) sim TEST=axi4_wrap_burst_test

test_long_burst:
	$(MAKE) sim TEST=axi4_long_burst_test

test_unaligned:
	$(MAKE) sim TEST=axi4_unaligned_test

test_2kb_boundary:
	$(MAKE) sim TEST=axi4_2kb_boundary_test

test_wstrb_mask:
	$(MAKE) sim TEST=axi4_wstrb_mask_test

test_bandwidth:
	$(MAKE) sim TEST=axi4_bandwidth_test

# Clean up
clean:
	rm -rf $(OUT_DIR)
	rm -rf simv* csrc DVEfiles
	rm -rf work
	rm -f *.log *.key *.vpd
	rm -rf INCA_libs irun.key irun.log xrun.log

# Help
help:
	@echo "AXI4 VIP Makefile"
	@echo ""
	@echo "Usage: make [target] [options]"
	@echo ""
	@echo "Targets:"
	@echo "  compile      - Compile the VIP and testbench"
	@echo "  sim          - Run simulation"
	@echo "  vcs          - Compile and run with VCS"
	@echo "  questa       - Compile and run with Questa Sim"
	@echo "  xrun         - Compile and run with Xcelium"
	@echo "  clean        - Clean up generated files"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Test targets:"
	@echo "  test_single_write   - Single write transaction test"
	@echo "  test_single_read    - Single read transaction test"
	@echo "  test_random         - Random burst test"
	@echo "  test_fixed          - Fixed burst test"
	@echo "  test_wrap           - Wrap burst test"
	@echo "  test_long_burst     - Long INCR burst test (burst splitting)"
	@echo "  test_unaligned      - Unaligned transfer test"
	@echo "  test_2kb_boundary   - 2KB boundary crossing test"
	@echo "  test_wstrb_mask     - WSTRB mask test"
	@echo "  test_bandwidth      - Bandwidth efficiency test"
	@echo ""
	@echo "Options:"
	@echo "  SIMULATOR=vcs|questa|xrun  - Select simulator (default: vcs)"
	@echo "  TEST=<test_name>           - Select test to run (default: axi4_base_test)"
	@echo "  GUI=1                      - Enable GUI mode"
	@echo "  COVERAGE=1                 - Enable coverage"