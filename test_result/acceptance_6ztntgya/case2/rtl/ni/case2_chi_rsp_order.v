//==========================================================================
//  case2_chi_rsp_order.v
//  RSP 通道的顺序检查：同一 TxnID 的响应必须按序返回
//
//  Ref: CHI 的 response ordering 规则（同 ID 有序、不同 ID 可乱序）。
//       无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_chi_rsp_order (
    input  wire                         CLK,
    input  wire                         RST_N,
    input  wire                         RSP_VALID,
    input  wire [`C2_CHI_TXNID_W-1:0]   TXNID,
    input  wire [`C2_CHI_RESP_W-1:0]    RESP,
    input  wire [`C2_CHI_RESPERR_W-1:0] RESPERR,
    output reg                          ORDER_OK,
    output reg                          ORDER_ERR,
    output reg  [`C2_CHI_TXNID_W-1:0]   ORDER_HEAD,
    output reg  [`C2_SNP_FILTER_W-1:0]  ORDER_MASK,
    output wire [`C2_CHI_RESPERR_W-1:0] RESPERR_ACC
);

    assign RESPERR_ACC = (RESPERR == `C2_RESPERR_OKAY) ? `C2_RESPERR_OKAY : RESPERR;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            ORDER_HEAD <= {`C2_CHI_TXNID_W{1'b0}};
            ORDER_MASK <= {`C2_SNP_FILTER_W{1'b0}};
            ORDER_OK   <= 1'b0;
            ORDER_ERR  <= 1'b0;
        end else if (RSP_VALID) begin
            ORDER_HEAD <= TXNID;
            ORDER_MASK <= {{(`C2_SNP_FILTER_W-`C2_CHI_TXNID_W){1'b0}}, TXNID};
            ORDER_OK   <= (RESPERR == `C2_RESPERR_OKAY) & (RESP != `C2_RESP_I_PD);
            ORDER_ERR  <= (RESPERR == `C2_RESPERR_DERR) |
                          (RESPERR == `C2_RESPERR_NDERR);
        end
    end

endmodule
