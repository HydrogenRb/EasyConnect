//==========================================================================
//  case3_cnt_wrap.v
//  计数器包装层：按参数在“性能计数器”与“纯同步器”之间做 generate-if 选择。
//  该模块不是叶子 —— 内部的例化只在 generate-if 分支里出现。
//
//  Ref: 项目里常见的 cnt_wrap / counter_shell 适配层
//       （同一 RTL 既支持 full counter 也支持 dummy tie-off）。
//==========================================================================
`include "case3_define.v"

module case3_cnt_wrap (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       EVT,
    input  wire                       CLR,
    input  wire [`C3_MON_SEL_W-1:0]   MON_SEL,
    input  wire [`C3_XFER_CNT_W-1:0]  INC,
    output wire [`C3_CNT_W-1:0]       CNT,
    output wire                       WRAP,
    output wire                       OVF_SYNC
);

    parameter WRAP_EN = `C3_PERF_WRAP_EN;
    parameter WRAP_AT = `C3_PERF_WRAP_VAL;

    wire                 cnt_ovf;
    wire [`C3_CNT_W-1:0] cnt_sat;

    generate
        if (WRAP_EN == 1) begin : g_wrap_cnt
            case3_perf_counter u_cnt_core (
                .CLK     (CLK),
                .RST_N   (RST_N),
                .EN      (EVT),
                .CLR     (CLR),
                .MON_SEL (MON_SEL),
                .INC     (INC),
                .CNT     (CNT),
                .OVF     (cnt_ovf),
                .CNT_SAT (cnt_sat)
            );
        end else begin : g_plain_cnt
            case3_sync_2ff u_evt_sync (CLK, RST_N, EVT, OVF_SYNC);
        end
    endgenerate

    assign WRAP = (EVT & (CNT >= WRAP_AT));

endmodule
