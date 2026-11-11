# ============================================================
# run_cov.do  -  same flow with code coverage
# Needs a ModelSim edition that licenses coverage (SE/DE/Questa;
# not Starter / Intel FPGA Starter).  Otherwise use run.do.
#   do run_cov.do
# ============================================================
transcript on
catch {quit -sim}
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv +define+MODELSIM +cover=bcesf matmul_seq.v matmul_pipe.v tb_matmul.v
if {[catch {vsim -coverage -voptargs=+acc work.tb_matmul} err]} {
    puts "Code coverage is not licensed in this ModelSim edition -> use run.do instead."
    return
}

run -all

coverage save cov.ucdb
coverage report -details -output cov_report.txt
puts "Coverage report written to cov_report.txt (database: cov.ucdb)"
