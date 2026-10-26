# Lab 3 Part 4: 8x8 FP8 matmul with APB slave. Run `source env.cshrc` first.
#   make          run the testbench with VCS (default)
#   make waves    build with FSDB, run, and open Verdi on the exception test
#                 with the report signals and markers (part4_views.tcl)
#   make view-waves  re-open the last FSDB without re-running
#   make vl       run with Verilator (local, no VCS needed)
#   make clean
.DEFAULT_GOAL := all
VCS ?= vcs
VERDI_HOME ?= /usr/local2/synopsys/verdi_2024.09/verdi_2024
VERDI ?= $(VERDI_HOME)/bin/verdi
export VERDI_HOME

SRC := FPAddSub.sv FPMult.sv matmul.sv matmul_8x8.sv apb_slave.sv \
       matmul_8x8_with_ram.sv matmul_8x8_with_ram_tb.sv
TOP := matmul_with_ram_tb
BUILD := build/vcs
WAVE_BUILD := build/fsdb
WAVE_SIM := $(WAVE_BUILD)/simv
WAVE_FILE := $(WAVE_BUILD)/matmul_apb.fsdb
WAVE_EVENTS := $(abspath $(WAVE_BUILD))/events.tcl
WAVE_SCRIPT := $(abspath part4_views.tcl)

.PHONY: all waves view-waves check-wave-tools vl clean
all: $(BUILD)/simv
	cd $(BUILD) && ./simv -l run.log
	@grep -Fq "ALL TESTS PASSED" $(BUILD)/run.log || { echo "ERROR: a test failed"; exit 1; }

$(BUILD)/simv: $(SRC) Makefile
	mkdir -p $(BUILD)
	$(VCS) -full64 -sverilog -debug_access+all $(SRC) -top $(TOP) \
		-Mdir=$(BUILD)/csrc -o $@ -l $(BUILD)/compile.log

check-wave-tools:
	@command -v "$(VERDI)" >/dev/null || { echo "ERROR: run 'source env.cshrc' or set VERDI_HOME"; exit 1; }

# Separate binary with the $fsdbDump calls turned on (+define+FSDB).
$(WAVE_SIM): $(SRC) Makefile | check-wave-tools
	mkdir -p $(WAVE_BUILD)
	$(VCS) -full64 -sverilog -debug_access+all -kdb -lca +define+FSDB $(SRC) \
		-top $(TOP) -Mdir=$(WAVE_BUILD)/csrc -o $@ -l $(WAVE_BUILD)/compile.log

# One command: compile, run all tests, check the result, turn the WAVE_EVENT
# lines the testbench printed into Verdi markers, then open Verdi.
waves: $(WAVE_SIM)
	rm -f $(WAVE_FILE)
	cd $(WAVE_BUILD) && ./simv -l run.log
	@grep -Fq "ALL TESTS PASSED" $(WAVE_BUILD)/run.log || \
		{ echo "ERROR: a test failed; see $(WAVE_BUILD)/run.log"; exit 1; }
	@test -s $(WAVE_FILE) || { echo "ERROR: FSDB file was not created"; exit 1; }
	@grep "^WAVE_EVENT" $(WAVE_BUILD)/run.log | \
		awk 'BEGIN{printf "set events [dict create"} {printf " %s %s", $$2, $$3} END{print "]"}' > $(WAVE_EVENTS)
	WAVE_EVENTS=$(WAVE_EVENTS) $(VERDI) -dbdir $(WAVE_SIM).daidir -ssf $(WAVE_FILE) \
		-play "$(WAVE_SCRIPT)" -nologo &

view-waves: check-wave-tools
	@test -s $(WAVE_FILE) || { echo "ERROR: run make waves first"; exit 1; }
	WAVE_EVENTS=$(WAVE_EVENTS) $(VERDI) -dbdir $(WAVE_SIM).daidir -ssf $(WAVE_FILE) \
		-play "$(WAVE_SCRIPT)" -nologo &

vl:
	mkdir -p build/vl
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module $(TOP) \
		-Mdir build/vl $(SRC)
	./build/vl/V$(TOP)

clean:
	rm -rf build csrc simv simv.daidir ucli.key
	rm -f *.fsdb *.vcd vc_hdrs.h novas.* verdiLog
