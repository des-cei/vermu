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
# Try to find source in PROJECT_DIR/main.c first, then sw/tb/PROJECT.c
SRC := $(or $(wildcard $(PROJECT_DIR)/main.c), sw/tb/$(PROJECT).c)
OBJ := sw/build/main.o
WAVE_DO := tb/wave.do
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
	rtl/vpu_xif_decoder.sv \
	rtl/vpu_decoder.sv \
	rtl/vpu_control_unit.sv \
	rtl/load_store_unit_mis.sv \
	rtl/obi_lsu_top.sv \
	rtl/simd_controller.sv \
	rtl/VAU_lanes.sv \
	rtl/VAU.sv \
	rtl/vregfile.sv \
	rtl/vpu_top.sv

#TODO: remove tb files?
TB_FILES := \
    tb/tb_xif_decoder.sv \
	tb/vpu_stimulus_gen.sv \
	tb/vpu_pipeline_checker.sv \
	tb/tb_vpu_top.sv

SIM_FILES ?= -all
	

SV_INC_DIRS := +incdir+$(CURDIR)/rtl/include +incdir+$(CURDIR)/tb

.PHONY: all help check-tools build-sw build-sim run-vpu-unit-test run-vpu-unit-gui run-questa-tb run-questa-tb-gui

all: run-vpu-unit-test

help:
	@echo "Targets:"
	@echo "  build-sw            Build sw/build/main.S from sw/<PROJECT>/main.c"
	@echo "  build-sim           Build local Questa simulation workspace"
	@echo "  run-vpu-unit-test   Run VPU unit test in CLI"
	@echo "  run-vpu-unit-gui    Run VPU unit test in GUI"
	@echo "  run-questa-tb       Run an arbitrary tb_<name> in CLI"
	@echo "  run-questa-tb-gui   Run an arbitrary tb_<name> in GUI"
	@echo "Variables:"
	@echo "  PROJECT=<name>      Software project under sw/"
	@echo "  SIM_FILES=<list>    Files to compile in build-sim, or -all"
	@echo "  TB_TOP=<module>     Top module to simulate with run-questa-tb"
	@echo "  QUESTA_LICENSE=<lic> Optional, only if you want to force a license file"

check-tools:
	@echo "Checking tools and their resolved paths:"
	@echo "  PYTHON: $(PYTHON) -> $$(command -v $(PYTHON) 2>/dev/null || echo not-found)"
	@echo "  vsim: $$(command -v vsim 2>/dev/null || echo not-found)"
	@echo "  $(QUESTA_VLIB): $$(command -v $(QUESTA_VLIB) 2>/dev/null || echo not-found)"
	@echo "  $(QUESTA_VLOG): $$(command -v $(QUESTA_VLOG) 2>/dev/null || echo not-found)"
	@echo "  $(RISCV_GCC): $$(command -v $(RISCV_GCC) 2>/dev/null || echo not-found)"
	@echo "  $(RISCV_OBJDUMP): $$(command -v $(RISCV_OBJDUMP) 2>/dev/null || echo not-found)"
	@command -v $(PYTHON) >/dev/null || (echo "Error: $(PYTHON) not found"; exit 1)
	@command -v vsim >/dev/null || (echo "Error: vsim not found"; exit 1)
	@command -v $(QUESTA_VLIB) >/dev/null || (echo "Error: $(QUESTA_VLIB) not found"; exit 1)
	@command -v $(QUESTA_VLOG) >/dev/null || (echo "Error: $(QUESTA_VLOG) not found"; exit 1)
	@command -v $(RISCV_GCC) >/dev/null || (echo "Error: $(RISCV_GCC) not found"; exit 1)
	@command -v $(RISCV_OBJDUMP) >/dev/null || (echo "Error: $(RISCV_OBJDUMP) not found"; exit 1)

build-sw:
	@echo "--> Building sw..."
	@test -f $(SRC) || (echo "Error: source file not found: $(SRC)"; exit 1)
	@mkdir -p sw/build
	$(RISCV_GCC) $(CFLAGS) -c $(SRC) -o $(OBJ)
	$(RISCV_OBJDUMP) -d $(OBJ) > $(ASM)

build-sim: check-tools
	@mkdir -p $(SIM_DIR)
	@test -f $(SRC) || (echo "Error: source file not found: $(SRC)"; exit 1)
	@mkdir -p sw/build
	$(RISCV_GCC) $(CFLAGS) -c $(SRC) -o $(OBJ)
	$(RISCV_OBJDUMP) -d $(OBJ) > $(ASM)
	cd $(SIM_DIR) && [ -d work ] || $(QUESTA_VLIB) work
	cd $(SIM_DIR) && $(if $(filter -all,$(SIM_FILES)),$(QUESTA_VLOG) -sv $(SV_INC_DIRS) $(addprefix $(CURDIR)/,$(RTL_PKG_FILES) $(RTL_FILES) $(TB_FILES)),$(QUESTA_VLOG) -sv $(SV_INC_DIRS) $(addprefix $(CURDIR)/,$(SIM_FILES)))

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

run-questa-tb: check-tools
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Running Questasim testbench $(TB_TOP)..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -c -do "run -all; quit" $(TB_TOP) +stimulus_path=$(CURDIR)/$(STIM)

run-questa-tb-gui: check-tools
	@echo "--> Building local simulation workspace..."
	$(MAKE) build-sim
	@echo "--> Generating stimulus..."
	$(PYTHON) tb/gen_stimulus.py $(ASM) $(STIM)
	@echo "--> Launching Questasim testbench $(TB_TOP) in GUI..."
	cd $(SIM_DIR) && $(VSIM_ENV) vsim -voptargs="+acc" work.$(TB_TOP) +stimulus_path=$(CURDIR)/$(STIM) -do $(CURDIR)/$(WAVE_DO)

		