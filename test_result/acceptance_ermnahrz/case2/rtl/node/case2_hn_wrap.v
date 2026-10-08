//==========================================================================
//  case2_hn_wrap.v
//  HN 节点外壳：CHI home node + CHI<->flit 适配
//
//  Ref: CHI HN-F 节点顶层，挂在 router(0,0) 的北向 link（N lane0）上。
//==========================================================================
`include "case2_define.v"

module case2_hn_wrap (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C2_CHI_NODEID_W-1:0]   NODEID,
    input  wire [`C2_CHI_ADDR_W-1:0]     MEM_BASE,
    input  wire [`C2_REQ_FLIT_W-1:0]     REQ_RX,
    input  wire                          REQ_RX_VALID,
    output wire                          REQ_RX_READY,
    output wire [`C2_SNP_FLIT_W-1:0]     SNP_TX,
    output wire                          SNP_TX_VALID,
    input  wire                          SNP_TX_READY,
    input  wire [`C2_RSP_FLIT_W-1:0]     RSP_RX,
    input  wire                          RSP_RX_VALID,
    output wire                          RSP_RX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0]     DAT_RX,
    input  wire                          DAT_RX_VALID,
    output wire                          DAT_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0]     RSP_TX,
    output wire                          RSP_TX_VALID,
    input  wire                          RSP_TX_READY,
    output wire [`C2_DAT_FLIT_W-1:0]     DAT_TX,
    output wire                          DAT_TX_VALID,
    input  wire                          DAT_TX_READY,
    output wire [`C2_REQ_FLIT_W-1:0]     REQ_TX,
    output wire                          REQ_TX_VALID,
    input  wire                          REQ_TX_READY,
    input  wire [`C2_SNP_FLIT_W-1:0]     SNP_RX,
    input  wire                          SNP_RX_VALID,
    output wire                          SNP_RX_READY,
    output wire [`C2_CREDIT_W-1:0]       CREDIT_ON,
    input  wire [`C2_CREDIT_W-1:0]       CREDIT_RET,
    output wire [`C2_SNP_FILTER_W-1:0]   SNP_VEC,
    output wire                          HIT_ANY,
    output wire                          HN_IDLE,

    output wire [16 -1:0] ec_debug // Moved acceptance
);

    wire [`C2_CHI_ADDR_W-1:0]   hn_addr;
    wire [`C2_CHI_OPCODE_W-1:0] adapter_opcode;
    wire [`C2_CHI_TXNID_W-1:0]  adapter_txnid_out;
    wire [`C2_CHI_TXNID_W-1:0]  adapter_txnid_in;
    wire [`C2_CHI_DATA_W-1:0]   adapter_data;
    wire [`C2_CHI_BE_W-1:0]     adapter_be;
    wire [`C2_CHI_DBID_W-1:0]   adapter_dbid;
    wire [`C2_CHI_RESP_W-1:0]   adapter_resp;
    wire [`C2_CHI_RESPERR_W-1:0] adapter_resperr;
    wire [`C2_REQ_FLIT_W-1:0]   adapter_req_flit;
    wire                        adapter_req_valid;
    wire                        adapter_req_ready;
    wire [`C2_DAT_FLIT_W-1:0]   adapter_dat_flit;
    wire                        adapter_dat_valid;
    wire                        adapter_dat_ready;
    wire                        adapter_chi_valid;
    wire                        adapter_order_err;
    wire                        adapter_chi_last;
    wire [`C2_VC_NUM-1:0]       adapter_vc_free;

    assign HN_IDLE      = ~(REQ_RX_VALID | RSP_TX_VALID | DAT_TX_VALID);
    assign REQ_TX       = adapter_req_flit;
    assign REQ_TX_VALID = adapter_req_valid;
    assign adapter_req_ready = REQ_TX_READY;
    assign adapter_dat_ready = DAT_TX_READY;

    //------------------------------------------------------------------
    // CHI home node
    //------------------------------------------------------------------
    case2_chi_hn u_hn (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .NODEID       (NODEID),
        .REQ_RX       (REQ_RX),
        .REQ_RX_VALID (REQ_RX_VALID),
        .REQ_RX_READY (REQ_RX_READY),
        .SNP_TX       (SNP_TX),
        .SNP_TX_VALID (SNP_TX_VALID),
        .SNP_TX_READY (SNP_TX_READY),
        .RSP_RX       (RSP_RX),
        .RSP_RX_VALID (RSP_RX_VALID),
        .RSP_RX_READY (RSP_RX_READY),
        .DAT_RX       (DAT_RX),
        .DAT_RX_VALID (DAT_RX_VALID),
        .DAT_RX_READY (DAT_RX_READY),
        .RSP_TX       (RSP_TX),
        .RSP_TX_VALID (RSP_TX_VALID),
        .RSP_TX_READY (RSP_TX_READY),
        .DAT_TX       (DAT_TX),
        .DAT_TX_VALID (DAT_TX_VALID),
        .DAT_TX_READY (DAT_TX_READY),
        .SNP_VEC      (SNP_VEC),
        .HIT_ANY      (HIT_ANY),
        .HN_ADDR      (hn_addr),
        .HN_IDLE      (),
    
        .ec_debug(ec_debug) // Moved acceptance
);

    //------------------------------------------------------------------
    // CHI <-> flit 适配（HN 的旁路请求 / 响应回读）
    //------------------------------------------------------------------
    case2_chi_to_noc u_to_noc (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .OPCODE      (adapter_opcode),
        .ADDR        (hn_addr | MEM_BASE),
        .SIZE        ({`C2_CHI_SIZE_W{1'b0}}),
        .QOS         ({`C2_CHI_QOS_W{1'b0}}),
        .MEMATTR     ({`C2_CHI_MEMATTR_W{1'b0}}),
        .SNPATTR     (1'b0),
        .SRCID       (NODEID),
        .TGTID       (NODEID),
        .DATA        (adapter_data),
        .BE          (adapter_be),
        .CHI_VALID   (adapter_chi_valid),
        .CHI_READY   (),
        .TXNID       (adapter_txnid_out),
        .TAG         (),
        .REQ_TX      (adapter_req_flit),
        .REQ_TX_VALID(adapter_req_valid),
        .REQ_TX_READY(adapter_req_ready),
        .DAT_TX      (adapter_dat_flit),
        .DAT_TX_VALID(adapter_dat_valid),
        .DAT_TX_READY(adapter_dat_ready),
        .CREDIT_RET  (CREDIT_RET),
        .CREDIT_ON   (CREDIT_ON),
        .VC_FREE     (adapter_vc_free)
    );

    case2_noc_to_chi u_to_chi (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .RSP_RX      (RSP_RX),
        .RSP_RX_VALID(RSP_RX_VALID),
        .RSP_RX_READY(),
        .DAT_RX      (DAT_RX),
        .DAT_RX_VALID(DAT_RX_VALID),
        .DAT_RX_READY(),
        .OPCODE      (adapter_opcode),
        .TXNID       (adapter_txnid_in),
        .RESP        (adapter_resp),
        .RESPERR     (adapter_resperr),
        .FWDSTATE    (),
        .DATA        (adapter_data),
        .BE          (adapter_be),
        .DBID        (adapter_dbid),
        .DATAID      (),
        .CHI_VALID   (adapter_chi_valid),
        .ORDER_ERR   (adapter_order_err),
        .CHI_LAST    (adapter_chi_last)
    );

    assign SNP_RX_READY = 1'b1;

endmodule
