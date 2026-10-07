//==========================================================================
//  case3_xbar_arb.v
//  交叉开关内部仲裁器：每个 virtual channel 一个，固定优先级 / 轮询可选。
//
//  Ref: NoC / AXI 交叉开关里的 VC arbiter（CHI 的 VC 仲裁、AXI xbar round-robin）。
//==========================================================================
`include "case3_define.v"

module case3_xbar_arb (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C3_LANE_NUM-1:0]  REQ_VEC,
    input  wire [`C3_LANE_AW-1:0]   PRIO,
    output reg  [`C3_LANE_NUM-1:0]  GRANT_VEC,
    output reg  [`C3_LANE_AW-1:0]   SEL,
    output wire                     ARB_BUSY
);

    parameter VC_ID     = 0;
    parameter PRIO_MODE = `C3_XBAR_ROUND_ROBIN;

    reg                     prio_r;
    reg  [`C3_LANE_NUM-1:0] mask_r;
    wire                    prio_sync_w;

    assign ARB_BUSY = |REQ_VEC;

    always @(*) begin
        GRANT_VEC = {`C3_LANE_NUM{1'b0}};
        SEL       = {`C3_LANE_AW{1'b0}};
        if (PRIO_MODE == `C3_XBAR_ROUND_ROBIN) begin
            GRANT_VEC = REQ_VEC & mask_r;
            if (~|GRANT_VEC) begin
                GRANT_VEC = REQ_VEC;
            end
        end else begin
            GRANT_VEC = (REQ_VEC & ({{(`C3_LANE_NUM-1){1'b0}}, 1'b1} << PRIO));
        end
        SEL = PRIO;
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            mask_r <= {`C3_LANE_NUM{1'b1}};
            prio_r <= 1'b0;
        end else begin
            mask_r <= {`C3_LANE_NUM{1'b1}} >> PRIO;
            prio_r <= prio_sync_w;
        end
    end

    case3_sync_2ff u_prio_sync (CLK, RST_N, prio_r, prio_sync_w);

endmodule
