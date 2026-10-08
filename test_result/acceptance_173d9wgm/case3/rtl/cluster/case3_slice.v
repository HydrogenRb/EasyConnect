//==========================================================================
//  case3_slice.v
//  slice：4 条 lane 的 SIMD 分组 + slice 本地寄存器堆 + 性能监测。
//  内部用 for-generate 展开 `C3_LANE_NUM 条 lane。
//
//  Ref: NPU/DSP 里的 sub-partition（NVDLA 的 sub-partition、Vision P6 的 slice）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_slice (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          SLICE_CLK,
    input  wire [`C3_CFG_DATA_W-1:0]     SL_CTRL,
    input  wire [`C3_ADDR_W-1:0]         SL_BASE,
    input  wire [`C3_OP_W-1:0]           SL_OP,
    input  wire [`C3_LANE_NUM-1:0]       SL_LANE_MASK,
    input  wire [`C3_SLICE_AW-1:0]       SLICE_ID,
    input  wire [`C3_DESC_W-1:0]         DESC_DATA,
    input  wire                          DESC_VALID,
    output wire                          DESC_READY,
    input  wire [`C3_TXN_ID_W-1:0]       TXN_ID,
    input  wire [`C3_XFER_ID_W-1:0]      XFER_ID,
    input  wire [`C3_MON_SEL_W-1:0]      MON_SEL,
    output wire [`C3_STATUS_W-1:0]       SL_STATUS,
    output wire [`C3_CNT_W-1:0]          SL_CYCLES,
    output wire                          SL_BUSY,
    output wire                          SP_A_CEN,
    output wire                          SP_A_WEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_A_ADDR,
    output wire [`C3_SCRATCH_DATA_W-1:0] SP_A_D,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_A_Q,
    output wire                          SP_B_CEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_B_ADDR,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_B_Q
);

    parameter SLICE_INDEX = 0;
    parameter SLICE_PIPE  = `C3_PIPE_STAGE;

    genvar l;

    reg  sl_go_r;
    reg  [(`C3_LANE_NUM)-1:0] lane_evt_r;
    wire [`C3_DATA_W-1:0]      lane_result_w [0:`C3_LANE_NUM-1];
    wire [`C3_ACC_W-1:0]       lane_acc_w    [0:`C3_LANE_NUM-1];
    wire [`C3_FLAG_W-1:0]      lane_flags_w  [0:`C3_LANE_NUM-1];
    wire [`C3_ADDR_W-1:0]      lane_addr_w   [0:`C3_LANE_NUM-1];
    wire                       lane_req_w    [0:`C3_LANE_NUM-1];
    wire                       lane_busy_w   [0:`C3_LANE_NUM-1];
    wire [`C3_DATA_W-1:0]      local_rdata_w;
    wire                       local_busy_w;
    wire [`C3_FLAG_W-1:0]      local_err_w;
    wire                       lane_busy_or_w;
    wire [`C3_CNT_W-1:0]       mon_cycles_w;
    wire                       mon_ovf_w;
    wire                       mon_wrap_w;

    assign SP_A_D    = {lane_result_w[`C3_LANE_NUM-1][`C3_LANE_MSB:0],
                        lane_result_w[`C3_LANE_NUM-2][`C3_LANE_MSB:0],
                        lane_result_w[1][`C3_LANE_MSB:0],
                        lane_result_w[0][`C3_LANE_MSB:0]} ^ local_rdata_w;
    assign SP_A_ADDR = lane_addr_w[0][`C3_SCRATCH_ADDR_W-1:0];
    assign SP_A_CEN  = ~(|{lane_req_w[3], lane_req_w[2], lane_req_w[1], lane_req_w[0]});
    assign SP_A_WEN  = (SL_OP != `C3_OP_ST);
    assign SP_B_ADDR = lane_acc_w[2][`C3_SCRATCH_MSB:0] ^ lane_acc_w[3][`C3_SCRATCH_MSB:0];
    assign SP_B_CEN  = ~(sl_go_r & (~lane_busy_or_w));
    assign lane_busy_or_w = lane_busy_w[0] | lane_busy_w[1] | lane_busy_w[2] | lane_busy_w[3];
    assign SL_BUSY   = lane_busy_or_w | mon_ovf_w | mon_wrap_w;
    assign SL_STATUS = {local_err_w[`C3_FLAG_W-1:`C3_FLAG_W-3],
                        lane_acc_w[0][`C3_ACC_MSB:`C3_ACC_MSB-3],
                        local_busy_w};
    assign SL_CYCLES = mon_cycles_w;
    assign DESC_READY = ~SL_BUSY;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            sl_go_r    <= 1'b0;
            lane_evt_r <= {`C3_LANE_NUM{1'b0}};
        end else begin
            sl_go_r    <= DESC_VALID & ~SL_BUSY;
            lane_evt_r <= lane_evt_r | {lane_req_w[3], lane_req_w[2], lane_req_w[1], lane_req_w[0]};
        end
    end

    generate
        for (l = 0; l < `C3_LANE_NUM; l = l + 1) begin : g_lane
            wire [`C3_LANE_AW-1:0] lane_id_w;
            wire [`C3_ADDR_W-1:0]  lane_stride_w;
            wire [`C3_LANE_W-1:0]  lane_amt_w;
            wire [`C3_ROUND_W-1:0] lane_round_w;

            assign lane_id_w     = l;
            assign lane_stride_w = {{(`C3_ADDR_W-`C3_LANE_AW){1'b0}}, l};
            assign lane_amt_w    = {{(`C3_LANE_W-`C3_SLICE_AW){1'b0}}, SLICE_ID};
            assign lane_round_w  = SL_CTRL[`C3_ROUND_W-1:0];

            case3_lane u_lane[l] (
                .CLK             (CLK),
                .RST_N           (RST_N),
                .LANE_OPA        (SP_B_Q),
                .LANE_OPB        (DESC_DATA[`C3_DATA_MSB:0]),
                .LANE_ACC_IN     ({{(`C3_ACC_W-`C3_DATA_W){1'b0}}, DESC_DATA[`C3_DATA_MSB:0]}),
                .LANE_OP         (SL_OP),
                .LANE_ID         (lane_id_w),
                .LANE_RD_ADDR_A  (DESC_DATA[`C3_REG_ADDR_MSB:0]),
                .LANE_RD_ADDR_B  (SL_CTRL[`C3_REG_ADDR_MSB:0]),
                .LANE_WR_ADDR    (DESC_DATA[`C3_REG_ADDR_MSB:0]),
                .LANE_WR_DATA    (SP_A_Q),
                .LANE_WR_EN      (SL_LANE_MASK[l] & sl_go_r),
                .LANE_AGU_BASE   (SL_BASE),
                .LANE_AGU_OFF    (DESC_DATA[`C3_ADDR_MSB:0]),
                .LANE_AGU_STRIDE (lane_stride_w),
                .LANE_SHIFT_AMT  (lane_amt_w),
                .LANE_ROUND     (lane_round_w),
                .LANE_STEP       (sl_go_r),
                .LANE_RESULT     (lane_result_w[l]),
                .LANE_ACC_OUT    (lane_acc_w[l]),
                .LANE_FLAGS      (lane_flags_w[l]),
                .LANE_MEM_ADDR   (lane_addr_w[l]),
                .LANE_MEM_WDATA  (),
                .LANE_BEN        (),
                .LANE_MEM_REQ    (lane_req_w[l]),
                .LANE_MEM_WR     (),
                .LANE_BUSY       (lane_busy_w[l])
            );
        end
    endgenerate

    case3_lane_local_rf u_local_rf (
        .CLK          (SLICE_CLK),
        .RST_N        (RST_N),
        .LOCAL_ADDR   (DESC_DATA[`C3_REG_ADDR_MSB:0]),
        .LOCAL_WDATA  (DESC_DATA[`C3_DATA_MSB:0]),
        .LOCAL_RDATA  (local_rdata_w),
        .LOCAL_WE     (SL_OP == `C3_OP_WR),
        .LOCAL_RE     (SL_OP == `C3_OP_RD),
        .LOCAL_BUSY   (local_busy_w),
        .RF_ERR       (local_err_w)
    );

    case3_slice_monitor u_mon (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .SL_GO     (sl_go_r),
        .SL_BUSY   (lane_busy_or_w),
        .LANE_EVT  (lane_evt_r),
        .MON_SEL   (MON_SEL),
        .SL_CYCLES (mon_cycles_w),
        .MON_OVF   (mon_ovf_w),
        .MON_WRAP  (mon_wrap_w)
    );

endmodule
