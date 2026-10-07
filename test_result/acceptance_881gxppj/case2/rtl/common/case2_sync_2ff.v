//==========================================================================
//  case2_sync_2ff.v
//  单比特两级触发器同步器（跨 mesh link 的 valid / link_active 握手同步级）
//
//  Ref: 真实 NoC 里 link 握手信号、credit 归还脉冲跨路由器同步时使用的
//       2FF synchronizer；本单元无任何例化，是层次树的叶子。
//==========================================================================
`include "case2_define.v"

module case2_sync_2ff (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    D,
    output reg                     Q
);

    parameter STAGES = 2;

    reg [`C2_SYNC_STAGE_W-1:0] sync_pipe;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            sync_pipe <= {`C2_SYNC_STAGE_W{1'b0}};
        end else begin
            sync_pipe <= {sync_pipe[`C2_SYNC_STAGE_W-2:0], D};
        end
    end

    always @(*) begin
        Q = sync_pipe[`C2_SYNC_STAGE_W-1];
    end

endmodule
