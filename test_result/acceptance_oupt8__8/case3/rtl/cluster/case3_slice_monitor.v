//==========================================================================
//  case3_slice_monitor.v
//  slice 级性能监测：包装计数器（cnt_wrap → perf_counter），并直接例化一个
//  lane 事件计数器与一个溢出同步器。
//
//  Ref: SoC 里按簇/按片挂载的 perf monitor（CoreSight PMU 的分级计数结构）。
//==========================================================================
`include "case3_define.v"

module case3_slice_monitor (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       SL_GO,
    input  wire                       SL_BUSY,
    input  wire [`C3_LANE_NUM-1:0]    LANE_EVT,
    input  wire [`C3_MON_SEL_W-1:0]   MON_SEL,
    output wire [`C3_CNT_W-1:0]       SL_CYCLES,
    output wire                       MON_OVF,
    output wire                       MON_WRAP
);

    parameter MON_ID     = 0;
    parameter MON_ENABLE = `C3_ENABLE_MONITOR;

    wire [`C3_CNT_W-1:0]      lane_cnt;
    wire                      lane_ovf;
    wire                      ovf_sync_w;
    wire                      ovf_sync_plain_w;
    wire [`C3_XFER_CNT_W-1:0] evt_inc;

    assign evt_inc = {{(`C3_XFER_CNT_W-`C3_LANE_NUM){1'b0}}, LANE_EVT};
    assign MON_OVF = lane_ovf | ovf_sync_plain_w;

    // 主计数器：走 cnt_wrap 包装层（命名端口连接）
    case3_cnt_wrap u_cnt_wrap (
        .CLK     (CLK),
        .RST_N   (RST_N),
        .EVT     (SL_BUSY),
        .CLR     (SL_GO),
        .MON_SEL (MON_SEL),
        .INC     (evt_inc),
        .CNT     (SL_CYCLES),
        .WRAP    (MON_WRAP),
        .OVF_SYNC(ovf_sync_w)
    );

    // 直接例化的 lane 事件计数器（命名端口连接）
    case3_perf_counter u_lane_cnt (
        .CLK     (CLK),
        .RST_N   (RST_N),
        .EN      (|LANE_EVT),
        .CLR     (SL_GO),
        .MON_SEL (MON_SEL),
        .INC     (evt_inc),
        .CNT     (lane_cnt),
        .OVF     (lane_ovf),
        .CNT_SAT ()
    );

    // 溢出打拍（位置端口连接）
    case3_sync_2ff u_ovf_sync (CLK, RST_N, lane_ovf, ovf_sync_plain_w);

endmodule
