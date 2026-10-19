# `dispatch_sideband_t` — per-fragment sideband

Defined in [include/vpu_pkg.sv.tpl](include/vpu_pkg.sv.tpl). Built by the dispatcher
([vpu_dispatch.sv](vpu_dispatch.sv), `dispatch_last[i]`) for every fragment it issues to a
functional unit (VALU, VLSU, VSLD). It travels in two places:

- `vpu_compl_issue_t.instr_fragment` — **issue interface** (`wrapper_exe_instr_issue`)
- `vpu_issue_fifo_res_t.instr_fragment` — **result interface** (`exe_wrapper_result`)

On issue it tells the FU and the register file *what to compute and what to read*; on result
it tells the register file *where to write* and the dispatcher *what has completed*.

A vector instruction is split into `total_frags` fragments. Each fragment covers one DW-wide
row of one vector register; a register holds `FRAGS_PER_REG` rows and a register group
holds `EMUL` registers.

## Fields

| Field | Value set by the dispatcher | Meaning |
|---|---|---|
| `next_frag` | `slot_q.next_frag` | Index of this fragment inside the instruction (0 … `total_frags-1`) |
| `is_last` | `next_frag == total_frags-1` | Last fragment of the instruction |
| `elem_base` | `next_frag * epf(esew)` | Global index of the first element processed in this step |
| `elements` | `calc_elements_for_frag(vl, …)` | Number of active elements in this step (≤ `epf`, smaller in the `vl` tail) |
| `dispatch_vd/vs1/vs2` | `base + next_frag / FRAGS_PER_REG` | Physical vector register used in this step |
| `row_vd/vs1/vs2` | `next_frag % FRAGS_PER_REG` | Row (fragment) inside that register |
| `dispatch_raddr1` | `'0` | Unused. The memory offset is now derived by the LSU from `elem_base` |
| `vd_frag` | `next_frag` (`0` for reductions) | Bit index in the producer's `frag_done_mask` |
| `vd_frag_done` | `1` (`is_last` for reductions) | This write completes `vd_frag`; consumers may read it |

### Reductions

`calc_view()` ([vpu_dispatch.sv](vpu_dispatch.sv)) overrides the default lockstep view:
`vs1` and `vd` stay on the base register, row 0 (they are scalars, EMUL=1). `vd` holds a
partial sum until the end, so `vd_frag` is fixed at 0 and `vd_frag_done` is only asserted
on the last step. `vs2` walks the group normally.

## Issue interface (`wrapper_exe_instr_issue.instr_fragment`)

Driven by the dispatcher, consumed by:

- **Register file — operand read** ([vpu_vregfile.sv](vpu_vregfile.sv), `read_data`)
  - Reads `vreg[vsX][issue_frag.row_vsX]`.
  - `vs1`/`vs2` are ANDed with `active_elements_mask(…, row, elements)`.
  - `vd` is read unmasked as `old_vd`, needed for the undisturbed policy.
- **VALU** ([vpu_simd_controller.sv](vpu_simd_controller.sv)): `elements` → `iter_vl`.
- **VLSU** ([obi_lsu_top.sv](obi_lsu_top.sv))
  - Address per port: `rs1 + (elem_base + port*elements_per_port) * stride`.
  - `elements` sets how many beats are issued.
- **VSLD / reductions** ([vpu_sldu.sv](vpu_sldu.sv))
  - `next_frag == 0` selects the initial accumulator: `vs1[0]` on the first step, the
    partial sum in `vd` afterwards.
  - Also uses `is_last` and `elements`.
- **Dispatcher — hazard check** (before issue)
  - Builds the same view (`vsX`, `row_vsX`) for the candidate fragment.
  - For RAW (vs1, vs2, vd as source) and WAW against every older in-flight producer `p`:
    `fg = (vsX - p.vd_base) * FRAGS_PER_REG + row_vsX`.
  - If `p.frag_done_mask[fg]` is not set, the issue stalls.

## Result interface (`exe_wrapper_result.instr_fragment`)

All three FUs currently forward the issue sideband unchanged
([vpu_simd_controller.sv](vpu_simd_controller.sv), [obi_lsu_top.sv](obi_lsu_top.sv),
[vpu_sldu.sv](vpu_sldu.sv)). Consumed by:

- **Register file — writeback** ([vpu_vregfile.sv](vpu_vregfile.sv), `write_data` /
  `merge_write_data`)
  - Writes `vreg[dispatch_vd][row_vd]`.
  - Inside the row, a byte with global index `g` is overwritten only if
    `elem_base <= g < elem_base + elements`, subject to the usual vstart / tail (`vta`) /
    mask (`vma`) rules. Every other byte keeps `old_vd`.
  - This allows partial rows (the `vl` tail and, later, narrowing).
- **Register file — register indices**: `raddr1`, `raddr2` and `vd` are taken from the
  result-side `dispatch_vX`, while the rows come from the issue side. This only works because
  both are identical (pass-through).
- **Dispatcher — scoreboard**
  - `vd_frag_done` → set `frag_done_mask[vd_frag]`, unblocking waiting consumers on the
    next cycle.
  - `is_last` → free the slot (`valid = 0`).

## Caveat

Because the result sideband is just the issue sideband passed through, it is only correct
while the dispatcher holds `instr_fragment` stable until the FU returns its result. Today
`next_frag` only advances on `fu_instr_valid`, so this holds. If an FU becomes pipelined, or
the LSU accepts a new fragment before the previous load data returns, the FU must register
the sideband and return it with its own result. Reading the register indices from
`issue_frag` in the register file would also make the two sides consistent.
