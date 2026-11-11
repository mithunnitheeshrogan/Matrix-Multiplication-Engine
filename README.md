# Matrix Multiplication Engine in Verilog

A parameterized **N×N matrix multiplication engine** (C = A × B) in Verilog, implemented in two architectures and verified with a self-checking testbench:

- **Sequential**: one multiply-accumulate (MAC) unit driven by an FSM
- **Pipelined**: N parallel multipliers plus an adder stage, producing one output element per cycle

Both engines have the same interface, so the same testbench drives and checks them side by side.

## Results at a glance

| | Sequential | Pipelined |
|---|---|---|
| Multipliers | 1 | N |
| Cycles, 4×4 (measured) | 81 | 17 |
| Cycles, 8×8 (measured) | 577 | 65 |
| Cycle formula | N³ + N² + 1 | N² + 1 |
| Throughput | one MAC per cycle | one output element per cycle |
| Trade-off | smallest area, slowest | ~4.7× faster at 4×4 for N× the multipliers |

Cycles are counted from the end of the `start` pulse to the cycle `done` is raised. Area and timing have not been measured yet (see [Status](#status-and-limitations)).

## Architecture

### Sequential engine (`matmul_seq.v`)

An FSM (`IDLE → MAC → WRITE → FIN`) steps through three nested loops over `i`, `j`, `k`:

```
for i in 0..N-1
  for j in 0..N-1
    acc = 0
    for k in 0..N-1
      acc += A[i][k] * B[k][j]
    C[i][j] = acc
```

One multiplier and one accumulator are reused for every element, so this version has the lowest hardware cost and the longest latency.

### Pipelined engine (`matmul_pipe.v`)

Computing one output element is a dot product of a row of A and a column of B, and the pipeline performs it in two stages:

1. **Stage 1:** N products `A[i][k] * B[k][j]` are computed in parallel and registered.
2. **Stage 2:** the N products are summed (sum-of-products accumulate) and written into `C[i][j]`.

A new output element enters the pipeline every cycle, so after the pipeline fills, one element of C completes per clock.

### Data widths

Elements are **unsigned**, `DW` bits wide (default 8). The accumulator is `AW = 2·DW + ⌈log2 N⌉` bits (18 bits for 8-bit, 4×4), which is enough for the worst case. For example, with every element equal to 255 each result is 4 × 255² = 260,100, which fits in 18 bits.

## Interface

Both modules share the same ports.

| Port | Dir | Description |
|---|---|---|
| `clk` | in | Clock |
| `rst_n` | in | Asynchronous reset, active low |
| `start` | in | One-cycle pulse; latches A and B and begins the operation |
| `a_flat` | in | Matrix A, `A[i][k]` at `[(i*N+k)*DW +: DW]` |
| `b_flat` | in | Matrix B, `B[k][j]` at `[(k*N+j)*DW +: DW]` |
| `c_flat` | out | Result C, `C[i][j]` at `[(i*N+j)*AW +: AW]` |
| `busy` | out | High while an operation is in progress |
| `done` | out | One-cycle pulse when `c_flat` is valid; `busy` falls in the same cycle |

Parameters: `N` (matrix size, default 4), `DW` (element width, default 8), `AW` (derived accumulator width).

Behaviour:
- Inputs are latched when `start` is accepted, so `a_flat` / `b_flat` may change afterwards.
- A `start` pulse while the engine is busy is ignored.
- Reset aborts any operation in progress and clears `busy`, `done` and `c_flat`.

## Repository structure

```
.
├── matmul_seq.v      Sequential engine
├── matmul_pipe.v     Pipelined engine
├── tb_matmul.v       Self-checking testbench (drives both engines)
├── run.do            ModelSim: compile, simulate, add waves, run
├── run_cov.do        ModelSim: same flow with code coverage (needs a coverage license)
├── docs/             Screenshots (transcript output, waveform)
└── README.md
```

## How to run

### ModelSim

Put all files in one folder, then in the ModelSim transcript:

```tcl
cd {path/to/this/folder}
do run.do
```

`run.do` creates the library, compiles the design and testbench, adds a grouped waveform and runs to completion. A passing run ends with `ALL 24 TESTS PASSED`.

### Options

- **Print every test's matrices:** add `+SHOW_ALL` (for example `vvp sim +SHOW_ALL`, or `vsim -voptargs=+acc work.tb_matmul +SHOW_ALL` in ModelSim). Tests 1 to 4 always print their matrices.
- **Matrix size:** change `parameter N` in `tb_matmul.v` (tested with 4 and 8). The hard-coded golden result in test 1 applies to 4×4 only and is skipped for other sizes.

## Verification

`tb_matmul.v` drives both engines with identical inputs, then checks each result against a behavioural reference model computed in the testbench.

| Test | What it checks |
|---|---|
| **Predefined matrices** (A = 1..16, B = 16..1) | Result matches a hard-coded golden matrix (computed independently) |
| **A × Identity** | Values are routed to the correct positions |
| **All 255** | Worst-case values; the accumulator does not overflow (260,100 per element) |
| **All zeros** | Smallest result; nothing carries over from the previous run |
| **10 random matrices** | General correctness against the reference model |
| **Start while busy** (4 timings) | An extra `start` with corrupted inputs is ignored: no re-run, no extra `done` |
| **Reset mid-operation** (3 timings) | Outputs clear, no late `done` or writes, and the next operation is correct |
| **Protocol monitors** (every cycle) | `done` is a single-cycle pulse, follows `busy`, and `busy` falls with it |

That is 24 tests in total. The checks were also validated by deliberately breaking the RTL (for example accepting `start` while busy, or not returning to idle on reset) and confirming the testbench reports a failure.

### Example output

```
  ===== 1: A=1..16, B=16..1 =====
  Matrix A (4x4):
        1     2     3     4
        5     6     7     8
        9    10    11    12
       13    14    15    16
  Matrix B (4x4):
       16    15    14    13
       12    11    10     9
        8     7     6     5
        4     3     2     1
  Result C = A x B  (sequential engine):
         80      70      60      50
        240     214     188     162
        400     358     316     274
        560     502     444     386
  Pipelined engine output matches the sequential one

PASS [1: A=1..16, B=16..1]  seq: 81 cycles | pipe: 17 cycles
...
ALL 24 TESTS PASSED
```

## Author

Mithun Nitheesh Rogan R
