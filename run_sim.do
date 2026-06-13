# ==============================================================
#  run_sim.do  —  Full simulation + coverage script
#  Usage (ModelSim/QuestaSim GUI):  do run_sim.do
#  Usage (batch):  vsim -c -do run_sim.do
# ==============================================================

# ── 1. Clean and create work library ─────────────────────────
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# ── 2. Compile RTL with code coverage (bcest) ────────────────
#   b=branch  c=condition  e=expression  s=statement  t=toggle

vlog -sv -cover bcest -work work  CLK_Div/ClkDiv.v
vlog -sv -cover bcest -work work  "MEM/True_Dual_Port_BRAM.v"
vlog -sv -cover bcest -work work  CDC/CDC_sync.v

# CCM sub-modules (must precede CCM.v)
vlog -sv -cover bcest -work work  CCM/centroid_buffer.v
vlog -sv -cover bcest -work work  CCM/input_buffer.v
vlog -sv -cover bcest -work work  CCM/CCU.v
vlog -sv -cover bcest -work work  CCM/CCM.v

# FIFO sub-modules (must precede FIFO_TOP.sv)
vlog -sv -cover bcest -work work  FIFO/FIFO_MEM_CNTRL.sv
vlog -sv -cover bcest -work work  FIFO/FIFO_WR.sv
vlog -sv -cover bcest -work work  FIFO/FIFO_RD.sv
vlog -sv -cover bcest -work work  FIFO/SYNC_W2R.sv
vlog -sv -cover bcest -work work  FIFO/SYNC_R2W.sv
vlog -sv -cover bcest -work work  FIFO/FIFO_TOP.sv

vlog -sv -cover bcest -work work  CTRL/CCM_CTRL.v
vlog -sv -cover bcest -work work  CTRL/IMM_CTRL.v
vlog -sv -cover bcest -work work  IMM/PSumLUT.v
vlog -sv -cover bcest -work work  IMM/scratchpad.v
vlog -sv -cover bcest -work work  IMM/IMM.v
vlog -sv -cover bcest -work work  SYSTEM_TOP.v

# Testbench: functional coverage only (no code coverage on TB)
vlog -sv -work work  SYSTEM_TOP_TB.sv

# ── 3. Elaborate and simulate ─────────────────────────────────
vsim -t 1ps                 \
     -coverage              \
     -sv_seed random        \
     -voptargs=+acc         \
     work.SYSTEM_TOP_TB

