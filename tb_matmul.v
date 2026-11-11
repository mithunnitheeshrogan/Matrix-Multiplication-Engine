`timescale 1ns/1ps
// ============================================================
// Self-checking testbench for matmul_seq and matmul_pipe
//  - directed tests (golden, identity, all-255, zeros)
//  - random tests vs behavioural reference
//  - protocol monitors (done pulse rules)
//  - start-while-busy test  (extra start pulses must be ignored)
//  - reset-mid-operation test (engine must abort and recover)
// ============================================================
module tb_matmul;
    parameter N  = 4;
    parameter DW = 8;
    parameter AW = 2*DW + $clog2(N);

    reg clk = 0, rst_n = 0, start = 0;
    reg  [N*N*DW-1:0] a_flat, b_flat;
    wire [N*N*AW-1:0] c_seq, c_pipe;
    wire busy_s, done_s, busy_p, done_p;

    matmul_seq  #(.N(N), .DW(DW)) u_seq  (clk, rst_n, start, a_flat, b_flat, c_seq,  busy_s, done_s);
    matmul_pipe #(.N(N), .DW(DW)) u_pipe (clk, rst_n, start, a_flat, b_flat, c_pipe, busy_p, done_p);

    always #5 clk = ~clk;                   // 100 MHz

    integer errors = 0, tests = 0;
    integer done_cnt_s = 0, done_cnt_p = 0;
    integer cyc_s, cyc_p;
    reg     got_s, got_p;
    reg [AW-1:0] ref_c  [0:N*N-1];
    reg [AW-1:0] golden [0:N*N-1];

    // ------------------------------------------------------------
    // Protocol monitors (checked every clock, outside reset)
    //   * done is a single-cycle pulse
    //   * done is only seen after busy was high, and busy drops with it
    // ------------------------------------------------------------
    reg busy_s_d = 0, busy_p_d = 0, done_s_d = 0, done_p_d = 0;
    always @(posedge clk) begin
        busy_s_d <= busy_s;  busy_p_d <= busy_p;
        done_s_d <= done_s;  done_p_d <= done_p;
        if (rst_n) begin
            if (done_s) begin
                done_cnt_s = done_cnt_s + 1;
                if (!busy_s_d) begin $display("MONITOR FAIL: SEQ done without prior busy @%0t", $time); errors = errors + 1; end
                if (busy_s)    begin $display("MONITOR FAIL: SEQ busy still high with done @%0t", $time); errors = errors + 1; end
                if (done_s_d)  begin $display("MONITOR FAIL: SEQ done longer than 1 cycle @%0t", $time); errors = errors + 1; end
            end
            if (done_p) begin
                done_cnt_p = done_cnt_p + 1;
                if (!busy_p_d) begin $display("MONITOR FAIL: PIPE done without prior busy @%0t", $time); errors = errors + 1; end
                if (busy_p)    begin $display("MONITOR FAIL: PIPE busy still high with done @%0t", $time); errors = errors + 1; end
                if (done_p_d)  begin $display("MONITOR FAIL: PIPE done longer than 1 cycle @%0t", $time); errors = errors + 1; end
            end
        end
    end

    // ------------------------------------------------------------
    // Readable views of the flat buses (for the waveform window).
    // Index n = i*N + j  (row-major):  A_view[n] = A[i][j], etc.
    // ------------------------------------------------------------
    reg [DW-1:0] A_view      [0:N*N-1];
    reg [DW-1:0] B_view      [0:N*N-1];
    reg [AW-1:0] C_seq_view  [0:N*N-1];
    reg [AW-1:0] C_pipe_view [0:N*N-1];
    integer vi;
    always @(a_flat or b_flat or c_seq or c_pipe)
        for (vi = 0; vi < N*N; vi = vi + 1) begin
            A_view[vi]      = a_flat[vi*DW +: DW];
            B_view[vi]      = b_flat[vi*DW +: DW];
            C_seq_view[vi]  = c_seq [vi*AW +: AW];
            C_pipe_view[vi] = c_pipe[vi*AW +: AW];
        end

    // ------------------------------------------------------------
    // Transcript printing: A, B, C = A x B, optional per-element maths
    // ------------------------------------------------------------
    reg show_all;                           // vsim ... +SHOW_ALL prints every test

    task print_matrices(input [255:0] name, input verbose);
        integer i, j, k;
        begin
            $display("");
            $display("  ===== %0s =====", name);
            $display("  Matrix A (%0dx%0d):", N, N);
            for (i = 0; i < N; i = i + 1) begin
                $write("   ");
                for (j = 0; j < N; j = j + 1) $write("%6d", a_flat[(i*N+j)*DW +: DW]);
                $write("\n");
            end
            $display("  Matrix B (%0dx%0d):", N, N);
            for (i = 0; i < N; i = i + 1) begin
                $write("   ");
                for (j = 0; j < N; j = j + 1) $write("%6d", b_flat[(i*N+j)*DW +: DW]);
                $write("\n");
            end
            $display("  Result C = A x B  (sequential engine):");
            for (i = 0; i < N; i = i + 1) begin
                $write("   ");
                for (j = 0; j < N; j = j + 1) $write("%8d", c_seq[(i*N+j)*AW +: AW]);
                $write("\n");
            end
            $display("  Pipelined engine output %0s the sequential one",
                     (c_seq === c_pipe) ? "matches" : "DIFFERS from");
            if (verbose) begin
                $display("  Element-by-element (row of A . column of B):");
                for (i = 0; i < N; i = i + 1)
                    for (j = 0; j < N; j = j + 1) begin
                        $write("    C[%0d][%0d] = ", i, j);
                        for (k = 0; k < N; k = k + 1) begin
                            if (k > 0) $write(" + ");
                            $write("%0d*%0d", a_flat[(i*N+k)*DW +: DW], b_flat[(k*N+j)*DW +: DW]);
                        end
                        $display(" = %0d", c_seq[(i*N+j)*AW +: AW]);
                    end
            end
            $display("");
        end
    endtask

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    task set_a(input integer i, input integer k, input integer v);
        a_flat[(i*N+k)*DW +: DW] = v;
    endtask
    task set_b(input integer k, input integer j, input integer v);
        b_flat[(k*N+j)*DW +: DW] = v;
    endtask

    task randomize_inputs;
        integer i, j;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    set_a(i, j, $urandom_range(0, 255));
                    set_b(i, j, $urandom_range(0, 255));
                end
        end
    endtask

    task compute_ref;                       // behavioural reference model
        integer i, j, k;
        reg [AW-1:0] s;
        begin
            for (i = 0; i < N; i = i + 1)
                for (j = 0; j < N; j = j + 1) begin
                    s = 0;
                    for (k = 0; k < N; k = k + 1)
                        s = s + a_flat[(i*N+k)*DW +: DW] * b_flat[(k*N+j)*DW +: DW];
                    ref_c[i*N+j] = s;
                end
        end
    endtask

    task pulse_start;                       // 1-cycle start, aligned to negedge
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
        end
    endtask

    integer base_s = 0, base_p = 0;         // done counters before the operation

    task wait_done;                         // waits for both engines
        integer t;
        begin
            got_s = (done_cnt_s > base_s);
            got_p = (done_cnt_p > base_p);
            cyc_s = 0; cyc_p = 0; t = 0;
            while ((!got_s || !got_p) && t < 2000) begin
                @(posedge clk); t = t + 1;
                if (!got_s) cyc_s = cyc_s + 1;
                if (!got_p) cyc_p = cyc_p + 1;
                #1;
                if (done_s || done_cnt_s > base_s) got_s = 1;
                if (done_p || done_cnt_p > base_p) got_p = 1;
            end
            if (!got_s || !got_p) begin
                $display("FAIL: timeout (seq done=%b pipe done=%b)", got_s, got_p);
                errors = errors + 1;
            end
        end
    endtask

    task check_results(input [255:0] name, input use_golden);
        integer n;
        reg [AW-1:0] vs, vp;
        begin
            for (n = 0; n < N*N; n = n + 1) begin
                vs = c_seq [n*AW +: AW];
                vp = c_pipe[n*AW +: AW];
                if (vs !== ref_c[n]) begin
                    $display("FAIL [%0s] SEQ  C[%0d][%0d] = %0d, expected %0d", name, n/N, n%N, vs, ref_c[n]);
                    errors = errors + 1;
                end
                if (vp !== ref_c[n]) begin
                    $display("FAIL [%0s] PIPE C[%0d][%0d] = %0d, expected %0d", name, n/N, n%N, vp, ref_c[n]);
                    errors = errors + 1;
                end
                if (use_golden && ref_c[n] !== golden[n]) begin
                    $display("FAIL [%0s] reference model disagrees with golden at %0d", name, n);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // one full operation: start, wait, compare
    task run_test(input [255:0] name, input use_golden);
        integer e0;
        begin
            tests = tests + 1; e0 = errors;
            base_s = done_cnt_s; base_p = done_cnt_p;
            compute_ref;
            pulse_start;
            wait_done;
            check_results(name, use_golden);
            repeat (3) @(posedge clk);              // let the monitors settle
            if (done_cnt_s != base_s + 1 || done_cnt_p != base_p + 1) begin
                $display("FAIL [%0s] expected exactly one done pulse per engine", name);
                errors = errors + 1;
            end
            if (show_all || tests <= 4) print_matrices(name, tests == 1);
            $display("%0s [%0s]  seq: %0d cycles | pipe: %0d cycles",
                     (errors == e0) ? "PASS" : "FAIL", name, cyc_s, cyc_p);
        end
    endtask

    // ------------------------------------------------------------
    // Extra test 1: a second start pulse (with corrupted inputs)
    // arrives while the engines are busy. It must be ignored.
    // ------------------------------------------------------------
    task test_start_while_busy(input integer offset);
        integer e0;
        begin
            tests = tests + 1; e0 = errors;
            base_s = done_cnt_s; base_p = done_cnt_p;
            randomize_inputs;
            compute_ref;
            pulse_start;
            repeat (offset) @(negedge clk);
            if (!busy_s || !busy_p) begin
                $display("FAIL: engines not busy at offset %0d (seq=%b pipe=%b)", offset, busy_s, busy_p);
                errors = errors + 1;
            end
            a_flat = ~a_flat;  b_flat = ~b_flat;      // corrupt the inputs
            start = 1; @(negedge clk); start = 0;     // illegal extra start
            wait_done;
            check_results("start-while-busy", 0);
            repeat (100) @(posedge clk);              // make sure no re-run happens
            if (done_cnt_s != base_s + 1 || done_cnt_p != base_p + 1) begin
                $display("FAIL: wrong number of done pulses after ignored start (seq %0d, pipe %0d)",
                         done_cnt_s - base_s, done_cnt_p - base_p);
                errors = errors + 1;
            end
            $display("%0s [start while busy, +%0d cycles]", (errors == e0) ? "PASS" : "FAIL", offset);
        end
    endtask

    // ------------------------------------------------------------
    // Extra test 2: reset in the middle of an operation.
    // Engines must go idle, clear outputs, not raise done, and then
    // work normally on the next operation.
    // ------------------------------------------------------------
    task test_reset_midrun(input integer offset);
        integer e0, ds0, dp0;
        begin
            tests = tests + 1; e0 = errors;
            ds0 = done_cnt_s; dp0 = done_cnt_p;
            randomize_inputs;
            pulse_start;
            repeat (offset) @(negedge clk);
            rst_n = 0;
            repeat (2) @(negedge clk);
            if (busy_s || busy_p || done_s || done_p) begin
                $display("FAIL: busy/done not cleared by reset"); errors = errors + 1;
            end
            if (c_seq !== 0 || c_pipe !== 0) begin
                $display("FAIL: result registers not cleared by reset"); errors = errors + 1;
            end
            rst_n = 1;
            repeat (100) @(posedge clk);              // an aborted op must not finish
            if (done_cnt_s != ds0 || done_cnt_p != dp0) begin
                $display("FAIL: done raised for an aborted operation"); errors = errors + 1;
            end
            if (c_seq !== 0 || c_pipe !== 0) begin
                $display("FAIL: aborted operation wrote results after reset"); errors = errors + 1;
            end
            $display("%0s [reset mid-run, +%0d cycles]", (errors == e0) ? "PASS" : "FAIL", offset);
            randomize_inputs;
            run_test("recovery after reset", 0);
        end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    integer i, j, r;
    initial begin
        $dumpfile("matmul.vcd");
        $dumpvars(0, tb_matmul);
        show_all = $test$plusargs("SHOW_ALL");
        a_flat = 0; b_flat = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- Test 1: predefined matrices with hard-coded golden ----
        // A = 1..16 row-major, B = 16..1 row-major
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                set_a(i, j, i*N + j + 1);
                set_b(i, j, 16 - (i*N + j));
            end
        // golden = A x B computed independently (numpy)
        golden[0]  = 80;  golden[1]  = 70;  golden[2]  = 60;  golden[3]  = 50;
        golden[4]  = 240; golden[5]  = 214; golden[6]  = 188; golden[7]  = 162;
        golden[8]  = 400; golden[9]  = 358; golden[10] = 316; golden[11] = 274;
        golden[12] = 560; golden[13] = 502; golden[14] = 444; golden[15] = 386;
        run_test("1: A=1..16, B=16..1", (N == 4));  // golden is 4x4-only

        // ---- Test 2: A x Identity = A ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1)
                set_b(i, j, (i == j) ? 1 : 0);
        run_test("2: A x I", 0);

        // ---- Test 3: worst case, all 255 (checks accumulator width) ----
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                set_a(i, j, 255);
                set_b(i, j, 255);
            end
        run_test("3: all 255", 0);

        // ---- Test 4: zeros ----
        a_flat = 0; b_flat = 0;
        run_test("4: zeros", 0);

        // ---- Random matrices ----
        for (r = 0; r < 10; r = r + 1) begin
            randomize_inputs;
            run_test("random", 0);
        end

        // ---- Start pulse while busy (mid-issue, late, and on the last cycle) ----
        test_start_while_busy(3);
        test_start_while_busy(8);
        test_start_while_busy(N*N - 1);     // pipe: draining
        test_start_while_busy(N*N);         // pipe: on the cycle done is raised

        // ---- Reset in the middle of an operation ----
        test_reset_midrun(4);
        test_reset_midrun(N*N - 6);         // mid-run
        test_reset_midrun(N*N);             // pipe: reset one cycle before done

        $display("--------------------------------------------");
        if (errors == 0) $display("ALL %0d TESTS PASSED", tests);
        else             $display("%0d ERRORS in %0d tests", errors, tests);
`ifdef MODELSIM
        $stop;      // keeps ModelSim open (waves, coverage) instead of closing the sim
`else
        $finish;
`endif
    end
endmodule
