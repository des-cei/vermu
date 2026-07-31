# Standalone VPU unit-test flow (software build + local Questa simulation)

########################################
# User-facing configuration
########################################
PYTHON ?= python3
PROJECT ?= vpu_compiler
CORE_NAME ?= ceiupm::vpu_upm
FUSESOC_TARGET ?= default
BUILD_DIR ?= build
# SIM_DIR = $(shell find $(BUILD_DIR) -maxdepth 1 -type d -name '*vpu_upm*' 2>/dev/null | sort -V | head -n 1)/sim-modelsim
SIM_BASE_DIR = $(shell find $(BUILD_DIR) -maxdepth 1 -type d -name '*vpu_upm*' 2>/dev/null | sort -V | head -n 1)
SIM_DIR ?= $(or $(wildcard $(SIM_BASE_DIR)/$(FUSESOC_TARGET)-modelsim),$(wildcard $(SIM_BASE_DIR)/sim-modelsim),$(firstword $(wildcard $(SIM_BASE_DIR)/*-modelsim)))
STIM ?= sw/build/stimulus.txt
ASM ?= sw/build/main.S
TB_TOP ?= tb_vpu_top
TB_FILE ?= tb/$(TB_TOP).sv

# Resolve paths from this Makefile, but allow a parent project to override them.
MODULE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
ROOT_DIR ?= $(MODULE_DIR)

########################################
# Toolchain and tool commands
########################################
RISCV_GCC ?= riscv32-unknown-elf-gcc
RISCV_OBJDUMP ?= riscv32-unknown-elf-objdump
FUSESOC ?= fusesoc
QUESTA_VLOG ?= vlog
# QUESTA_VLIB ?= vlib

########################################
# Optional license override
########################################
QUESTA_LICENSE ?=
VSIM_ENV :=
ifneq ($(strip $(QUESTA_LICENSE)),)
VSIM_ENV := MGLS_LICENSE_FILE=$(QUESTA_LICENSE) LM_LICENSE_FILE=$(QUESTA_LICENSE)
endif

########################################
# Build configuration
########################################
PROJECT_DIR := sw/$(PROJECT)
#SRC := $(or $(wildcard $(PROJECT_DIR)/main.c), $(SW_DIR)/tb/$(PROJECT).c)
SRC := $(or $(wildcard $(PROJECT_DIR)/main.c), sw/tb/$(PROJECT).c)
OBJ := sw/build/main.o
WAVE_DO ?= tb/wave.do
MARCH := rv32imc_zve32x_zvl128b
MABI := ilp32
CFLAGS := -O2 -march=$(MARCH) -mabi=$(MABI) -I$(PROJECT_DIR)


.PHONY: all help check-tools build-sw build-sim run-vpu-unit run-vpu-unit-gui run-questa-tb run-questa-tb-gui

all: run-vpu-unit

help:
	@echo "Targets:"
	@echo "  build-sw            Build sw/build/main.S from sw/<PROJECT>/main.c"
	@echo "  build-sim           Run FuseSoC to elaborate the sim target (Questa)"
	@echo "  run-vpu-unit        Run VPU unit test in CLI"
	@echo "  run-vpu-unit-gui    Run VPU unit test in GUI"
	@echo "  run-questa-tb       Run a module-level TB in CLI"
	@echo "  run-questa-tb-gui   Run a module-level TB in GUI"
	@echo "Variables:"
	@echo "  PROJECT=<name>      Software project under sw/"
	@echo "  TB_TOP=<module>     Testbench top module name"
	@echo "  TB_FILE=<file>      Testbench source file under tb/"
	@echo "  QUESTA_LICENSE=<lic> Optional, only if you want to force a license file"

check-tools:
	@echo "Checking tools and their resolved paths:"
	@command -v $(PYTHON) >/dev/null || (echo "Error: $(PYTHON) not found"; exit 1)
	@command -v vsim >/dev/null || (echo "Error: vsim not found"; exit 1)
	@command -v $(QUESTA_VLOG) >/dev/null || (echo "Error: $(QUESTA_VLOG) not found"; exit 1)
	@command -v $(FUSESOC) >/dev/null || (echo "Error: fusesoc not found"; exit 1)
	@command -v $(RISCV_GCC) >/dev/null || (echo "Error: $(RISCV_GCC) not found"; exit 1)
	@command -v $(RISCV_OBJDUMP) >/dev/null || (echo "Error: $(RISCV_OBJDUMP) not found"; exit 1)

build-sw:
	@echo "--> Building sw..."
	@test -f $(SRC) || (echo "Error: source file not found: $(SRC)"; exit 1)
	@mkdir -p sw/build
	$(RISCV_GCC) $(CFLAGS) -c $(SRC) -o $(OBJ)
	$(RISCV_OBJDUMP) -d $(OBJ) > $(ASM)

build-sim: check-tools
	$(FUSESOC) --cores-root . run --target=$(FUSESOC_TARGET) --setup --build $(CORE_NAME)

## Test VPU by injection of certain C application instructions through X-IF
## @param PROJECT=<application to test>
run-vpu-unit: check-tools
	@echo "--> Compiling software..."
	$(MAKE) build-sw PROJECT=$(PROJECT)
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Running Questasim Unit Test..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -c -do "run -all; quit" tb_vpu_top +stimulus_path=$(CURDIR)/$(STIM)

run-vpu-unit-gui: check-tools
	@echo "--> Compiling software..."
	$(MAKE) build-sw PROJECT=$(PROJECT)
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Launching Questasim GUI..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -voptargs="+acc" work.tb_vpu_top +stimulus_path=$(CURDIR)/$(STIM) -do $(CURDIR)/$(WAVE_DO)

## Test specific VPU modules with particular testbenches
## @param PROJECT=<application> TB_TOP=<tb_module> TB_FILE=<tb/tb_file.sv>

run-questa-tb: check-tools
	@echo "--> Compiling software..."
	$(MAKE) build-sw PROJECT=$(PROJECT)
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@if [ -n "$(strip $(TB_FILE))" ]; then \
		echo "--> Compiling testbench source $(TB_FILE)..."; \
		cd $(SIM_DIR) && $(VSIM_ENV) $(QUESTA_VLOG) -sv -work work $(CURDIR)/$(TB_FILE); \
	fi
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Running Questasim testbench $(TB_TOP)..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -c -do "run -all; quit" $(TB_TOP) +stimulus_path=$(CURDIR)/$(STIM)

run-questa-tb-gui: check-tools
	@echo "--> Compiling software..."
	$(MAKE) build-sw PROJECT=$(PROJECT)
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@if [ -n "$(strip $(TB_FILE))" ]; then \
		echo "--> Compiling testbench source $(TB_FILE)..."; \
		cd $(SIM_DIR) && $(VSIM_ENV) $(QUESTA_VLOG) -sv -work work $(CURDIR)/$(TB_FILE); \
	fi
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Launching Questasim testbench $(TB_TOP) in GUI..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -voptargs="+acc" work.$(TB_TOP) +stimulus_path=$(CURDIR)/$(STIM) -do $(CURDIR)/$(WAVE_DO)
	
clean:
	rm -rf $(BUILD_DIR) sw/build