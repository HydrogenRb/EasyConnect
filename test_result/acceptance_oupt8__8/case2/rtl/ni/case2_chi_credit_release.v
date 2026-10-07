//==========================================================================
//  case2_chi_credit_release.v
//  CHI 事务完成 -> P-Credit / link credit 归还脉冲
//
//  Ref: CHI 的 P-Credit（PCrdGrant）归还路径；本样本里归还脉冲同时
//       释放一个 VC。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_chi_credit_release (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       RELEASE,
    input  wire [`C2_CHI_TXNID_W-1:0] TXNID,
    input  wire [`C2_VC_NUM-1:0]      VC_BUSY,
    output reg  [`C2_CREDIT_W-1:0]    CREDIT_RET,
    output reg  [`C2_VC_NUM-1:0]      VC_FREE,
    output wire                       RELEASE_DONE,
    output reg  [`C2_CHI_TXNID_W-1:0] TXNID_HOLD
);

    reg pending_r;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            CREDIT_RET <= {`C2_CREDIT_W{1'b0}};
            VC_FREE    <= {`C2_VC_NUM{1'b0}};
            TXNID_HOLD <= {`C2_CHI_TXNID_W{1'b0}};
            pending_r  <= 1'b0;
        end else begin
            CREDIT_RET <= RELEASE ? {{(`C2_CREDIT_W-1){1'b0}}, 1'b1}
                                  : {`C2_CREDIT_W{1'b0}};
            VC_FREE    <= ~VC_BUSY;
            TXNID_HOLD <= TXNID;
            pending_r  <= RELEASE;
        end
    end

    assign RELEASE_DONE = pending_r & (~RELEASE);

endmodule
