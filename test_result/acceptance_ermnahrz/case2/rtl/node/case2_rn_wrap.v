//==========================================================================
//  case2_rn_wrap.v
//  RN 节点外壳：CHI RN 核 + CHI<->flit 适配 + REQ 通道仲裁
//
//  u_rn 产生本 RN 自己的 REQ flit；u_to_noc/u_to_chi 是字段级适配层
//  （旁路请求），两者在 u_req_arb 上汇合后送上 mesh local lane。
//
//  Ref: CHI RN 节点顶层（RN-F wrapper）。
//==========================================================================
`include "case2_define.v"

module case2_rn_wrap (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0]   NODEID,
    input  wire [`C2_CHI_NODEID_W-1:0]   HOMEID,
    input  wire                          REQ_START,
    input  wire [`C2_CHI_OPCODE_W-1:0]   REQ_OPCODE,
    input  wire [`C2_CHI_ADDR_W-1:0]     REQ_ADDR,
    input  wire [`C2_CHI_SIZE_W-1:0]     REQ_SIZE,
    input  wire [`C2_CHI_QOS_W-1:0]      REQ_QOS,
    input  wire [`C2_CHI_MEMATTR_W-1:0]  REQ_MEMATTR,
    input  wire [`C2_CHI_SNPATTR_W-1:0]  REQ_SNPATTR,
    input  wire [`C2_CHI_DATA_W-1:0]     WDATA,
    input  wire [`C2_CHI_BE_W-1:0]       WBE,
    input  wire                          WDATA_VALID,
    output wire                          WDATA_READY,
    output wire [`C2_REQ_FLIT_W-1:0]     REQ_TX,
    output wire                          REQ_TX_VALID,
    input  wire                          REQ_TX_READY,
    input  wire [`C2_RSP_FLIT_W-1:0]     RSP_RX,
    input  wire                          RSP_RX_VALID,
    output wire                          RSP_RX_READY,
    input  wire [`C2_SNP_FLIT_W-1:0]     SNP_RX,
    input  wire                          SNP_RX_VALID,
    output wire                          SNP_RX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]     DAT_RX,
    input  wire                          DAT_RX_VALID,
    output wire                          DAT_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]     RSP_TX,
    output wire                          RSP_TX_VALID,
    input  wire                          RSP_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]     DAT_TX,
    output wire                          DAT_TX_VALID,
    input  wire                          DAT_TX_READY,
    output wire [`C2_CREDIT_W-1:0]       CREDIT_ON,
    input  wire [`C2_CREDIT_W-1:0]       CREDIT_RET,
    output wire [`C2_CHI_RESP_W-1:0]     RESP,
    output wire [`C2_CHI_RESPERR_W-1:0]  RESPERR,
    output wire [`C2_CHI_TXNID_W-1:0]    TXNID,
    output wire                          RN_IDLE,

    input wire [16 -1:0] ec_debug_in // Moved acceptance
);

    wire [`C2_REQ_FLIT_W-1:0]  rn_req_flit;
    wire                       rn_req_valid;
    wire                       rn_req_ready;
    wire [`C2_REQ_FLIT_W-1:0]  adapter_req_flit;
    wire                       adapter_req_valid;
    wire                       adapter_req_ready;
    wire [`C2_DAT_FLIT_W-1:0]  adapter_dat_flit;
    wire                       adapter_dat_valid;
    wire                       adapter_dat_ready;
    wire [`C2_CHI_TAG_W-1:0]   rn_tag;
    wire [`C2_CHI_DATA_W-1:0]  rn_rdata;
    wire [`C2_CHI_BE_W-1:0]    rn_rbe;
    wire                       rn_rsp_done;
    wire                       rn_snp_hit;
    wire [`C2_CHI_OPCODE_W-1:0] adapter_opcode;
    wire [`C2_CHI_RESP_W-1:0]   adapter_resp;
    wire [`C2_CHI_RESPERR_W-1:0] adapter_resperr;
    wire [`C2_CHI_TXNID_W-1:0]  adapter_txnid_out;
    wire [`C2_CHI_TXNID_W-1:0]  adapter_txnid_in;
    wire [`C2_CHI_DATA_W-1:0]   adapter_data;
    wire [`C2_CHI_BE_W-1:0]     adapter_be;
    wire [`C2_CHI_DBID_W-1:0]   adapter_dbid;
    wire                         adapter_chi_valid;
    wire                         adapter_order_err;
    wire                         adapter_chi_last;
    wire [`C2_VC_NUM-1:0]        adapter_vc_free;
    wire [`C2_PORT_NUM-1:0]      req_gnt;
    wire [`C2_PORT_AW-1:0]       req_gnt_idx;
    wire                         req_gnt_valid;

    reg [`C2_REQ_FLIT_W-1:0] req_mux;

    assign RN_IDLE    = ~(REQ_TX_VALID | RSP_TX_VALID | DAT_TX_VALID);
    assign TXNID      = adapter_txnid_in;
    assign RESP       = adapter_resp;
    assign RESPERR    = adapter_resperr;
    assign REQ_TX     = req_mux;
    assign DAT_TX     = adapter_dat_flit;
    assign DAT_TX_VALID = adapter_dat_valid & (~DAT_TX_READY);
    assign REQ_TX_VALID = req_gnt_valid;

    //------------------------------------------------------------------
    // CHI RN 核
    //------------------------------------------------------------------
    case2_chi_rn u_rn (
        .CLK             (CLK),
        .RST_N           (RST_N),
        .NODEID          (NODEID),
        .HOMEID          (HOMEID),
        .REQ_START       (REQ_START),
        .REQ_OPCODE      (REQ_OPCODE),
        .REQ_ADDR        (REQ_ADDR),
        .REQ_SIZE        (REQ_SIZE),
        .REQ_QOS         (REQ_QOS),
        .REQ_MEMATTR     (REQ_MEMATTR),
        .REQ_SNPATTR     (REQ_SNPATTR),
        .WDATA           (WDATA),
        .WBE             (WBE),
        .WDATA_VALID     (WDATA_VALID),
        .WDATA_READY     (WDATA_READY),
        .REQ_FLIT        (rn_req_flit),
        .REQ_FLIT_VALID  (rn_req_valid),
        .REQ_FLIT_READY  (rn_req_ready),
        .TXNID           (),
        .TAG             (rn_tag),
        .RSP_RX          (RSP_RX),
        .RSP_RX_VALID    (RSP_RX_VALID),
        .RSP_RX_READY    (RSP_RX_READY),
        .SNP_RX          (SNP_RX),
        .SNP_RX_VALID    (SNP_RX_VALID),
        .SNP_RX_READY    (SNP_RX_READY),
        .DAT_RX          (DAT_RX),
        .DAT_RX_VALID    (DAT_RX_VALID),
        .DAT_RX_READY    (DAT_RX_READY),
        .RSP_TX          (RSP_TX),
        .RSP_TX_VALID    (RSP_TX_VALID),
        .RSP_TX_READY    (RSP_TX_READY),
        .DAT_TX          (),
        .DAT_TX_VALID    (),
        .DAT_TX_READY    (1'b1),
        .RESP            (),
        .RESPERR         (),
        .RDATA           (rn_rdata),
        .RBE             (rn_rbe),
        .RSP_DONE        (rn_rsp_done),
        .SNP_HIT         (rn_snp_hit),
    
        .ec_debug_in(ec_debug_in) // Moved acceptance
);

    //------------------------------------------------------------------
    // CHI <-> flit 适配（旁路请求 + 写数据）
    //------------------------------------------------------------------
    case2_chi_to_noc u_to_noc (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .OPCODE     (REQ_OPCODE),
        .ADDR       (REQ_ADDR),
        .SIZE       (REQ_SIZE),
        .QOS        (REQ_QOS),
        .MEMATTR    (REQ_MEMATTR),
        .SNPATTR    (REQ_SNPATTR),
        .SRCID      (NODEID),
        .TGTID      (HOMEID),
        .DATA       (WDATA),
        .BE         (WBE),
        .CHI_VALID  (WDATA_VALID),
        .CHI_READY  (),
        .TXNID      (adapter_txnid_out),
        .TAG        (),
        .REQ_TX     (adapter_req_flit),
        .REQ_TX_VALID(adapter_req_valid),
        .REQ_TX_READY(adapter_req_ready),
        .DAT_TX     (adapter_dat_flit),
        .DAT_TX_VALID(adapter_dat_valid),
        .DAT_TX_READY(adapter_dat_ready),
        .CREDIT_RET (CREDIT_RET),
        .CREDIT_ON  (CREDIT_ON),
        .VC_FREE    (adapter_vc_free)
    );

    case2_noc_to_chi u_to_chi (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .RSP_RX     (RSP_RX),
        .RSP_RX_VALID(RSP_RX_VALID),
        .RSP_RX_READY(),
        .DAT_RX     (DAT_RX),
        .DAT_RX_VALID(DAT_RX_VALID),
        .DAT_RX_READY(),
        .OPCODE     (adapter_opcode),
        .TXNID      (adapter_txnid_in),
        .RESP       (adapter_resp),
        .RESPERR    (adapter_resperr),
        .FWDSTATE   (),
        .DATA       (adapter_data),
        .BE         (adapter_be),
        .DBID       (adapter_dbid),
        .DATAID     (),
        .CHI_VALID  (adapter_chi_valid),
        .ORDER_ERR  (adapter_order_err),
        .CHI_LAST   (adapter_chi_last)
    );

    //------------------------------------------------------------------
    // REQ 通道两路仲裁：RN 核 REQ 优先，其次旁路适配请求
    //------------------------------------------------------------------
    case2_noc_arbiter u_req_arb (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ       ({{(`C2_PORT_NUM-`C2_ARB_LOCAL_SRC_NUM){1'b0}}, adapter_req_valid, rn_req_valid}),
        .CREDIT    ({`C2_PORT_NUM{1'b1}}),
        .HOLD      (~REQ_TX_READY),
        .GNT       (req_gnt),
        .GNT_IDX   (req_gnt_idx),
        .GNT_VALID (req_gnt_valid),
        .ALLOC_FAIL()
    );

    always @(*) begin
        if (req_gnt[0])      req_mux = rn_req_flit;
        else if (req_gnt[1]) req_mux = adapter_req_flit;
        else                 req_mux = {`C2_REQ_FLIT_W{1'b0}};
    end

    assign rn_req_ready      = req_gnt[0] & REQ_TX_READY;
    assign adapter_req_ready = req_gnt[1] & REQ_TX_READY;
    assign adapter_dat_ready = DAT_TX_READY;

endmodule
