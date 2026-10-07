VERILATOR ?= verilator
BUILD_DIR ?= ../../simulation/harness/teeter_nmi
GHDL ?= /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl
GHDL_LIB ?= /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib
GHDL_DIR ?= ../../simulation/harness/teeter_nmi_ghdl

.PHONY: test generator t65

test: generator t65

generator:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --top-module tb_teeter_nmi -Wno-fatal --Mdir $(BUILD_DIR) tb_teeter_nmi.sv ../../rtl/teeter_nmi.v > $(BUILD_DIR)/build.log 2>&1
	$(BUILD_DIR)/Vtb_teeter_nmi > $(BUILD_DIR)/run.log 2>&1
	grep -q "PASS Teeter NMI generator nominal period=75260" $(BUILD_DIR)/run.log

t65:
	mkdir -p $(GHDL_DIR)
	rm -f $(GHDL_DIR)/work-obj08.cf
	LD_LIBRARY_PATH=$(GHDL_LIB) $(GHDL) -a --std=08 --ieee=synopsys --workdir=$(GHDL_DIR) ../../modules/cpu-t65/T65_Pack.vhd ../../modules/cpu-t65/T65_ALU.vhd ../../modules/cpu-t65/T65_MCode.vhd ../../modules/cpu-t65/T65.vhd tb_t65_nmi.vhd
	LD_LIBRARY_PATH=$(GHDL_LIB) $(GHDL) -e --std=08 --ieee=synopsys --workdir=$(GHDL_DIR) tb_t65_nmi
	LD_LIBRARY_PATH=$(GHDL_LIB) $(GHDL) -r --std=08 --ieee=synopsys --workdir=$(GHDL_DIR) tb_t65_nmi --assert-level=error > $(GHDL_DIR)/run.log 2>&1 || { cat $(GHDL_DIR)/run.log; exit 1; }
	grep -q "PASS selected T65 captures paused NMI" $(GHDL_DIR)/run.log || { cat $(GHDL_DIR)/run.log; exit 1; }
