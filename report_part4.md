# Part 4: APB slave interface (report text)

## 1. Description of changes

Part 3 gave us an 8x8 FP8 matrix multiplier (four 4x4 systolic blocks) with a `flags` output that ORs the exception flags of all 64 MACs, six RAMs (A, B and C, two 32-bit blocks each) and a small control FSM that took `start` and the address/stride pins directly. In Part 4 the FSM is removed and an APB slave takes its place, so a CPU can control and observe the matmul through registers.

**New file: `apb_slave.sv`.** It holds the control and status registers and talks APB on one side and to the matmul on the other.
- A write happens on the clock edge where `PSEL`, `PENABLE` and `PWRITE` are all 1 (the access phase). `PADDR` picks the register and `PWDATA` is stored.
- `PREADY` is tied to 1, so every transfer is two cycles (setup, access) with no wait states.
- `PRDATA` is a mux on `PADDR`: it returns `done` for address 7, `flags` for address 8, and 0 otherwise.
- Writing 1 to bit 0 of `CTRL` produces a one-cycle `start` pulse. Nothing is stored for `CTRL`.
- `done` and `flags` come from the matmul as short pulses. A CPU polling over APB would miss them, so the slave holds them in two sticky bits (`done_q`, `flags_q`). Both are cleared when a new start is written.
- No separate state machine is used. The transfer takes effect on the access-phase edge, so the three bus signals are enough.

**Changed file: `matmul_8x8_with_ram.sv`** (top module `matrix_multiplication`).
- Removed the control FSM and the `start`, `done`, `address_mat_*` and `address_stride_*` ports.
- Added the APB ports `PCLK`, `PRESETn`, `PADDR`, `PWRITE`, `PSEL`, `PENABLE`, `PWDATA`, `PRDATA` and `PREADY`. `PADDR` is 4 bits and the data is 16 bits. `pe_resetn` and the external RAM ports are kept so the testbench can load and read the RAMs.
- Instantiated `apb_slave`. Its address and stride outputs go straight to the matmul, and the matmul's `done` and `flags` go into it.
- The matmul needs `start_mat_mul` held high until it finishes, but the APB start is a one-cycle pulse. A small flop is set by the pulse and cleared by `done_mat_mul`.
- `PCLK` and `PRESETn` drive the clock and reset of the whole design.

**Unchanged:** `matmul_8x8.sv` (it already exports `flags`, so the slave just reads that signal), `matmul.sv` (4x4 systolic array with the FP8 MAC), `FPMult.sv` and `FPAddSub.sv`.

**Testbench: `matmul_8x8_with_ram_tb.sv`.** It plays the CPU. It loads A and B into the RAMs through the external RAM ports, then does the sequence the lab describes with `apb_write` and `apb_read` tasks:
1. Write `ADDR_A/B/C` and `STRIDE_A/B/C`.
2. Write `CTRL` with bit 0 set.
3. Read `DONE` until it is 1.
4. Read `FLAGS`.
5. Read C back from the RAM and compare it with the expected product.

Tests: all zeros, all ones, a worked example, B = identity, A = identity, 10 random sets, a set with non-zero base addresses (A at 16, B at 32, C at 48) and an overflow set where every element is 15.5 (`0x6F`). In all but the last, `FLAGS` must read 0. In the overflow test every product overflows, `FLAGS` must read 1, and only the flag is checked. The overflow test runs last, after a reset, so the registers start at 0 in its waveform.

## 2. APB register map

All registers are 16 bits wide. `PADDR` is the register number (word-indexed). Write-only registers read back as 0. Writes to unused addresses are ignored, and reads from them return 0.

| PADDR | Name | Access | Bits | Description |
|---|---|---|---|---|
| 0x0 | CTRL | W | [0] | Write 1 to start the matmul. Self-clearing: it makes a one-cycle `start` pulse and nothing is stored. Also clears `DONE` and `FLAGS`. |
| 0x1 | ADDR_A | W | [9:0] | `address_mat_a`: where matrix A starts in its RAM. |
| 0x2 | ADDR_B | W | [9:0] | `address_mat_b`: where matrix B starts in its RAM. |
| 0x3 | ADDR_C | W | [9:0] | `address_mat_c`: where matrix C is written. |
| 0x4 | STRIDE_A | W | [7:0] | `address_stride_a`: address step between rows of A. |
| 0x5 | STRIDE_B | W | [7:0] | `address_stride_b`: address step between rows of B. |
| 0x6 | STRIDE_C | W | [7:0] | `address_stride_c`: address step between rows of C. |
| 0x7 | DONE | R | [0] | 1 when the matmul has finished. Stays 1 until the next start. |
| 0x8 | FLAGS | R | [0] | 1 if any FP8 exception (overflow, underflow, invalid, ...) happened during the run. Stays 1 until the next start. |

Bits [15:1] of `DONE` and `FLAGS` read as 0. All registers reset to 0.

Usage: write the six address and stride registers, write 1 to `CTRL`, read `DONE` until it is 1, then read `FLAGS`. The testbench uses `ADDR_*` = 0 (or 16/32/48 in the non-zero base test) and `STRIDE_*` = 1.