# ── 4. Setup VCD dump ─────────────────────────────────────────
vcd file sim_dump.vcd
vcd add -r /SYSTEM_TOP_TB/*
vcd add -r /SYSTEM_TOP_TB/dut/*

# ── 5. Wave Groups ─────────────────────────────────────────────
#       Each subsystem gets its own collapsible group.

# ───── GROUP: TB Stimulus & Score ─────────────────────────────
add wave -group {TB Stimulus} \
    /SYSTEM_TOP_TB/clk_fast \
    /SYSTEM_TOP_TB/rst_n \
    /SYSTEM_TOP_TB/div_ratio \
    /SYSTEM_TOP_TB/top2sys_valid \
    /SYSTEM_TOP_TB/sys2top_ready \
    /SYSTEM_TOP_TB/sys_done \
    /SYSTEM_TOP_TB/tb_busy \
    /SYSTEM_TOP_TB/k_total \
    /SYSTEM_TOP_TB/n_total \
    /SYSTEM_TOP_TB/spad_out_addr \
    /SYSTEM_TOP_TB/pass_count \
    /SYSTEM_TOP_TB/fail_count \
    /SYSTEM_TOP_TB/assert_fail_count \
    /SYSTEM_TOP_TB/run_total \
    /SYSTEM_TOP_TB/last_cycle_count \
    /SYSTEM_TOP_TB/reset_count \
    /SYSTEM_TOP_TB/lut_pattern_tag \
    /SYSTEM_TOP_TB/sys_done_q \
    /SYSTEM_TOP_TB/hw_cycle_cnt \
    /SYSTEM_TOP_TB/hw_last_cycles \
    /SYSTEM_TOP_TB/hw_run_total

# ───── GROUP: System Top Control ──────────────────────────────
add wave -group {System Top} \
    /SYSTEM_TOP_TB/dut/clk_fast \
    /SYSTEM_TOP_TB/dut/clk_slow \
    /SYSTEM_TOP_TB/dut/rst_n \
    /SYSTEM_TOP_TB/dut/sys_busy \
    /SYSTEM_TOP_TB/dut/ccm_start_pulse \
    /SYSTEM_TOP_TB/dut/ccm_done_pulse \
    /SYSTEM_TOP_TB/dut/imm_start_slow \
    /SYSTEM_TOP_TB/dut/imm_done_slow \
    /SYSTEM_TOP_TB/dut/imm_done_fast \
    /SYSTEM_TOP_TB/dut/imm2top_ready \
    /SYSTEM_TOP_TB/dut/sys2top_ready \
    /SYSTEM_TOP_TB/dut/sys_done

# ───── GROUP: Clock Divider ────────────────────────────────────
add wave -group {ClkDiv} \
    /SYSTEM_TOP_TB/dut/u_clk_div/i_ref_clk \
    /SYSTEM_TOP_TB/dut/u_clk_div/i_rst \
    /SYSTEM_TOP_TB/dut/u_clk_div/i_clk_en \
    /SYSTEM_TOP_TB/dut/u_clk_div/i_div_ratio \
    /SYSTEM_TOP_TB/dut/u_clk_div/o_div_clk

# ───── GROUP: CDC — Fast→Slow (Start) ─────────────────────────
add wave -group {CDC Start (fast->slow)} \
    /SYSTEM_TOP_TB/dut/u_cdc_start/src_clk \
    /SYSTEM_TOP_TB/dut/u_cdc_start/src_resetn \
    /SYSTEM_TOP_TB/dut/u_cdc_start/src_pulse_i \
    /SYSTEM_TOP_TB/dut/u_cdc_start/dst_clk \
    /SYSTEM_TOP_TB/dut/u_cdc_start/dst_resetn \
    /SYSTEM_TOP_TB/dut/u_cdc_start/dst_pulse_o

# ───── GROUP: CDC — Slow→Fast (Done) ──────────────────────────
add wave -group {CDC Done (slow->fast)} \
    /SYSTEM_TOP_TB/dut/u_cdc_done/src_clk \
    /SYSTEM_TOP_TB/dut/u_cdc_done/src_resetn \
    /SYSTEM_TOP_TB/dut/u_cdc_done/src_pulse_i \
    /SYSTEM_TOP_TB/dut/u_cdc_done/dst_clk \
    /SYSTEM_TOP_TB/dut/u_cdc_done/dst_resetn \
    /SYSTEM_TOP_TB/dut/u_cdc_done/dst_pulse_o

# ───── GROUP: CCM Controller ───────────────────────────────────
add wave -group {CCM Controller} \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/clk \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/rst_n \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccm_start_pulse \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccm_done_pulse \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/current_state \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/next_state \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2cb_start_addr \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2cb_valid \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb2ctrl_ready \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2ib_start_addr \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2ib_valid \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib2ctrl_ready \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccu_done \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/total_count \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb_addr_count \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib_addr_count \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib_n_loop_count \
    /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb_n_loop_count

# ───── GROUP: CCM Block (CCU + Buffers) ───────────────────────
add wave -group {CCM Block} \
    /SYSTEM_TOP_TB/dut/u_ccm/clk \
    /SYSTEM_TOP_TB/dut/u_ccm/rst_n \
    /SYSTEM_TOP_TB/dut/u_ccm/ctrl2cb_start_addr \
    /SYSTEM_TOP_TB/dut/u_ccm/ctrl2cb_addr_valid \
    /SYSTEM_TOP_TB/dut/u_ccm/cb2ctrl_addr_ready \
    /SYSTEM_TOP_TB/dut/u_ccm/ctrl2ib_start_addr \
    /SYSTEM_TOP_TB/dut/u_ccm/ctrl2ib_valid \
    /SYSTEM_TOP_TB/dut/u_ccm/ib2ctrl_ready \
    /SYSTEM_TOP_TB/dut/u_ccm/ccu2fifo_idx \
    /SYSTEM_TOP_TB/dut/u_ccm/ccu2fifo_valid \
    /SYSTEM_TOP_TB/dut/u_ccm/fifo2ccu_ready \
    /SYSTEM_TOP_TB/dut/u_ccm/ccu_done

# ───── GROUP: CSRAM (Centroid SRAM) ───────────────────────────
add wave -group {CSRAM} \
    /SYSTEM_TOP_TB/csram_we_a \
    /SYSTEM_TOP_TB/csram_waddr_a \
    /SYSTEM_TOP_TB/csram_wdata_a \
    /SYSTEM_TOP_TB/dut/csram_re_b \
    /SYSTEM_TOP_TB/dut/csram_raddr_b \
    /SYSTEM_TOP_TB/dut/csram_rdata_b

# ───── GROUP: ISRAM (Input SRAM) ──────────────────────────────
add wave -group {ISRAM} \
    /SYSTEM_TOP_TB/isram_we_a \
    /SYSTEM_TOP_TB/isram_waddr_a \
    /SYSTEM_TOP_TB/isram_wdata_a \
    /SYSTEM_TOP_TB/dut/isram_re_b \
    /SYSTEM_TOP_TB/dut/isram_raddr_b \
    /SYSTEM_TOP_TB/dut/isram_rdata_b

# ───── GROUP: Async FIFO (CCM→PSumLUT) ───────────────────────
add wave -group {Async FIFO} \
    /SYSTEM_TOP_TB/dut/u_fifo/W_clk \
    /SYSTEM_TOP_TB/dut/u_fifo/W_rst_n \
    /SYSTEM_TOP_TB/dut/u_fifo/W_valid \
    /SYSTEM_TOP_TB/dut/u_fifo/W_ready \
    /SYSTEM_TOP_TB/dut/u_fifo/WR_DATA \
    /SYSTEM_TOP_TB/dut/u_fifo/R_clk \
    /SYSTEM_TOP_TB/dut/u_fifo/R_rst_n \
    /SYSTEM_TOP_TB/dut/u_fifo/R_ready \
    /SYSTEM_TOP_TB/dut/u_fifo/R_valid \
    /SYSTEM_TOP_TB/dut/u_fifo/RD_DATA \
    /SYSTEM_TOP_TB/dut/u_fifo/FULL \
    /SYSTEM_TOP_TB/dut/u_fifo/EMPTY

# ───── GROUP: LSRAM (PSum LUT SRAM) ──────────────────────────
add wave -group {LSRAM} \
    /SYSTEM_TOP_TB/lsram_we_a \
    /SYSTEM_TOP_TB/lsram_waddr_a \
    /SYSTEM_TOP_TB/lsram_wdata_a \
    /SYSTEM_TOP_TB/dut/lsram_re_b \
    /SYSTEM_TOP_TB/dut/lsram_raddr_b \
    /SYSTEM_TOP_TB/dut/lsram_rdata_b

# ───── GROUP: IMM_CTRL FSM ────────────────────────────────────
add wave -group {IMM_CTRL} \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/clk \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/rst_n \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/cs \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/ns \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/top2imm_valid \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/imm2top_ready \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/imm_done \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/k_total \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/n_total \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/subspace_count \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/n_count \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2psum_start_addr \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2psum_addr_valid \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/psum2ctrl_addr_ready \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2spad_start_addr \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2spad_addr_valid \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/spad2ctrl_addr_ready \
    /SYSTEM_TOP_TB/dut/u_imm_ctrl/spad2ctrl_done

# ───── GROUP: PSumLUT ─────────────────────────────────────────
add wave -group {PSumLUT} \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/clk \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/rst_n \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/ctrl2psum_start_addr \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/ctrl2psum_addr_valid \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2ctrl_addr_ready \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2mem_re \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2mem_addr \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/mem2psum_lut_value \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/fifo2psum_valid \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/fifo2psum_index \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2fifo_ready \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2spad_valid \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2spad_value \
    /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/spad2psum_ready

# ───── GROUP: Scratchpad ──────────────────────────────────────
add wave -group {Scratchpad} \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/clk \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/rst_n \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/state \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/m_count \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/k_sub_count \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/n_col_count \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/acc_col_base \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/acc_current_addr \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/psum2spad_valid \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/psum2spad_value \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2psum_ready \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/ctrl2spad_start_addr \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/ctrl2spad_addr_valid \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2ctrl_addr_ready \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_count \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_row \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_col \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_we \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_addr \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_data \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2ctrl_done \
    /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/base_addr

# ───── GROUP: OSRAM (Output SRAM) ────────────────────────────
add wave -group {OSRAM} \
    /SYSTEM_TOP_TB/dut/osram_we_a \
    /SYSTEM_TOP_TB/dut/osram_waddr_full \
    /SYSTEM_TOP_TB/dut/osram_wdata_a \
    /SYSTEM_TOP_TB/osram_re_b \
    /SYSTEM_TOP_TB/osram_raddr_b \
    /SYSTEM_TOP_TB/osram_rdata_b

# ── 6. Configure waveform display ────────────────────────────
configure wave -namecolwidth  250
configure wave -valuecolwidth 100
configure wave -justifyvalue  left
configure wave -signalnamewidth 1
configure wave -snapdistance  5
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0

# ── 7. Run simulation ─────────────────────────────────────────
run -all

# ── 8. Save waveform layout ───────────────────────────────────
write format wave -window .main_pane.wave.interior.cs.body.pw.wf wave_layout.do

# ── 9. Save VCD (already opened above, close it) ─────────────
vcd flush

# ── 10. Save functional + code coverage database ─────────────
coverage save sim_coverage.ucdb

# ── 11. Transcript: short totals (no -detail = one line per scope) ──
coverage report -assert
coverage report -cvg
coverage report -code bcest

# ── 12. Detail to files only (-file routes output to file, not transcript) ──
coverage report -assert     -detail -verbose              -file rpt_assert.txt
coverage report -cvg        -detail -verbose -zeros       -file rpt_func.txt
coverage report -code bcest -detail -verbose              -file rpt_code.txt

# ── 14. HTML report (full detail, no transcript noise) ────────
vcover report sim_coverage.ucdb -html -output coverage_html \
    -details -all -verbose -threshL 50 -threshH 90

# ── 15. Single combined text report ───────────────────────────
vcover report sim_coverage.ucdb -details -all > coverage_full.txt

echo ""
echo "=========================================="
echo " run_sim.do COMPLETE"
echo "  Waveform    : wave_layout.do"
echo "  VCD dump    : sim_dump.vcd"
echo "  Coverage DB : sim_coverage.ucdb"
echo "  -- Detail reports (open these) --"
echo "  Assertions  : rpt_assert.txt"
echo "  Functional  : rpt_func.txt"
echo "  Code        : rpt_code.txt"
echo "  Full text   : coverage_full.txt"
echo "  HTML        : coverage_html/index.html"
echo "=========================================="
