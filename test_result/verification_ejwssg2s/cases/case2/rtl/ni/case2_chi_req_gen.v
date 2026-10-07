//==========================================================================
//  case2_chi_req_gen.v
//  RN 请求生成：TxnID 分配 + REQ flit 打包
//
//  Ref: CHI RN 的 request generator（REQ 通道上游）。
//==========================================================================
`include "case2_define.v"

module case2_chi_req_gen (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire                        REQ_START,
    input  wire                        REQ_FREE,
    input  wire [`C2_CHI_OPCODE_W-1:0] REQ_OPCODE,
    input  wire [`C2_CHI_ADDR_W-1:0]   ADDR,
    input  wire [`C2_CHI_SIZE_W-1:0]   SIZE,
    input  wire [`C2_CHI_QOS_W-1:0]    QOS,
    input  wire [`C2_CHI_MEMATTR_W-1:0] MEMATTR,
    input  wire [`C2_CHI_SNPATTR_W-1:0] SNPATTR,
    input  wire [`C2_CHI_NODEID_W-1:0] SRCID,
    input  wire [`C2_CHI_NODEID_W-1:0] TGTID,
    input  wire [`C2_CHI_DATA_W-1:0]   DATA,
    input  wire [`C2_CHI_BE_W-1:0]     BE,
    input  wire [`C2_CHI_TXNID_W-1:0]  FREE_ID,
    output wire [`C2_CHI_TXNID_W-1:0]  TXNID,
    output wire [`C2_CHI_TAG_W-1:0]    TAG,
    output wire [`C2_REQ_FLIT_W-1:0]   REQ_FLIT,
    output wire                        REQ_VALID,
    input  wire                        REQ_READY,
    output wire                        ALLOC_FULL,
    output wire [`C2_CREDIT_W-1:0]     TXNID_FREE_CNT,
    output wire [`C2_SNP_FILTER_W-1:0] TXNID_MASK,

    input wire [8 -1:0] ec_debug_in // EasyConnect 1.0 验收
);

    wire [`C2_CHI_TXNID_W-1:0] txnid_alloc;
    wire                       txnid_valid;
    wire                       alloc_full;
    wire [`C2_CREDIT_W-1:0]    txnid_free;
    wire [`C2_SNP_FILTER_W-1:0] txnid_mask;

    reg                        req_valid_r;
    reg  [`C2_CHI_TAG_W-1:0]   tag_r;
    reg  [`C2_CHI_LPID_W-1:0]  lpid_r;

    assign TXNID          = txnid_alloc;
    assign TAG            = tag_r;
    assign REQ_VALID      = req_valid_r & (~alloc_full);
    assign ALLOC_FULL     = alloc_full;
    assign TXNID_FREE_CNT = txnid_free;
    assign TXNID_MASK     = txnid_mask;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            req_valid_r <= 1'b0;
            tag_r       <= {`C2_CHI_TAG_W{1'b0}};
            lpid_r      <= {`C2_CHI_LPID_W{1'b0}};
        end else if (REQ_START) begin
            req_valid_r <= 1'b1;
            tag_r       <= tag_r + {{(`C2_CHI_TAG_W-1){1'b0}}, 1'b1};
            lpid_r      <= SRCID[`C2_CHI_LPID_W-1:0];
        end else if (REQ_READY) begin
            req_valid_r <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // TxnID 分配
    //------------------------------------------------------------------
    case2_chi_txnid_alloc u_txnid (
        .CLK            (CLK),
        .RST_N          (RST_N),
        .ALLOC_REQ      (REQ_START),
        .FREE_REQ       (REQ_FREE),
        .FREE_ID        (FREE_ID),
        .TXNID          (txnid_alloc),
        .TXNID_VALID    (txnid_valid),
        .TXNID_FREE_CNT (txnid_free),
        .ALLOC_FULL     (alloc_full),
        .TXNID_MASK     (txnid_mask)
    );

    //------------------------------------------------------------------
    // REQ flit 打包（字段位置全部来自 define 文件）
    //------------------------------------------------------------------
    case2_chi_flit_pack u_pack (
        .CHI_VALID   (req_valid_r),
        .QOS         (QOS),
        .SRCID       (SRCID),
        .TGTID       (TGTID),
        .RETURNID    (SRCID),
        .FWDNID      (TGTID),
        .TXNID       (txnid_alloc),
        .FWDTXNID    (txnid_alloc),
        .OPCODE      (REQ_OPCODE),
        .SIZE        (SIZE),
        .ADDR        (ADDR),
        .NS          (1'b0),
        .MEMATTR     (MEMATTR),
        .SNPATTR     (SNPATTR),
        .EXPCOMPACK  (1'b1),
        .TAG         (tag_r),
        .LPID        (lpid_r),
        .MPAM        ({`C2_CHI_MPAM_W{1'b0}}),
        .PCRDTYPE    ({`C2_CHI_PCRDTYPE_W{1'b0}}),
        .ALLOWRETRY  (1'b1),
        .ORDER       ({`C2_CHI_ORDER_W{1'b0}}),
        .RESP        (`C2_RESP_ICO),
        .RESPERR     (`C2_RESPERR_OKAY),
        .FWDSTATE    (`C2_FWDSTATE_I),
        .DATASOURCE  ({`C2_CHI_DATASOURCE_W{1'b0}}),
        .CBUSY       ({`C2_CHI_CBUSY_W{1'b0}}),
        .DATAID      ({`C2_CHI_DATAID_W{1'b0}}),
        .CCID        ({`C2_CHI_CCID_W{1'b0}}),
        .DBID        ({`C2_CHI_DBID_W{1'b0}}),
        .RETTOSRC    (1'b0),
        .TRACETAG    ({`C2_CHI_TRACETAG_W{1'b0}}),
        .BE          (BE),
        .DATA        (DATA),
        .REQ_FLIT    (REQ_FLIT),
        .RSP_FLIT    (),
        .SNP_FLIT    (),
        .DAT_FLIT    ()
    );

endmodule
