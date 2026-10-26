# Lab 3, Part 4: APB Slave on the FP8 8x8 Matmul

Run everything from the `part4` directory.

```
source env.cshrc     # VCS / Verdi paths (csh)
make                 # compile and run the APB testbench with VCS (all tests)
make waves           # compile with FSDB, run, and open Verdi on the exception test
make view-waves      # re-open the last FSDB without re-running
make vl              # compile and run with Verilator (no VCS needed)
make clean           # remove build files
```
