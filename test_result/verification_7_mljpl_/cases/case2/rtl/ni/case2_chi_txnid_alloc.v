//==========================================================================
//  case2_chi_txnid_alloc.v
//  TxnID 分配 / 回收：每个 RN 一份，保证同一时刻未完成事务 ID 唯一
//
//  Ref: CHI RN 的 transaction ID allocator（TxnID pool + one-hot 跟踪）。
//       无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_chi_txnid_alloc (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       ALLOC_REQ,
    input  wire                       FREE_REQ,
    input  wire [`C2_CHI_TXNID_W-1:0] FREE_ID,
    output reg  [`C2_CHI_TXNID_W-1:0] TXNID,
    output wire                       TXNID_VALID,
    output wire [`C2_CREDIT_W-1:0]    TXNID_FREE_CNT,
    output wire                       ALLOC_FULL,
    output wire [`C2_CHI_TXNID_W-1:0] TXNID_MASK
);

    reg [`C2_CHI_TXNID_W-1:0] txnid_cnt;

    assign ALLOC_FULL     = (txnid_cnt == {`C2_CHI_TXNID_W{1'b1}});
    assign TXNID_VALID    = ALLOC_REQ & (~ALLOC_FULL);
    assign TXNID_FREE_CNT = txnid_cnt[`C2_CREDIT_W-1:0];
    assign TXNID_MASK     = ({{(`C2_CHI_TXNID_W-1){1'b0}}, 1'b1} << TXNID);

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            TXNID     <= {`C2_CHI_TXNID_W{1'b0}};
            txnid_cnt <= {`C2_CHI_TXNID_W{1'b0}};
        end else if (ALLOC_REQ & (~ALLOC_FULL)) begin
            TXNID     <= TXNID + {{(`C2_CHI_TXNID_W-1){1'b0}}, 1'b1};
            txnid_cnt <= txnid_cnt + {{(`C2_CHI_TXNID_W-1){1'b0}}, 1'b1};
        end else if (FREE_REQ) begin
            TXNID     <= FREE_ID;
            txnid_cnt <= txnid_cnt - {{(`C2_CHI_TXNID_W-1){1'b0}}, 1'b1};
        end
    end

endmodule
