//==========================================================================
//  case2_noc_credit_ctrl.v
//  单条 link（或单个 VC）的 credit 记账：初始预算、发送扣减、归还累加
//
//  Ref: credit-based flow control（credit_on_* / *_credit_cnt）。
//       无例化，叶子单元；在 router_port / noc_vc / credit_mgr 中复用。
//==========================================================================
`include "case2_define.v"

module case2_noc_credit_ctrl (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    INIT,
    input  wire                    SEND,
    input  wire                    RET,
    input  wire [`C2_CREDIT_W-1:0] RET_NUM,
    output reg  [`C2_CREDIT_W-1:0] CREDIT_CNT,
    output wire                    CREDIT_OK,
    output wire [`C2_CREDIT_W-1:0] CREDIT_ON
);

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            CREDIT_CNT <= {`C2_CREDIT_W{1'b0}};
        end else if (INIT) begin
            CREDIT_CNT <= `C2_CREDIT_INIT;
        end else if (SEND & RET) begin
            CREDIT_CNT <= CREDIT_CNT + RET_NUM;
        end else if (SEND) begin
            CREDIT_CNT <= CREDIT_CNT - {{(`C2_CREDIT_W-1){1'b0}}, 1'b1};
        end else if (RET) begin
            CREDIT_CNT <= CREDIT_CNT + RET_NUM;
        end
    end

    assign CREDIT_OK = (CREDIT_CNT != {`C2_CREDIT_W{1'b0}});
    assign CREDIT_ON = RET ? RET_NUM : {`C2_CREDIT_W{1'b0}};

endmodule
