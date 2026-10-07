//==========================================================================
//  case2_chi_flit_pack.v
//  CHI 字段 -> REQ / RSP / SNP / DAT flit 打包（纯组合）
//
//  四个通道的字段位置全部来自 case2_define.v 的 `C2_*_FIELD_* 宏，
//  是"字段宏被真正使用"的地方。无例化，叶子单元。
//
//  Ref: CHI 协议层到链路层 flit 的打包逻辑（flit packer）。
//==========================================================================
`include "case2_define.v"

module case2_chi_flit_pack (
    input  wire                            CHI_VALID,
    input  wire [`C2_CHI_QOS_W-1:0]        QOS,
    input  wire [`C2_CHI_NODEID_W-1:0]     SRCID,
    input  wire [`C2_CHI_NODEID_W-1:0]     TGTID,
    input  wire [`C2_CHI_NODEID_W-1:0]     RETURNID,
    input  wire [`C2_CHI_NODEID_W-1:0]     FWDNID,
    input  wire [`C2_CHI_TXNID_W-1:0]      TXNID,
    input  wire [`C2_CHI_TXNID_W-1:0]      FWDTXNID,
    input  wire [`C2_CHI_OPCODE_W-1:0]     OPCODE,
    input  wire [`C2_CHI_SIZE_W-1:0]       SIZE,
    input  wire [`C2_CHI_ADDR_W-1:0]       ADDR,
    input  wire                            NS,
    input  wire [`C2_CHI_MEMATTR_W-1:0]    MEMATTR,
    input  wire [`C2_CHI_SNPATTR_W-1:0]    SNPATTR,
    input  wire [`C2_CHI_EXPCOMPACK_W-1:0] EXPCOMPACK,
    input  wire [`C2_CHI_TAG_W-1:0]        TAG,
    input  wire [`C2_CHI_LPID_W-1:0]       LPID,
    input  wire [`C2_CHI_MPAM_W-1:0]       MPAM,
    input  wire [`C2_CHI_PCRDTYPE_W-1:0]   PCRDTYPE,
    input  wire [`C2_CHI_ALLOWRETRY_W-1:0] ALLOWRETRY,
    input  wire [`C2_CHI_ORDER_W-1:0]      ORDER,
    input  wire [`C2_CHI_RESP_W-1:0]       RESP,
    input  wire [`C2_CHI_RESPERR_W-1:0]    RESPERR,
    input  wire [`C2_CHI_FWDSTATE_W-1:0]   FWDSTATE,
    input  wire [`C2_CHI_DATASOURCE_W-1:0] DATASOURCE,
    input  wire [`C2_CHI_CBUSY_W-1:0]      CBUSY,
    input  wire [`C2_CHI_DATAID_W-1:0]     DATAID,
    input  wire [`C2_CHI_CCID_W-1:0]       CCID,
    input  wire [`C2_CHI_DBID_W-1:0]       DBID,
    input  wire [`C2_CHI_RETTOSRC_W-1:0]   RETTOSRC,
    input  wire [`C2_CHI_TRACETAG_W-1:0]   TRACETAG,
    input  wire [`C2_CHI_BE_W-1:0]         BE,
    input  wire [`C2_CHI_DATA_W-1:0]       DATA,
    output wire [`C2_REQ_FLIT_W-1:0]       REQ_FLIT,
    output wire [`C2_RSP_FLIT_W-1:0]       RSP_FLIT,
    output wire [`C2_SNP_FLIT_W-1:0]       SNP_FLIT,
    output wire [`C2_DAT_FLIT_W-1:0]       DAT_FLIT
);

    //------------------------------------------------------------------
    // REQ flit : 128 bit
    //------------------------------------------------------------------
    assign REQ_FLIT[`C2_REQ_FIELD_QOS_MSB:`C2_REQ_FIELD_QOS_LSB]               = QOS;
    assign REQ_FLIT[`C2_REQ_FIELD_TGTID_MSB:`C2_REQ_FIELD_TGTID_LSB]           = TGTID;
    assign REQ_FLIT[`C2_REQ_FIELD_SRCID_MSB:`C2_REQ_FIELD_SRCID_LSB]           = SRCID;
    assign REQ_FLIT[`C2_REQ_FIELD_TXNID_MSB:`C2_REQ_FIELD_TXNID_LSB]           = TXNID;
    assign REQ_FLIT[`C2_REQ_FIELD_RETURNID_MSB:`C2_REQ_FIELD_RETURNID_LSB]     = RETURNID;
    assign REQ_FLIT[`C2_REQ_FIELD_OPCODE_MSB:`C2_REQ_FIELD_OPCODE_LSB]         = OPCODE;
    assign REQ_FLIT[`C2_REQ_FIELD_SIZE_MSB:`C2_REQ_FIELD_SIZE_LSB]             = SIZE;
    assign REQ_FLIT[`C2_REQ_FIELD_ADDR_MSB:`C2_REQ_FIELD_ADDR_LSB]             = ADDR;
    assign REQ_FLIT[`C2_REQ_FIELD_NS_MSB:`C2_REQ_FIELD_NS_LSB]                 = NS;
    assign REQ_FLIT[`C2_REQ_FIELD_MEMATTR_MSB:`C2_REQ_FIELD_MEMATTR_LSB]       = MEMATTR;
    assign REQ_FLIT[`C2_REQ_FIELD_SNPATTR_MSB:`C2_REQ_FIELD_SNPATTR_LSB]       = SNPATTR;
    assign REQ_FLIT[`C2_REQ_FIELD_EXPCOMPACK_MSB:`C2_REQ_FIELD_EXPCOMPACK_LSB] = EXPCOMPACK;
    assign REQ_FLIT[`C2_REQ_FIELD_TAG_MSB:`C2_REQ_FIELD_TAG_LSB]               = TAG;
    assign REQ_FLIT[`C2_REQ_FIELD_LPID_MSB:`C2_REQ_FIELD_LPID_LSB]             = LPID;
    assign REQ_FLIT[`C2_REQ_FIELD_MPAM_MSB:`C2_REQ_FIELD_MPAM_LSB]             = MPAM;
    assign REQ_FLIT[`C2_REQ_FIELD_PCRDTYPE_MSB:`C2_REQ_FIELD_PCRDTYPE_LSB]     = PCRDTYPE;
    assign REQ_FLIT[`C2_REQ_FIELD_ALLOWRETRY_MSB:`C2_REQ_FIELD_ALLOWRETRY_LSB] = ALLOWRETRY;
    assign REQ_FLIT[`C2_REQ_FIELD_ORDER_MSB:`C2_REQ_FIELD_ORDER_LSB]           = ORDER;
    assign REQ_FLIT[`C2_REQ_FLIT_SPARE_W-1:0] =
           {CHI_VALID, {(`C2_REQ_FLIT_SPARE_W-1){1'b0}}};

    //------------------------------------------------------------------
    // RSP flit : 64 bit
    //------------------------------------------------------------------
    assign RSP_FLIT[`C2_RSP_FIELD_QOS_MSB:`C2_RSP_FIELD_QOS_LSB]               = QOS;
    assign RSP_FLIT[`C2_RSP_FIELD_TGTID_MSB:`C2_RSP_FIELD_TGTID_LSB]           = TGTID;
    assign RSP_FLIT[`C2_RSP_FIELD_SRCID_MSB:`C2_RSP_FIELD_SRCID_LSB]           = SRCID;
    assign RSP_FLIT[`C2_RSP_FIELD_TXNID_MSB:`C2_RSP_FIELD_TXNID_LSB]           = TXNID;
    assign RSP_FLIT[`C2_RSP_FIELD_OPCODE_MSB:`C2_RSP_FIELD_OPCODE_LSB]         = OPCODE;
    assign RSP_FLIT[`C2_RSP_FIELD_RESPERR_MSB:`C2_RSP_FIELD_RESPERR_LSB]       = RESPERR;
    assign RSP_FLIT[`C2_RSP_FIELD_RESP_MSB:`C2_RSP_FIELD_RESP_LSB]             = RESP;
    assign RSP_FLIT[`C2_RSP_FIELD_FWDSTATE_MSB:`C2_RSP_FIELD_FWDSTATE_LSB]     = FWDSTATE;
    assign RSP_FLIT[`C2_RSP_FIELD_DATASOURCE_MSB:`C2_RSP_FIELD_DATASOURCE_LSB] = DATASOURCE;
    assign RSP_FLIT[`C2_RSP_FIELD_DBID_MSB:`C2_RSP_FIELD_DBID_LSB]             = DBID;
    assign RSP_FLIT[`C2_RSP_FIELD_CBUSY_MSB:`C2_RSP_FIELD_CBUSY_LSB]           = CBUSY;
    assign RSP_FLIT[`C2_RSP_FIELD_TAG_MSB:`C2_RSP_FIELD_TAG_LSB]               = TAG;
    assign RSP_FLIT[`C2_RSP_FIELD_TRACETAG_MSB:`C2_RSP_FIELD_TRACETAG_LSB]     = TRACETAG;
    assign RSP_FLIT[`C2_RSP_FIELD_RETTOSRC_MSB:`C2_RSP_FIELD_RETTOSRC_LSB]     = RETTOSRC;
    assign RSP_FLIT[`C2_RSP_FIELD_CCID_MSB:`C2_RSP_FIELD_CCID_LSB]             = CCID;

    //------------------------------------------------------------------
    // SNP flit : 64 bit
    //------------------------------------------------------------------
    assign SNP_FLIT[`C2_SNP_FIELD_QOS_MSB:`C2_SNP_FIELD_QOS_LSB]           = QOS;
    assign SNP_FLIT[`C2_SNP_FIELD_SRCID_MSB:`C2_SNP_FIELD_SRCID_LSB]       = SRCID;
    assign SNP_FLIT[`C2_SNP_FIELD_TXNID_MSB:`C2_SNP_FIELD_TXNID_LSB]       = TXNID;
    assign SNP_FLIT[`C2_SNP_FIELD_FWDNID_MSB:`C2_SNP_FIELD_FWDNID_LSB]     = FWDNID;
    assign SNP_FLIT[`C2_SNP_FIELD_FWDTXNID_MSB:`C2_SNP_FIELD_FWDTXNID_LSB] = FWDTXNID;
    assign SNP_FLIT[`C2_SNP_FIELD_OPCODE_MSB:`C2_SNP_FIELD_OPCODE_LSB]     = OPCODE;
    assign SNP_FLIT[`C2_SNP_FIELD_ADDR_MSB:`C2_SNP_FIELD_ADDR_LSB]         = ADDR[`C2_SNP_FIELD_ADDR_MSB:`C2_SNP_FIELD_ADDR_LSB];
    assign SNP_FLIT[`C2_SNP_FIELD_NS_MSB:`C2_SNP_FIELD_NS_LSB]             = NS;
    assign SNP_FLIT[`C2_SNP_FIELD_RETTOSRC_MSB:`C2_SNP_FIELD_RETTOSRC_LSB] = RETTOSRC;
    assign SNP_FLIT[`C2_SNP_FIELD_CBUSY_MSB:`C2_SNP_FIELD_CBUSY_LSB]       = CBUSY;

    //------------------------------------------------------------------
    // DAT flit : 320 bit
    //------------------------------------------------------------------
    assign DAT_FLIT[`C2_DAT_FIELD_QOS_MSB:`C2_DAT_FIELD_QOS_LSB]               = QOS;
    assign DAT_FLIT[`C2_DAT_FIELD_OPCODE_MSB:`C2_DAT_FIELD_OPCODE_LSB]         = OPCODE;
    assign DAT_FLIT[`C2_DAT_FIELD_RESP_MSB:`C2_DAT_FIELD_RESP_LSB]             = RESP;
    assign DAT_FLIT[`C2_DAT_FIELD_RESPERR_MSB:`C2_DAT_FIELD_RESPERR_LSB]       = RESPERR;
    assign DAT_FLIT[`C2_DAT_FIELD_DATASOURCE_MSB:`C2_DAT_FIELD_DATASOURCE_LSB] = DATASOURCE;
    assign DAT_FLIT[`C2_DAT_FIELD_CBUSY_MSB:`C2_DAT_FIELD_CBUSY_LSB]           = CBUSY;
    assign DAT_FLIT[`C2_DAT_FIELD_DATAID_MSB:`C2_DAT_FIELD_DATAID_LSB]         = DATAID;
    assign DAT_FLIT[`C2_DAT_FIELD_CCID_MSB:`C2_DAT_FIELD_CCID_LSB]             = CCID;
    assign DAT_FLIT[`C2_DAT_FIELD_DBID_MSB:`C2_DAT_FIELD_DBID_LSB]             = DBID;
    assign DAT_FLIT[`C2_DAT_FIELD_BE_MSB:`C2_DAT_FIELD_BE_LSB]                 = BE;
    assign DAT_FLIT[`C2_DAT_FIELD_DATA_MSB:`C2_DAT_FIELD_DATA_LSB]             = DATA;

endmodule
