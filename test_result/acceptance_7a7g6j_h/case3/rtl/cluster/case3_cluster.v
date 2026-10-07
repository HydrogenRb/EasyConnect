//==========================================================================
//  case3_cluster.v
//  计算簇：命令译码 + `C3_SLICE_NUM 个 slice（for-generate）+ slice 级
//  互连（slice_xbar）+ 共享寄存器堆。
//
//  Ref: 多核加速器的 cluster（Mali 的 shader core、NPU 的 cluster）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_cluster (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          CLUSTER_CLK,
    input  wire [`C3_CFG_DATA_W-1:0]     CL_CTRL,
    input  wire [`C3_CFG_DATA_W-1:0]     CL_MASK,
    input  wire [`C3_ADDR_W-1:0]         CL_BASE,
    input  wire                          CL_GO,
    input  wire [`C3_CLUSTER_AW-1:0]     CLUSTER_ID,
    input  wire [`C3_MON_SEL_W-1:0]      MON_SEL,
    input  wire [`C3_DESC_W-1:0]         DESC_DATA,
    input  wire                          DESC_VALID,
    output wire                          DESC_READY,
    input  wire [`C3_TXN_ID_W-1:0]       TXN_ID,
    input  wire [`C3_XFER_ID_W-1:0]      XFER_ID,
    output wire [`C3_STATUS_W-1:0]       CL_STATUS,
    output wire [`C3_CNT_W-1:0]          CL_CYCLES,
    output wire                          CL_BUSY,
    output wire                          SP_A_CEN,
    output wire                          SP_A_WEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_A_ADDR,
    output wire [`C3_SCRATCH_DATA_W-1:0] SP_A_D,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_A_Q,
    output wire                          SP_B_CEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_B_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_B_Q
);

    parameter CLUSTER_INDEX = 0;
    parameter CLUSTER_PIPE  = `C3_PIPE_NUM;

    genvar s;

    wire [`C3_OP_W-1:0]     dec_op_w;
    wire [`C3_LANE_NUM-1:0] dec_lane_mask_w;
    wire [`C3_SLICE_NUM-1:0] dec_slice_mask_w;
    wire [`C3_PE_W-1:0]     dec_imm_w;
    wire                    dec_valid_w;
    wire                    dec_err_w;
    wire                    cmd_clk_w;
    wire                    xbar_busy_w;
    wire                    rf_ready_w;
    wire                    rf_err_w;
    wire [`C3_BANK_AW-1:0]  rf_bank_sel_w;

    wire [`C3_STATUS_W-1:0]       sl_status_w  [0:`C3_SLICE_NUM-1];
    wire [`C3_CNT_W-1:0]          sl_cycles_w  [0:`C3_SLICE_NUM-1];
    wire                          sl_busy_w    [0:`C3_SLICE_NUM-1];
    wire                          sl_desc_rdy_w[0:`C3_SLICE_NUM-1];
    wire                          sl_a_cen_w   [0:`C3_SLICE_NUM-1];
    wire                          sl_a_wen_w   [0:`C3_SLICE_NUM-1];
    wire [`C3_SCRATCH_ADDR_W-1:0] sl_a_addr_w  [0:`C3_SLICE_NUM-1];
    wire [`C3_SCRATCH_DATA_W-1:0] sl_a_d_w     [0:`C3_SLICE_NUM-1];
    wire                          sl_b_cen_w   [0:`C3_SLICE_NUM-1];
    wire [`C3_SCRATCH_ADDR_W-1:0] sl_b_addr_w  [0:`C3_SLICE_NUM-1];

    assign SP_A_CEN   = sl_a_cen_w[0] | sl_a_cen_w[1];
    assign SP_A_WEN   = sl_a_wen_w[0] | sl_a_wen_w[1];
    assign SP_A_ADDR  = sl_a_addr_w[0] | sl_a_addr_w[1];
    assign SP_A_D     = sl_a_d_w[0] | sl_a_d_w[1];
    assign SP_B_CEN   = sl_b_cen_w[0] | sl_b_cen_w[1];
    assign SP_B_ADDR  = sl_b_addr_w[0] | sl_b_addr_w[1];
    assign CL_STATUS  = sl_status_w[0] | sl_status_w[1] | {`C3_STATUS_W{rf_err_w}};
    assign CL_CYCLES  = sl_cycles_w[0] + sl_cycles_w[1];
    assign CL_BUSY    = sl_busy_w[0] | sl_busy_w[1] | xbar_busy_w | (~rf_ready_w);
    assign DESC_READY = sl_desc_rdy_w[0] & sl_desc_rdy_w[1];

    case3_cmd_decoder u_cmd (
        .CLK           (CLK),
        .RST_N         (RST_N),
        .CFG_CTRL      (CL_CTRL),
        .CL_GO         (CL_GO),
        .CFG_MASK      (CL_MASK),
        .DEC_OP        (dec_op_w),
        .DEC_LANE_MASK (dec_lane_mask_w),
        .DEC_SLICE_MASK(dec_slice_mask_w),
        .DEC_IMM       (dec_imm_w),
        .DEC_VALID     (dec_valid_w),
        .DEC_ERR       (dec_err_w),
        .CMD_CLK       (cmd_clk_w)
    );

    generate
        for (s = 0; s < `C3_SLICE_NUM; s = s + 1) begin : g_slice
            wire [`C3_SLICE_AW-1:0] slice_id_w;
            wire [`C3_ADDR_W-1:0]   slice_stride_w;
            wire [`C3_LANE_NUM-1:0] slice_mask_w;

            assign slice_id_w     = s;
            assign slice_stride_w = {{(`C3_ADDR_W-`C3_SLICE_AW){1'b0}}, s};
            assign slice_mask_w   = dec_lane_mask_w & {`C3_LANE_NUM{dec_slice_mask_w[s]}};

            case3_slice u_slice[s] (
                .CLK          (cmd_clk_w),
                .RST_N        (RST_N),
                .SLICE_CLK    (CLUSTER_CLK),
                .SL_CTRL      (CL_CTRL),
                .SL_BASE      (CL_BASE + slice_stride_w),
                .SL_OP        (dec_op_w),
                .SL_LANE_MASK (slice_mask_w),
                .SLICE_ID     (slice_id_w),
                .DESC_DATA    (DESC_DATA),
                .DESC_VALID   (DESC_VALID & dec_valid_w),
                .DESC_READY   (sl_desc_rdy_w[s]),
                .TXN_ID       (TXN_ID),
                .XFER_ID      (XFER_ID),
                .MON_SEL      (MON_SEL),
                .SL_STATUS    (sl_status_w[s]),
                .SL_CYCLES    (sl_cycles_w[s]),
                .SL_BUSY      (sl_busy_w[s]),
                .SP_A_CEN     (sl_a_cen_w[s]),
                .SP_A_WEN     (sl_a_wen_w[s]),
                .SP_A_ADDR    (sl_a_addr_w[s]),
                .SP_A_D       (sl_a_d_w[s]),
                .SP_A_Q       (SP_A_Q),
                .SP_B_CEN     (sl_b_cen_w[s]),
                .SP_B_ADDR    (sl_b_addr_w[s]),
                .SP_B_Q       (SP_B_Q)
            );
        end
    endgenerate

    case3_slice_xbar u_slice_xbar (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .XBAR_CLK     (cmd_clk_w),
        .LANE_REQ     ({`C3_LANE_NUM{dec_valid_w}}),
        .LANE_SEL     (dec_lane_mask_w[`C3_LANE_AW-1:0]),
        .LANE_DATA    (DESC_DATA[`C3_DATA_MSB:0]),
        .XBAR_DATA    (),
        .LANE_GRANT   (),
        .SLICE_XBAR_BUSY(xbar_busy_w)
    );

    case3_rf_bank u_shared_rf (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .RF_ADDR     (DESC_DATA[`C3_REG_ADDR_MSB:0]),
        .RF_WDATA    (SP_A_Q),
        .RF_RDATA    (),
        .RF_WE       (dec_valid_w & (dec_op_w == `C3_OP_WR)),
        .RF_RE       (dec_valid_w & (dec_op_w == `C3_OP_RD)),
        .RF_READY    (rf_ready_w),
        .RF_BUSY     (),
        .RF_BANK_SEL (rf_bank_sel_w),
        .RF_ERR      (rf_err_w)
    );

endmodule
