#!/usr/bin/env bash
# Environment template for VPU unit-test flow
# Copy this file to your local machine-specific env script and edit paths.

set -e

# ---- RISC-V toolchain (required for build-sw) ----
export RISCV_XHEEP="/tools/rv32imc_zve32x_zvl128b"
export PATH="$RISCV_XHEEP/bin:$PATH"

# ---- Questa/ModelSim (required for build-sim/run) ----
export QUESTA_HOME="/tools/intelFPGA_pro/22.4/questa_fse"
export PATH="$QUESTA_HOME/bin:$PATH"

# ---- License ----
export LM_LICENSE_FILE="/tools/intelFPGA_pro/22.4/LR-155147_License.dat"

echo "Environment loaded."
echo "riscv32-unknown-elf-gcc -> $(command -v riscv32-unknown-elf-gcc || echo MISSING)"
echo "vsim -> $(command -v vsim || echo MISSING)"
echo "LM_LICENSE_FILE=${LM_LICENSE_FILE:-<unset>}"