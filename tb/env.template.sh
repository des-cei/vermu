#!/usr/bin/env bash
# Environment template for VPU unit-test flow.
# Copy to tb/env.sh and adapt paths to your local machine.

# ---- RISC-V toolchain (required for build-sw) ----
export RISCV_XHEEP=/tools/rv32imc_zve32x_zvl128b
export PATH=/tools/rv32imc_zve32x_zvl128b/bin:$PATH

# ---- License ----
# Keep generic pattern for 22.4 installs; replace if your setup differs.
export LM_LICENSE_FILE=/tools/intelFPGA_pro/22.4/*.dat

# ---- Questa/ModelSim (required for build-sim/run) ----
export MODEL_TECH=/tools/intelFPGA_pro/22.4/questa_fse/bin
export PATH=$PATH:/tools/intelFPGA_pro/22.4/questa_fse/bin

# Activate conda environment
conda activate core-v-mini-mcu

echo "Environment loaded."
echo "riscv32-unknown-elf-gcc -> $(command -v riscv32-unknown-elf-gcc || echo MISSING)"
echo "vsim -> $(command -v vsim || echo MISSING)"
echo "LM_LICENSE_FILE=${LM_LICENSE_FILE:-<unset>}"
