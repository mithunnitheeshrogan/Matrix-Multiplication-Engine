`timescale 1ns/1ps
// ============================================================
// Sequential Matrix Multiplication Engine  (C = A x B)
// One MAC unit, triple nested loop (i, j, k) driven by an FSM.
// Unsigned DW-bit elements, N x N matrices.
// Latency ~ N^3 + N^2 + 2 cycles.  Area: 1 multiplier + 1 adder.
// ============================================================
module matmul_seq #(
    parameter N  = 4,                       // matrix dimension
    parameter DW = 8,                       // element width
    parameter AW = 2*DW + $clog2(N)         // accumulator width (no overflow)
)(
    input                    clk,
    input                    rst_n,
    input                    start,         // 1-cycle pulse, latches A and B
    input  [N*N*DW-1:0]      a_flat,        // A[i][k] at [(i*N+k)*DW +: DW]
    input  [N*N*DW-1:0]      b_flat,        // B[k][j] at [(k*N+j)*DW +: DW]
    output reg [N*N*AW-1:0]  c_flat,        // C[i][j] at [(i*N+j)*AW +: AW]
    output reg               busy,
    output reg               done           // 1-cycle pulse, C is valid
);
    localparam IW = $clog2(N) + 1;

    localparam IDLE = 2'd0, MAC = 2'd1, WRITE = 2'd2, FIN = 2'd3;

    reg [1:0]     state;
    reg [DW-1:0]  A [0:N*N-1];
    reg [DW-1:0]  B [0:N*N-1];
    reg [IW-1:0]  i, j, k;
    reg [AW-1:0]  acc;                      // sum-of-products accumulator
    integer       n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            acc    <= {AW{1'b0}};
            c_flat <= {(N*N*AW){1'b0}};
            i <= 0; j <= 0; k <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    for (n = 0; n < N*N; n = n + 1) begin
                        A[n] <= a_flat[n*DW +: DW];
                        B[n] <= b_flat[n*DW +: DW];
                    end
                    i <= 0; j <= 0; k <= 0;
                    acc   <= {AW{1'b0}};
                    busy  <= 1'b1;
                    state <= MAC;
                end

                MAC: begin                  // acc += A[i][k] * B[k][j]
                    acc <= acc + A[i*N + k] * B[k*N + j];
                    if (k == N-1) state <= WRITE;
                    else          k     <= k + 1'b1;
                end

                WRITE: begin                // store C[i][j], advance j then i
                    c_flat[(i*N + j)*AW +: AW] <= acc;
                    acc <= {AW{1'b0}};
                    k   <= 0;
                    if (j == N-1) begin
                        j <= 0;
                        if (i == N-1) state <= FIN;
                        else begin i <= i + 1'b1; state <= MAC; end
                    end else begin
                        j <= j + 1'b1;
                        state <= MAC;
                    end
                end

                FIN: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
