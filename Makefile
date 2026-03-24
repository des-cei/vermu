# Modify paths for X-Heep directories
PYTHON ?= python3
PROJECT ?= vpu_compiler
SIM_DIR ?= build/.../sim-modelsim
STIM ?= sw/build/stimulus.txt
ASM ?= sw/build/main.S
BASE_DIR ?= ../../..

.PHONY: all help check-tools run-vpu-unit-test run-vpu-unit-gui

all: run-vpu-unit-test

help:
	@echo "Targets:"
	@echo "  run-vpu-unit-test   Run VPU unit test in CLI"
	@echo "  run-vpu-unit-gui    Run VPU unit test in GUI"

check-tools:
	@command -v $(PYTHON) >/dev/null || (echo "Error: $(PYTHON) not found"; exit 1)
	@command -v vsim >/dev/null || (echo "Error: vsim not found"; exit 1)

run-vpu-unit-test: check-tools
	@echo "--> Compiling software..."
	$(MAKE) app PROJECT=$(PROJECT)
	@echo "--> Generating stimulus..."
	$(PYTHON) scripts/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Running Questasim Unit Test..."
	cd $(SIM_DIR) && vsim -c -do "run -all; quit" tb_vpu_top +stimulus_path=../../../$(STIM)

run-vpu-unit-gui: check-tools
	@echo "--> Compiling software..."
	$(MAKE) app PROJECT=$(PROJECT)
	@echo "--> Generating stimulus..."
	$(PYTHON) scripts/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Launching Questasim GUI..."
	cd $(SIM_DIR) && vsim -voptargs="+acc" work.tb_vpu_top +stimulus_path=../../../$(STIM) -do $(BASE_DIR)/wave_automatize.do

		