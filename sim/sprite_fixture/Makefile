VERILATOR ?= verilator
SHELL := /bin/bash
BUILD_DIR ?= ../../simulation/sprite_fixture/build
GEN_DIR ?= ../../simulation/sprite_fixture/generated

.PHONY: run clean

run:
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --top-module tb_sprite_fixture -Wno-fatal -I$(GEN_DIR) --Mdir $(BUILD_DIR) tb_sprite_fixture.sv > $(BUILD_DIR)/build.log 2>&1
	set -o pipefail; $(BUILD_DIR)/Vtb_sprite_fixture | tee $(BUILD_DIR)/run.log

clean:
	rm -rf $(BUILD_DIR)
