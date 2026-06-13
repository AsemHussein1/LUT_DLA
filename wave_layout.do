onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/clk_fast
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/rst_n
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/div_ratio
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/top2sys_valid
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/sys2top_ready
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/sys_done
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/tb_busy
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/k_total
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/n_total
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/spad_out_addr
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/pass_count
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/fail_count
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/assert_fail_count
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/run_total
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/last_cycle_count
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/reset_count
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/lut_pattern_tag
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/sys_done_q
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/hw_cycle_cnt
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/hw_last_cycles
add wave -noupdate -group {TB Stimulus} /SYSTEM_TOP_TB/hw_run_total
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/clk_fast
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/clk_slow
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/rst_n
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/sys_busy
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/ccm_start_pulse
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/ccm_done_pulse
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/imm_start_slow
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/imm_done_slow
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/imm_done_fast
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/imm2top_ready
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/sys2top_ready
add wave -noupdate -group {System Top} /SYSTEM_TOP_TB/dut/sys_done
add wave -noupdate -group ClkDiv /SYSTEM_TOP_TB/dut/u_clk_div/i_ref_clk
add wave -noupdate -group ClkDiv /SYSTEM_TOP_TB/dut/u_clk_div/i_rst
add wave -noupdate -group ClkDiv /SYSTEM_TOP_TB/dut/u_clk_div/i_clk_en
add wave -noupdate -group ClkDiv /SYSTEM_TOP_TB/dut/u_clk_div/i_div_ratio
add wave -noupdate -group ClkDiv /SYSTEM_TOP_TB/dut/u_clk_div/o_div_clk
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/src_clk
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/src_resetn
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/src_pulse_i
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/dst_clk
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/dst_resetn
add wave -noupdate -group {CDC Start (fast->slow)} /SYSTEM_TOP_TB/dut/u_cdc_start/dst_pulse_o
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/src_clk
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/src_resetn
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/src_pulse_i
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/dst_clk
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/dst_resetn
add wave -noupdate -group {CDC Done (slow->fast)} /SYSTEM_TOP_TB/dut/u_cdc_done/dst_pulse_o
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/clk
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/rst_n
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccm_start_pulse
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccm_done_pulse
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/current_state
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/next_state
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2cb_start_addr
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2cb_valid
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb2ctrl_ready
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2ib_start_addr
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ctrl2ib_valid
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib2ctrl_ready
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ccu_done
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/total_count
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb_addr_count
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib_addr_count
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/ib_n_loop_count
add wave -noupdate -group {CCM Controller} /SYSTEM_TOP_TB/dut/u_ccm_ctrl/cb_n_loop_count
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/clk
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/rst_n
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ctrl2cb_start_addr
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ctrl2cb_addr_valid
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/cb2ctrl_addr_ready
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ctrl2ib_start_addr
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ctrl2ib_valid
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ib2ctrl_ready
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ccu2fifo_idx
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ccu2fifo_valid
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/fifo2ccu_ready
add wave -noupdate -group {CCM Block} /SYSTEM_TOP_TB/dut/u_ccm/ccu_done
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/csram_we_a
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/csram_waddr_a
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/csram_wdata_a
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/dut/csram_re_b
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/dut/csram_raddr_b
add wave -noupdate -group CSRAM /SYSTEM_TOP_TB/dut/csram_rdata_b
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/isram_we_a
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/isram_waddr_a
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/isram_wdata_a
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/dut/isram_re_b
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/dut/isram_raddr_b
add wave -noupdate -group ISRAM /SYSTEM_TOP_TB/dut/isram_rdata_b
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/W_clk
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/W_rst_n
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/W_valid
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/W_ready
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/WR_DATA
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/R_clk
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/R_rst_n
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/R_ready
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/R_valid
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/RD_DATA
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/FULL
add wave -noupdate -group {Async FIFO} /SYSTEM_TOP_TB/dut/u_fifo/EMPTY
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/lsram_we_a
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/lsram_waddr_a
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/lsram_wdata_a
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/dut/lsram_re_b
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/dut/lsram_raddr_b
add wave -noupdate -group LSRAM /SYSTEM_TOP_TB/dut/lsram_rdata_b
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/clk
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/rst_n
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/cs
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/ns
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/top2imm_valid
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/imm2top_ready
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/imm_done
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/k_total
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/n_total
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/subspace_count
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/n_count
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2psum_start_addr
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2psum_addr_valid
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/psum2ctrl_addr_ready
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2spad_start_addr
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/ctrl2spad_addr_valid
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/spad2ctrl_addr_ready
add wave -noupdate -group IMM_CTRL /SYSTEM_TOP_TB/dut/u_imm_ctrl/spad2ctrl_done
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/clk
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/rst_n
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/ctrl2psum_start_addr
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/ctrl2psum_addr_valid
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2ctrl_addr_ready
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2mem_re
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2mem_addr
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/mem2psum_lut_value
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/fifo2psum_valid
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/fifo2psum_index
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2fifo_ready
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2spad_valid
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/psum2spad_value
add wave -noupdate -group PSumLUT /SYSTEM_TOP_TB/dut/u_imm/PSum_LUT_inst/spad2psum_ready
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/clk
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/rst_n
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/state
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/m_count
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/k_sub_count
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/n_col_count
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/acc_col_base
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/acc_current_addr
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/psum2spad_valid
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/psum2spad_value
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2psum_ready
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/ctrl2spad_start_addr
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/ctrl2spad_addr_valid
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2ctrl_addr_ready
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_count
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_row
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/stream_col
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_we
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_addr
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2out_data
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/spad2ctrl_done
add wave -noupdate -group Scratchpad /SYSTEM_TOP_TB/dut/u_imm/Scratchpad_inst/base_addr
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/dut/osram_we_a
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/dut/osram_waddr_full
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/dut/osram_wdata_a
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/osram_re_b
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/osram_raddr_b
add wave -noupdate -group OSRAM /SYSTEM_TOP_TB/osram_rdata_b
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 5
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {28856884092 ps} {28856885048 ps}
