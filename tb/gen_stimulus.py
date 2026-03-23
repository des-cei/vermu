# Copy file to .../script
import sys
import re
import random

def parse_assembly(input_file, output_txt, target_function="main"):
    # 1. Matches hex instructions: "    3ef0:    02810e27     vs1r.v    v28,(sp)"
    instr_pattern = re.compile(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+([a-zA-Z0-9\.]+)")
    
    # 2. Matches objdump function headers: "80000120 <main>:"
    objdump_func_pattern = re.compile(r"^[0-9a-fA-F]+\s+<([a-zA-Z0-9_]+)>:")
    
    # 3. Matches raw assembly labels: "main:"
    raw_label_pattern = re.compile(r"^([a-zA-Z0-9_]+):$")
    
    # The exact 7-bit RISC-V opcodes for your VPU
    valid_opcodes = {0x07, 0x27, 0x57, 0x73}
    
    inside_target = False
    captured_count = 0

    with open(output_txt, 'w') as out_f, open(input_file, 'r') as in_f:
        for line in in_f:
            # Check if we are crossing a function boundary
            func_match = objdump_func_pattern.search(line)
            label_match = raw_label_pattern.search(line)
            
            if func_match:
                func_name = func_match.group(1)
                inside_target = (func_name == target_function)
                continue
                
            if label_match:
                func_name = label_match.group(1)
                inside_target = (func_name == target_function)
                continue
            
            # If we are inside 'main', look for vector instructions
            if inside_target:
                match = instr_pattern.search(line)
                if match:
                    instr_hex = match.group(1)
                    mnemonic = match.group(2)
                    opcode = int(instr_hex, 16) & 0x7F
                    
                    if opcode in valid_opcodes:
                        # Random data for RS1 and RS2 ports
                        rs1_val = f"{random.randint(0, 0xFFFFFFFF):08x}"
                        rs2_val = f"{random.randint(0, 0xFFFFFFFF):08x}"
                        
                        out_f.write(f"{instr_hex} {rs1_val} {rs2_val} {mnemonic}\n")
                        captured_count += 1
                        
    print(f"Stimulus generated: {captured_count} instructions captured from '{target_function}'.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 gen_stimulus.py <input.S or .dump> <output.txt>")
        sys.exit(1)
    # You can change "main" here if you ever want to target a specific C function
    parse_assembly(sys.argv[1], sys.argv[2], target_function="main")
