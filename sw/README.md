## Softeware Execution

There are two types of applications to test the VPU: data parallel kernels and testbench application for module validation. 

For the easiness of instruction deploying the following mechanism has been mounted. 
1. Compile application: `make build-sw PROJECT=vpu_xif_decoder`
2. With this compiled instructions recorded in main.S. For practicity to test modules with gen_stimulus.py, compiled instructions are extracted to *stimulus.txt*, which is injeted test bench.
There are two options for module testing: 
    1. to test each module with `make run-questa-tb TB_TOP=<under-test-tb>`. 
    2. Test of the whole vpu with instructions deployed through the Core-V Extension Interface.

# VPU Verification Flow

Two types of applications can be used to validate the Vector Processing Unit (VPU):

- **Data-parallel kernels**, used to evaluate vector processing functionality and performance.
- **Test applications**, used to validate individual hardware modules and verify instruction decoding and execution (`tb/`).

To simplify instruction deployment and simulation, a workflow has been implemented to automatically extract compiled instructions and inject them into the testbench environment.

## Software Compilation

Compile the desired application using:

```bash
make build-sw PROJECT=<project_name>
```

After compilation, the generated assembly code is available in `main.S`.

## Stimulus Generation

To facilitate module-level verification, the script `gen_stimulus.py` extracts the relevant instructions from `main.S` and generates a `stimulus.txt` file.

The resulting `stimulus.txt` file is used as input stimulus for the simulation testbenches, allowing the execution of realistic instruction streams without manually encoding instructions.

Flow summary:

## Simulation Options

### 1. Module-Level Validation

Individual hardware modules can be verified independently using dedicated testbenches.

Run:

```bash
make run-questa-tb PROJECT=<project_name> TB_TOP=<under-test-tb> 
```
<!-- If only certain VPU modules are wanted to  be compiled, SIM_FILES="<compiled-file>>" must be applied. -->

For example:

```bash
make run-questa-tb TB_TOP=tb_vpu_decoder
```

In this mode, instructions contained in `stimulus.txt` are injected directly into the module under test.

### 2. Full VPU Validation

The complete VPU can be verified through an end-to-end simulation environment.

In this configuration, instructions are delivered through the Core-V Extension Interface (XIF), exercising the entire execution flow:

This mode provides a more realistic verification environment and validates the integration of all VPU components.

## Typical Workflow

```bash
# Run module-level simulation
make run-questa-tb TB_TOP=tb_vpu_decoder

# Or run full VPU simulation
make run-vpu-unit
```