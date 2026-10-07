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

# Candidate PIA return-byte checks. The paired VHDL bench instantiates the
# production PIAs and sweeps all seven distinct phases of the 7:22 clock ratio.
PIA_RETURN_DIR ?= ../../simulation/harness/pia_return
PIA_GHDL_DIR ?= ../../simulation/harness/pia_return_ghdl
PIA_GHDL ?= $(GHDL)
PIA_GHDL_LIB ?= $(GHDL_LIB)

.PHONY: pia-return
pia-return:
	mkdir -p $(PIA_RETURN_DIR) $(PIA_GHDL_DIR)
	rm -f $(PIA_GHDL_DIR)/work-obj08.cf
	LD_LIBRARY_PATH=$(PIA_GHDL_LIB) $(PIA_GHDL) -a --std=08 --ieee=synopsys --workdir=$(PIA_GHDL_DIR) ../../modules/pia/pia6821.vhd ../../sim/pia_return/tb_pia_return_pair.vhd
	LD_LIBRARY_PATH=$(PIA_GHDL_LIB) $(PIA_GHDL) -e --std=08 --ieee=synopsys --workdir=$(PIA_GHDL_DIR) tb_pia_return_pair
	@for phase in 0 1 2 3 4 5 6; do LD_LIBRARY_PATH=$(PIA_GHDL_LIB) $(PIA_GHDL) -r --std=08 --ieee=synopsys --workdir=$(PIA_GHDL_DIR) tb_pia_return_pair -gPHASE_NS=$$phase --assert-level=error > $(PIA_GHDL_DIR)/phase-$$phase.log 2>&1 || { cat $(PIA_GHDL_DIR)/phase-$$phase.log; exit 1; }; grep -q "PASS paired production PIA return byte phase=" $(PIA_GHDL_DIR)/phase-$$phase.log || { cat $(PIA_GHDL_DIR)/phase-$$phase.log; exit 1; }; done
	$(VERILATOR) --binary --timing --top-module tb_pia_return -Wno-fatal --Mdir $(PIA_RETURN_DIR) ../../sim/pia_return/tb_pia_return.sv ../../rtl/pia_return.v > $(PIA_RETURN_DIR)/build.log 2>&1
	$(PIA_RETURN_DIR)/Vtb_pia_return > $(PIA_RETURN_DIR)/run.log 2>&1
	@echo "PASS paired production PIA handshake and staged-byte phase sweep plus production Verilog register test"

clean:
	rm -rf $(BUILD_DIR)
