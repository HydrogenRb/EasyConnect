//==========================================================================
//  case2_chi_hn.v
//  CHI home node：snoop filter + 请求流水 + 响应生成 + 数据流水
//
//  Ref: CHI HN-F（目录、snoop 产生、响应/数据回送）。
//==========================================================================
`include "case2_define.v"

module case2_chi_hn (
    input  wire                            CLK,
    input  wire                            RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0]     NODEID,
    input  wire [`C2_REQ_FLIT_W-1:0]       REQ_RX,
    input  wire                            REQ_RX_VALID,
    output wire                            REQ_RX_READY,
    output wire [`C2_SNP_FLIT_W-1:0]       SNP_TX,
    output wire                            SNP_TX_VALID,
    input  wire                            SNP_TX_READY,
    input  wire [`C2_RSP_FLIT_W-1:0]       RSP_RX,
    input  wire                            RSP_RX_VALID,
    output wire                            RSP_RX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]       DAT_RX,
    input  wire                            DAT_RX_VALID,
    output wire                            DAT_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]       RSP_TX,
    output wire                            RSP_TX_VALID,
    input  wire                            RSP_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]       DAT_TX,
    output wire                            DAT_TX_VALID,
    input  wire                            DAT_TX_READY,
    output wire [`C2_SNP_FILTER_W-1:0]     SNP_VEC,
    output wire                            HIT_ANY,
    output wire [`C2_CHI_ADDR_W-1:0]       HN_ADDR,
    output wire                            HN_IDLE
);

    wire [`C2_CHI_OPCODE_W-1:0]   req_opcode;
    wire [`C2_CHI_TXNID_W-1:0]    req_txnid;
    wire [`C2_CHI_NODEID_W-1:0]   req_srcid;
    wire                          req_valid;
    wire                          req_ready;
    wire [`C2_SNP_FILTER_W-1:0]   hit_vec;
    wire                          hit_any;
    wire [`C2_CHI_FWDSTATE_W-1:0] fwdstate;
    wire [`C2_CHI_DATASOURCE_W-1:0] datasource;
    wire [`C2_RSP_FLIT_W-1:0]     packed_rsp;
    wire [`C2_SNP_FLIT_W-1:0]     packed_snp;
    wire                          rsp_valid;
    wire                          snp_done;
    wire [`C2_CHI_DATA_W-1:0]     hn_data;
    wire [`C2_CHI_BE_W-1:0]       hn_be;
    wire [`C2_CHI_DBID_W-1:0]     hn_dbid;
    wire [`C2_CHI_DATAID_W-1:0]   hn_dataid;
    wire                          dat_last;
    wire [`C2_TAG_RAM_DW-1:0]     tag_data;
    wire                          tag_full;
    wire [`C2_CHI_QOS_W-1:0]        qos;
    wire [`C2_CHI_NODEID_W-1:0]     tgtid;
    wire [`C2_CHI_NODEID_W-1:0]     returnid;
    wire [`C2_CHI_SIZE_W-1:0]       size;
    wire [`C2_CHI_MEMATTR_W-1:0]    memattr;
    wire [`C2_CHI_TAG_W-1:0]        tag;
    wire                            is_snp;
    wire                            is_dat;
    wire                            is_rsp;

    assign HN_ADDR  = REQ_RX[`C2_REQ_FIELD_ADDR_MSB:`C2_REQ_FIELD_ADDR_LSB];
    assign HN_IDLE  = ~(REQ_RX_VALID | req_valid | rsp_valid);
    assign snp_done = RSP_RX_VALID | DAT_RX_VALID;

    //------------------------------------------------------------------
    // 请求流水 + 目录查找
    //------------------------------------------------------------------
    case2_hn_req_pipe u_req_pipe (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .REQ_IN       (REQ_RX),
        .REQ_IN_VALID (REQ_RX_VALID),
        .REQ_IN_READY (REQ_RX_READY),
        .ADDR         (),
        .OPCODE       (req_opcode),
        .TXNID        (req_txnid),
        .SRCID        (req_srcid),
        .REQ_VALID    (req_valid),
        .HIT_VEC      (hit_vec),
        .HIT_ANY      (hit_any)
    );

    case2_hn_snoop_filter u_sfilter (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .LOOKUP_REQ (req_valid),
        .ADDR       (HN_ADDR),
        .SRCID      (req_srcid),
        .UPDATE_REQ (req_valid & req_ready),
        .BE         (DAT_RX[`C2_DAT_FIELD_BE_MSB:`C2_DAT_FIELD_BE_LSB]),
        .SNP_VEC    (SNP_VEC),
        .HIT_ANY    (HIT_ANY),
        .FWDSTATE   (fwdstate),
        .DATASOURCE (datasource),
        .TAG_DATA   (tag_data),
        .TAG_FULL   (tag_full)
    );

    //------------------------------------------------------------------
    // 响应生成
    //------------------------------------------------------------------
    case2_hn_rsp_gen u_rsp_gen (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .REQ_VALID  (req_valid),
        .REQ_OPCODE (req_opcode),
        .HIT_ANY    (hit_any),
        .SNP_DONE   (snp_done),
        .RESPERR_IN (`C2_RESPERR_OKAY),
        .RESP       (),
        .RESPERR    (),
        .FWDSTATE   (),
        .DATASOURCE (),
        .RSP_OPCODE (),
        .RSP_VALID  (rsp_valid)
    );

    //------------------------------------------------------------------
    // 数据流水（内部例化 RAM_SP_BE 的 FIFO）
    //------------------------------------------------------------------
    case2_hn_dat_pipe u_dat_pipe (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .DAT_IN       (DAT_RX),
        .DAT_IN_VALID (DAT_RX_VALID),
        .DAT_IN_READY (DAT_RX_READY),
        .DAT_OUT      (DAT_TX),
        .DAT_OUT_VALID(DAT_TX_VALID),
        .DAT_OUT_READY(DAT_TX_READY),
        .DATA         (hn_data),
        .BE           (hn_be),
        .DBID         (hn_dbid),
        .DATAID       (hn_dataid),
        .DAT_LAST     (dat_last)
    );

    assign req_ready = ~req_valid;

    //------------------------------------------------------------------
    // 响应 / snoop 打包
    //------------------------------------------------------------------
    case2_chi_flit_pack u_pack (
        .CHI_VALID   (rsp_valid),
        .QOS         (qos),
        .SRCID       (NODEID),
        .TGTID       (req_srcid),
        .RETURNID    (req_srcid),
        .FWDNID      (req_srcid),
        .TXNID       (req_txnid),
        .FWDTXNID    (req_txnid),
        .OPCODE      (`C2_OP_SNP_UNIQUE),
        .SIZE        (size),
        .ADDR        (HN_ADDR),
        .NS          (1'b0),
        .MEMATTR     (memattr),
        .SNPATTR     (1'b1),
        .EXPCOMPACK  (1'b1),
        .TAG         (tag),
        .LPID        ({`C2_CHI_LPID_W{1'b0}}),
        .MPAM        ({`C2_CHI_MPAM_W{1'b0}}),
        .PCRDTYPE    ({`C2_CHI_PCRDTYPE_W{1'b0}}),
        .ALLOWRETRY  (1'b1),
        .ORDER       ({`C2_CHI_ORDER_W{1'b0}}),
        .RESP        (`C2_RESP_UC),
        .RESPERR     (`C2_RESPERR_OKAY),
        .FWDSTATE    (fwdstate),
        .DATASOURCE  (datasource),
        .CBUSY       ({`C2_CHI_CBUSY_W{1'b0}}),
        .DATAID      (hn_dataid),
        .CCID        ({`C2_CHI_CCID_W{1'b0}}),
        .DBID        (hn_dbid),
        .RETTOSRC    (1'b1),
        .TRACETAG    ({`C2_CHI_TRACETAG_W{1'b0}}),
        .BE          (hn_be),
        .DATA        (hn_data),
        .REQ_FLIT    (),
        .RSP_FLIT    (packed_rsp),
        .SNP_FLIT    (packed_snp),
        .DAT_FLIT    ()
    );

    assign RSP_TX       = packed_rsp;
    assign SNP_TX       = packed_snp;
    assign RSP_TX_VALID = rsp_valid & (~RSP_TX_READY);
    assign SNP_TX_VALID = rsp_valid & (~SNP_TX_READY);

endmodule
