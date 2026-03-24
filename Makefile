# Standalone VPU unit-test flow (software build + local Questa simulation)

########################################
# User-facing configuration
########################################
PYTHON ?= python3
PROJECT ?= vpu_compiler
SIM_DIR ?= $(or $(firstword $(wildcard build/sim-modelsim)),build/sim-modelsim)
STIM ?= sw/build/stimulus.txt
ASM ?= sw/build/main.S

########################################
# Toolchain and tool commands
# - Defaults work in this environment
# - Can be overridden from command line
########################################
RISCV_GCC ?= riscv32-unknown-elf-gcc
RISCV_OBJDUMP ?= riscv32-unknown-elf-objdump
QUESTA_VLIB ?= vlib
QUESTA_VLOG ?= vlog

########################################
# Optional license override
# By default, vsim uses shell environment.
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
SRC := $(PROJECT_DIR)/main.c
OBJ := sw/build/main.o
WAVE_DO := tb/wave_automatize.do
MARCH := rv32imc_zve32x_zvl128b
MABI := ilp32
CFLAGS := -O2 -march=$(MARCH) -mabi=$(MABI) -I$(PROJECT_DIR)

RTL_PKG_FILES := \
	rtl/include/vector_ops_pkg.sv \
	rtl/include/rvv_instr_pkg.sv \
	rtl/include/obi_pkg.sv \
	rtl/include/cvxif_types_pkg.sv \
	rtl/include/vpu_pkg.sv

RTL_FILES := \
	rtl/instr_decoder.sv \
	rtl/load_store_unit_mis.sv \
	rtl/obi_lsu_top.sv \
	rtl/simd_controller.sv \
	rtl/VAU_lanes.sv \
	rtl/VAU.sv \
	rtl/vregfile.sv \
	rtl/vpu_top.sv

TB_FILES := \
	tb/vpu_stimulus_gen.sv \
	tb/vpu_pipeline_checker.sv \
	tb/tb_vpu_top.sv

SV_INC_DIRS := +incdir+$(CURDIR)/rtl/include +incdir+$(CURDIR)/tb

.PHONY: all help check-tools build-sw build-sim run-vpu-unit-test run-vpu-unit-gui

all: run-vpu-unit-test

help:
	@echo "Targets:"
	@echo "  build-sw            Build sw/build/main.S from sw/<PROJECT>/main.c"
	@echo "  build-sim           Build local Questa simulation workspace"
	@echo "  run-vpu-unit-test   Run VPU unit test in CLI"
	@echo "  run-vpu-unit-gui    Run VPU unit test in GUI"
	@echo "Variables:"
	@echo "  PROJECT=<name>      Software project under sw/"
	@echo "  QUESTA_LICENSE=<lic> Optional, only if you want to force a license file"

check-tools:
	@command -v $(PYTHON) >/dev/null || (echo "Error: $(PYTHON) not found"; exit 1)
	@command -v vsim >/dev/null || (echo "Error: vsim not found"; exit 1)
	@command -v $(QUESTA_VLIB) >/dev/null || (echo "Error: $(QUESTA_VLIB) not found"; exit 1)
	@command -v $(QUESTA_VLOG) >/dev/null || (echo "Error: $(QUESTA_VLOG) not found"; exit 1)
	@command -v $(RISCV_GCC) >/dev/null || (echo "Error: $(RISCV_GCC) not found"; exit 1)
	@command -v $(RISCV_OBJDUMP) >/dev/null || (echo "Error: $(RISCV_OBJDUMP) not found"; exit 1)

build-sw:
	@test -f $(SRC) || (echo "Error: source file not found: $(SRC)"; exit 1)
	@mkdir -p sw/build
	$(RISCV_GCC) $(CFLAGS) -c $(SRC) -o $(OBJ)
	$(RISCV_OBJDUMP) -d $(OBJ) > $(ASM)

build-sim: check-tools
	@mkdir -p $(SIM_DIR)
	cd $(SIM_DIR) && [ -d work ] || $(QUESTA_VLIB) work
	cd $(SIM_DIR) && $(QUESTA_VLOG) -sv $(SV_INC_DIRS) $(addprefix $(CURDIR)/,$(RTL_PKG_FILES) $(RTL_FILES) $(TB_FILES))

run-vpu-unit-test: check-tools
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

		