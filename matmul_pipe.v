`timescale 1ns/1ps
// ============================================================
// Pipelined Matrix Multiplication Engine  (C = A x B)
// N parallel multipliers + adder tree, one C element per cycle.
//   Stage 1 : N parallel products  A[i][k]*B[k][j]  -> registers
//   Stage 2 : sum-of-products (accumulate) + store into C
// Latency ~ N^2 + 3 cycles, throughput = 1 output element / cycle.
// ============================================================
module matmul_pipe #(
    parameter N  = 4,
    parameter DW = 8,
    parameter PW = 2*DW,                    // product width
    parameter AW = 2*DW + $clog2(N)
)(
    input                    clk,
    input                    rst_n,
    input                    start,
    input  [N*N*DW-1:0]      a_flat,
    input  [N*N*DW-1:0]      b_flat,
    output reg [N*N*AW-1:0]  c_flat,
    output reg               busy,
    output reg               done
);
    localparam IW = $clog2(N) + 1;

    reg [DW-1:0]  A [0:N*N-1];
    reg [DW-1:0]  B [0:N*N-1];
    reg [IW-1:0]  i, j;
    reg           running;

    // ---- stage 1 registers ----
    reg [N*PW-1:0] p_flat;                  // N partial products
    reg            v1, last1;
    reg [2*IW-1:0] idx1;                    // output index (i*N+j)

    // ---- stage 2 combinational accumulate ----
    reg [AW-1:0] sum_c;
    integer k, n, ks;
    always @* begin
        sum_c = {AW{1'b0}};
        for (ks = 0; ks < N; ks = ks + 1)
            sum_c = sum_c + p_flat[ks*PW +: PW];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 1'b0; busy <= 1'b0; done <= 1'b0;
            v1 <= 1'b0; last1 <= 1'b0; idx1 <= 0;
            i <= 0; j <= 0;
            p_flat <= {(N*PW){1'b0}};
            c_flat <= {(N*N*AW){1'b0}};
        end else begin
            done <= 1'b0;
            v1   <= 1'b0;

            // ---------- stage 2: accumulate + write ----------
            if (v1) begin
                c_flat[idx1*AW +: AW] <= sum_c;
                if (last1) begin done <= 1'b1; busy <= 1'b0; end
            end

            // ---------- control / stage 1: issue ----------
            if (!running && !busy && start) begin
                for (n = 0; n < N*N; n = n + 1) begin
                    A[n] <= a_flat[n*DW +: DW];
                    B[n] <= b_flat[n*DW +: DW];
                end
                i <= 0; j <= 0;
                running <= 1'b1;
                busy    <= 1'b1;
            end else if (running) begin
                for (k = 0; k < N; k = k + 1)
                    p_flat[k*PW +: PW] <= A[i*N + k] * B[k*N + j];
                v1    <= 1'b1;
                idx1  <= i*N + j;
                last1 <= (i == N-1) && (j == N-1);
                if (j == N-1) begin
                    j <= 0;
                    if (i == N-1) running <= 1'b0;
                    else          i <= i + 1'b1;
                end else j <= j + 1'b1;
            end
        end
    end
endmodule
