VERILATOR ?= verilator
BUILD_DIR ?= ../../simulation/harness/ttl_ls139
GHDL ?= /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/bin/ghdl
GHDL_LIB ?= /mnt/c/MiSTerDev/_tools/ghdl6/ghdl-mcode-6.0.0-ubuntu24.04-x86_64/lib
GHDL_DIR ?= ../../simulation/harness/ghdl

.PHONY: smoke vhdl-check clean

smoke:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --top-module tb_exidy_ls139 -Wno-fatal --Mdir $(BUILD_DIR) tb_exidy_ls139.sv ../../rtl/ttl_chips.v > $(BUILD_DIR)/build.log 2>&1
	$(BUILD_DIR)/Vtb_exidy_ls139

vhdl-check:
	mkdir -p $(GHDL_DIR)
	rm -f $(GHDL_DIR)/work-obj08.cf
	LD_LIBRARY_PATH=$(GHDL_LIB) $(GHDL) -a --std=08 --ieee=synopsys --workdir=$(GHDL_DIR) ../../modules/6840/berzerk_sound_fx.vhd
	LD_LIBRARY_PATH=$(GHDL_LIB) $(GHDL) --synth --std=08 --ieee=synopsys --workdir=$(GHDL_DIR) --out=verilog berzerk_sound_fx > $(GHDL_DIR)/berzerk_sound_fx.v 2> $(GHDL_DIR)/synthesis.log
	$(VERILATOR) --lint-only --top-module berzerk_sound_fx -Wno-fatal $(GHDL_DIR)/berzerk_sound_fx.v > $(GHDL_DIR)/verilator-lint.log 2>&1
	@echo "PASS selected 6840 VHDL analysis/synthesis and Verilator lint (translation feasibility only)"

clean:
	rm -rf $(BUILD_DIR)
