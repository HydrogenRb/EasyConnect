//==========================================================================
//  case3_perf_counter.v
//  性能计数器：可清零、可饱和、带溢出指示的 32 位事件计数器。
//  叶子模块（内部没有任何例化）。
//
//  Ref: 模仿 CoreSight / perf-monitor 里的 event counter
//       （ARM PMU event counter、RISC-V mcycle/mhpmcounter 的行为模型）。
//==========================================================================
`include "case3_define.v"

module case3_perf_counter (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       EN,
    input  wire                       CLR,
    input  wire [`C3_MON_SEL_W-1:0]   MON_SEL,
    input  wire [`C3_XFER_CNT_W-1:0]  INC,
    output reg  [`C3_CNT_W-1:0]       CNT,
    output wire                       OVF,
    output wire [`C3_CNT_W-1:0]       CNT_SAT
);

    parameter CNT_WIDTH = `C3_CNT_W;
    parameter SATURATE  = `C3_ENABLE_MONITOR;

    reg [`C3_CNT_W:0] cnt_ext;
    reg [`C3_MON_SEL_W-1:0] sel_r;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            cnt_ext <= {(`C3_CNT_W+1){1'b0}};
            sel_r   <= {`C3_MON_SEL_W{1'b0}};
        end else if (CLR) begin
            cnt_ext <= {(`C3_CNT_W+1){1'b0}};
            sel_r   <= MON_SEL;
        end else if (EN) begin
            cnt_ext <= cnt_ext + {{`C3_CNT_W{1'b0}}, 1'b1} + {{(`C3_CNT_W-`C3_XFER_CNT_W){1'b0}}, INC};
            sel_r   <= MON_SEL;
        end
    end

    assign CNT     = cnt_ext[`C3_CNT_MSB:0];
    assign OVF     = cnt_ext[`C3_CNT_W];
    assign CNT_SAT = (cnt_ext[`C3_CNT_W]) ? {`C3_CNT_W{1'b1}} : cnt_ext[`C3_CNT_MSB:0];

endmodule
