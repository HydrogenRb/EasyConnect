//==========================================================================
//  case3 filelist -- SIMD compute cluster engine
//  路径相对 test_cases/case3/ 目录；共享库单元来自 case1（只读复用）。
//==========================================================================
rtl/common/defines/case3_define.v

// ---- 共享库单元（case1 提供，本 case 不修改） ----
../case1/rtl/common/lib/lib_define.v
../case1/rtl/common/lib/lib_ram_cells.v

// ---- common 工具单元 ----
rtl/common/case3_sync_2ff.v
rtl/common/case3_clk_gate.v
rtl/common/case3_perf_counter.v
rtl/common/case3_cnt_wrap.v
rtl/common/case3_sync_fifo.v

// ---- top ----
rtl/top/case3_engine_top.v

// ---- cluster / slice ----
rtl/cluster/case3_cluster_array.v
rtl/cluster/case3_cluster.v
rtl/cluster/case3_slice.v
rtl/cluster/case3_cmd_decoder.v
rtl/cluster/case3_rf_bank.v
rtl/cluster/case3_slice_monitor.v

// ---- lane ----
rtl/lane/case3_lane.v
rtl/lane/case3_lane_mul.v
rtl/lane/case3_lane_alu.v
rtl/lane/case3_lane_shf.v
rtl/lane/case3_lane_cmp.v
rtl/lane/case3_lane_sat.v
rtl/lane/case3_lane_regfile.v
rtl/lane/case3_lane_agu.v
rtl/lane/case3_lane_aligner.v
rtl/lane/case3_lane_local_rf.v

// ---- mem ----
rtl/mem/case3_scratchpad.v
rtl/mem/case3_scratch_bank.v
rtl/mem/case3_scratch_arb.v

// ---- xbar ----
rtl/xbar/case3_xbar.v
rtl/xbar/case3_slice_xbar.v
rtl/xbar/case3_xbar_cell.v
rtl/xbar/case3_xbar_arb.v

// ---- dma ----
rtl/dma/case3_dma_engine.v
rtl/dma/case3_dma_desc_fetch.v

// ---- cfg ----
rtl/cfg/case3_config_regs.v
rtl/cfg/case3_reg_bank.v
