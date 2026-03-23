# VERMU
VERMU is a Vector Processing Unit (VPU) based on the RISC-V Zve32x vector extension, designed for embedded acceleration. It is integrated within the [X-Heep](https://github.com/x-heep/x-heep) 
 platform via the XIF v1.0 interface and OBI protocol.

To enable autovectorization, the RISC-V GNU Compiler Toolchain (GCC v15) is required. The following toolchain configuration is needed to target this VPU:
```
./configure \
--target=riscv32-unknown-elf \
--prefix=/tools/rv32imc_zve32x_zvl128b \
--with-arch=rv32imc_zve32x_zvl128b \
--with-abi=ilp32 \
--enable-multilib \
--with-cmodel=medlow
```
