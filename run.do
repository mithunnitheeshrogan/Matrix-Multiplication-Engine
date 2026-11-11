# ============================================================
# run.do  -  one-command ModelSim flow
# GUI   :  do run.do
# Batch :  vsim -c -do run.do
# Print every test's matrices:  vsim -voptargs=+acc work.tb_matmul +SHOW_ALL
# ============================================================
transcript on
catch {quit -sim}          ;# unload a previous simulation so work/ can be deleted
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# design first, testbench last.  -sv for $urandom_range; MODELSIM makes the tb use $stop
vlog -sv +define+MODELSIM matmul_seq.v matmul_pipe.v tb_matmul.v

vsim -voptargs=+acc work.tb_matmul

if {[batch_mode]} {
    run -all
    quit -f
} else {
    add wave -divider {Control}
    add wave -radix binary   /tb_matmul/clk /tb_matmul/rst_n /tb_matmul/start

    add wave -divider {Matrices (index n = row*N + col)}
    add wave -radix unsigned /tb_matmul/A_view
    add wave -radix unsigned /tb_matmul/B_view
    add wave -radix unsigned /tb_matmul/C_seq_view
    add wave -radix unsigned /tb_matmul/C_pipe_view

    add wave -divider {Sequential engine}
    add wave -radix binary   /tb_matmul/u_seq/busy /tb_matmul/u_seq/done
    add wave -radix unsigned /tb_matmul/u_seq/state /tb_matmul/u_seq/i /tb_matmul/u_seq/j /tb_matmul/u_seq/k
    add wave -radix unsigned /tb_matmul/u_seq/acc
    add wave -radix unsigned /tb_matmul/c_seq

    add wave -divider {Pipelined engine}
    add wave -radix binary   /tb_matmul/u_pipe/busy /tb_matmul/u_pipe/done /tb_matmul/u_pipe/running /tb_matmul/u_pipe/v1
    add wave -radix unsigned /tb_matmul/u_pipe/i /tb_matmul/u_pipe/j /tb_matmul/u_pipe/idx1
    add wave -radix unsigned /tb_matmul/u_pipe/sum_c
    add wave -radix unsigned /tb_matmul/c_pipe

    run -all
    wave zoom full
}
