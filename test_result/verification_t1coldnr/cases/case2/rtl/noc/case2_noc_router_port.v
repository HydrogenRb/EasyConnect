//==========================================================================
//  case2_noc_router_port.v
//  mesh router 的一个端口：per-channel 输入缓冲 + VC + 输出缓冲 + credit
//
//  层次路径形如 u_router[0][0].u_port[4].u_vc[1].u_vc_buf。
//  接收方向（RX = 本模块输入）：link -> u_inbuf[ch] -> VC -> u_outbuf
//  发送方向（TX = 本模块输出）：u_outbuf -> 按 flit kind 解复用回各通道
//
//  Ref: CHI NoC router port（2 个 VC、每通道一个 input buffer）。
//==========================================================================
`include "case2_define.v"

module case2_noc_router_port (
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire                      LINK_UP,
    input  wire [`C2_REQ_FLIT_W-1:0] REQ_RX,
    input  wire                      REQ_RX_VALID,
    output wire                      REQ_RX_READY,
    output wire [`C2_REQ_FLIT_W-1:0] REQ_TX,
    output wire                      REQ_TX_VALID,
    input  wire                      REQ_TX_READY,
    input  wire [`C2_RSP_FLIT_W-1:0] RSP_RX,
    input  wire                      RSP_RX_VALID,
    output wire                      RSP_RX_READY,
    output wire [`C2_RSP_FLIT_W-1:0] RSP_TX,
    output wire                      RSP_TX_VALID,
    input  wire                      RSP_TX_READY,
    input  wire [`C2_SNP_FLIT_W-1:0] SNP_RX,
    input  wire                      SNP_RX_VALID,
    output wire                      SNP_RX_READY,
    output wire [`C2_SNP_FLIT_W-1:0] SNP_TX,
    output wire                      SNP_TX_VALID,
    input  wire                      SNP_TX_READY,
    input  wire [`C2_DAT_FLIT_W-1:0] DAT_RX,
    input  wire                      DAT_RX_VALID,
    output wire                      DAT_RX_READY,
    output wire [`C2_DAT_FLIT_W-1:0] DAT_TX,
    output wire                      DAT_TX_VALID,
    input  wire                      DAT_TX_READY,
    input  wire [`C2_CREDIT_W-1:0]   CREDIT_RET,
    output wire [`C2_CREDIT_W-1:0]   CREDIT_ON,
    input  wire [`C2_VC_NUM-1:0]     VC_ALLOC,
    output wire [`C2_VC_NUM-1:0]     VC_BUSY,
    input  wire [`C2_ROUTE_W-1:0]    ROUTE_SEL,
    output wire                      PORT_ACTIVE
);

    parameter PORT_IDX = `C2_PORT_LOCAL;
    parameter X_IDX    = 0;
    parameter Y_IDX    = 0;

    wire [`C2_KIND_NUM*`C2_FLIT_W-1:0]      ch_bus_rx;
    wire [`C2_KIND_NUM*`C2_FLIT_W-1:0]      ch_bus_tx;
    wire [`C2_KIND_NUM-1:0]                 ch_rx_valid;
    wire [`C2_KIND_NUM-1:0]                 ch_rx_ready;
    wire [`C2_KIND_NUM-1:0]                 ch_tx_valid;
    wire [`C2_KIND_NUM-1:0]                 ch_tx_ready;
    wire [`C2_KIND_NUM*`C2_FLIT_KIND_W-1:0] ch_kind;
    wire [`C2_KIND_NUM-1:0]                 ch_full;
    wire [`C2_KIND_NUM*`C2_BUF_PTR_W-1:0]   ch_wr_ptr;

    wire [`C2_VC_NUM*`C2_FLIT_W-1:0]        vc_bus_out;
    wire [`C2_VC_NUM-1:0]                   vc_out_valid;
    wire [`C2_VC_NUM-1:0]                   vc_out_ready;
    wire [`C2_VC_NUM-1:0]                   vc_empty;
    wire [`C2_VC_NUM*`C2_BUF_PTR_W-1:0]     vc_level;
    wire [`C2_VC_NUM*`C2_CREDIT_W-1:0]      vc_credit_on;

    wire [`C2_FLIT_W-1:0]      out_bus;
    wire [`C2_FLIT_W-1:0]      out_bus_tx;
    wire [`C2_FLIT_W-1:0]      vc_in_flit;
    wire [`C2_FLIT_KIND_W-1:0] out_kind;
    wire                       out_valid;
    wire                       out_empty;
    wire                       out_active;
    wire                       link_valid;
    wire                       link_ready;
    wire                       link_ready_out;
    wire                       link_valid_out;
    wire                       sync_err;
    wire [`C2_BUF_PTR_W-1:0]   link_ptr_in;
    wire [`C2_BUF_PTR_W-1:0]   link_ptr_out;
    wire [`C2_BUF_PTR_W-1:0]   out_rd_ptr;
    wire [`C2_CREDIT_W-1:0]    port_credit;
    wire                       credit_ok;

    reg kind_is_req;
    reg kind_is_rsp;
    reg kind_is_snp;
    reg kind_is_dat;
    reg [`C2_FLIT_W-1:0] vc_in_mux;

    assign PORT_ACTIVE = out_active | (|ch_rx_valid) | (|vc_out_valid);

    //------------------------------------------------------------------
    // 通道 RX flit 搬上 320bit 物理 flit 总线（窄通道补零）
    //------------------------------------------------------------------
    assign ch_bus_rx[`C2_CH_REQ*`C2_FLIT_W +: `C2_FLIT_W] =
           {{`C2_REQ_PAD_W{1'b0}}, REQ_RX};
    assign ch_bus_rx[`C2_CH_RSP*`C2_FLIT_W +: `C2_FLIT_W] =
           {{`C2_RSP_PAD_W{1'b0}}, RSP_RX};
    assign ch_bus_rx[`C2_CH_SNP*`C2_FLIT_W +: `C2_FLIT_W] =
           {{`C2_SNP_PAD_W{1'b0}}, SNP_RX};
    assign ch_bus_rx[`C2_CH_DAT*`C2_FLIT_W +: `C2_FLIT_W] = DAT_RX;

    assign ch_rx_valid[`C2_CH_REQ] = REQ_RX_VALID & LINK_UP;
    assign ch_rx_valid[`C2_CH_RSP] = RSP_RX_VALID & LINK_UP;
    assign ch_rx_valid[`C2_CH_SNP] = SNP_RX_VALID & LINK_UP;
    assign ch_rx_valid[`C2_CH_DAT] = DAT_RX_VALID & LINK_UP;

    assign REQ_RX_READY = ch_rx_ready[`C2_CH_REQ];
    assign RSP_RX_READY = ch_rx_ready[`C2_CH_RSP];
    assign SNP_RX_READY = ch_rx_ready[`C2_CH_SNP];
    assign DAT_RX_READY = ch_rx_ready[`C2_CH_DAT];

    //------------------------------------------------------------------
    // 通道 TX：输出总线按 flit kind 解复用回 4 个通道端口
    //------------------------------------------------------------------
    always @(*) begin
        kind_is_req = (out_kind == `C2_KIND_REQ);
        kind_is_rsp = (out_kind == `C2_KIND_RSP);
        kind_is_snp = (out_kind == `C2_KIND_SNP);
        kind_is_dat = (out_kind == `C2_KIND_DAT);
    end

    assign REQ_TX       = out_bus_tx[`C2_REQ_FLIT_W-1:0];
    assign RSP_TX       = out_bus_tx[`C2_RSP_FLIT_W-1:0];
    assign SNP_TX       = out_bus_tx[`C2_SNP_FLIT_W-1:0];
    assign DAT_TX       = out_bus_tx[`C2_DAT_FLIT_W-1:0];
    assign REQ_TX_VALID = out_valid & kind_is_req;
    assign RSP_TX_VALID = out_valid & kind_is_rsp;
    assign SNP_TX_VALID = out_valid & kind_is_snp;
    assign DAT_TX_VALID = out_valid & kind_is_dat;

    assign ch_tx_ready[`C2_CH_REQ] = REQ_TX_READY;
    assign ch_tx_ready[`C2_CH_RSP] = RSP_TX_READY;
    assign ch_tx_ready[`C2_CH_SNP] = SNP_TX_READY;
    assign ch_tx_ready[`C2_CH_DAT] = DAT_TX_READY;

    assign link_ready_out = ch_tx_ready[`C2_CH_REQ] | ch_tx_ready[`C2_CH_RSP] |
                            ch_tx_ready[`C2_CH_SNP] | ch_tx_ready[`C2_CH_DAT];
    assign link_valid     = |vc_out_valid;
    assign out_bus        = vc_out_valid[0] ? vc_bus_out[0 +: `C2_FLIT_W]
                                            : vc_bus_out[`C2_FLIT_W +: `C2_FLIT_W];
    assign link_ptr_out   = ch_wr_ptr[`C2_BUF_PTR_W-1:0];

    //------------------------------------------------------------------
    // VC 输入选择 + 输出 kind 译码（通道优先级 REQ > RSP > SNP > DAT）
    //------------------------------------------------------------------
    always @(*) begin
        casez (ch_tx_valid)
            4'b1???: vc_in_mux = ch_bus_tx[`C2_CH_REQ*`C2_FLIT_W +: `C2_FLIT_W];
            4'b01??: vc_in_mux = ch_bus_tx[`C2_CH_RSP*`C2_FLIT_W +: `C2_FLIT_W];
            4'b001?: vc_in_mux = ch_bus_tx[`C2_CH_SNP*`C2_FLIT_W +: `C2_FLIT_W];
            4'b0001: vc_in_mux = ch_bus_tx[`C2_CH_DAT*`C2_FLIT_W +: `C2_FLIT_W];
            default: vc_in_mux = {`C2_FLIT_W{1'b0}};
        endcase
    end

    always @(*) begin
        casez (ch_tx_valid)
            4'b1???: out_kind = `C2_KIND_REQ;
            4'b01??: out_kind = `C2_KIND_RSP;
            4'b001?: out_kind = `C2_KIND_SNP;
            4'b0001: out_kind = `C2_KIND_DAT;
            default: out_kind = `C2_KIND_REQ;
        endcase
    end

    assign vc_in_flit = vc_in_mux;

    //------------------------------------------------------------------
    // per-channel 输入缓冲（u_inbuf[0..3]，同一模块 4 个实例）
    //------------------------------------------------------------------
    genvar gc;
    generate
        for (gc = 0; gc < `C2_KIND_NUM; gc = gc + 1) begin : g_ch_inbuf
            case2_noc_input_buf u_inbuf (
                .CLK           (CLK),
                .RST_N         (RST_N),
                .FLIT_IN       (ch_bus_rx[gc*`C2_FLIT_W +: `C2_FLIT_W]),
                .FLIT_IN_VALID (ch_rx_valid[gc]),
                .FLIT_IN_READY (ch_rx_ready[gc]),
                .VC_SEL        (VC_ALLOC),
                .VC_ALLOC_REQ  (VC_ALLOC[gc % `C2_VC_NUM]),
                .FLIT_OUT      (ch_bus_tx[gc*`C2_FLIT_W +: `C2_FLIT_W]),
                .FLIT_OUT_VALID(ch_tx_valid[gc]),
                .FLIT_KIND     (ch_kind[gc*`C2_FLIT_KIND_W +: `C2_FLIT_KIND_W]),
                .BUF_FULL      (ch_full[gc]),
                .WR_PTR        (ch_wr_ptr[gc*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // VC 阵列：u_port[i].u_vc[v].u_vc_buf（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    genvar gv;
    generate
        for (gv = 0; gv < `C2_VC_NUM; gv = gv + 1) begin : g_vc
            case2_noc_vc #(.VC_IDX(gv), .LINK_ID(PORT_IDX)) u_vc (
                .CLK           (CLK),
                .RST_N         (RST_N),
                .FLIT_IN       (vc_in_flit),
                .FLIT_IN_VALID ((|ch_tx_valid) & VC_ALLOC[gv]),
                .FLIT_IN_READY (vc_out_ready[gv]),
                .FLIT_OUT      (vc_bus_out[gv*`C2_FLIT_W +: `C2_FLIT_W]),
                .FLIT_OUT_VALID(vc_out_valid[gv]),
                .FLIT_OUT_READY(link_ready),
                .ROUTE_SEL     (ROUTE_SEL),
                .CREDIT_RET    (CREDIT_RET),
                .CREDIT_ON     (vc_credit_on[gv*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .VC_ALLOC      (VC_ALLOC[gv]),
                .VC_BUSY       (VC_BUSY[gv]),
                .VC_EMPTY      (vc_empty[gv]),
                .VC_LEVEL      (vc_level[gv*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 输出缓冲
    //------------------------------------------------------------------
    case2_noc_output_buf u_outbuf (
        .CLK            (CLK),
        .RST_N          (RST_N),
        .FLIT_IN        (out_bus),
        .FLIT_IN_VALID  (link_valid),
        .VC_SEL         (VC_ALLOC),
        .FLIT_OUT       (out_bus_tx),
        .FLIT_OUT_VALID (out_valid),
        .FLIT_OUT_READY (link_ready),
        .RD_PTR         (out_rd_ptr),
        .OUT_EMPTY      (out_empty),
        .OUT_ACTIVE     (out_active)
    );

    //------------------------------------------------------------------
    // port 级 credit 记账
    //------------------------------------------------------------------
    case2_noc_credit_ctrl u_credit (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .INIT       (~RST_N),
        .SEND       (out_valid),
        .RET        (|CREDIT_RET),
        .RET_NUM    (CREDIT_RET),
        .CREDIT_CNT (port_credit),
        .CREDIT_OK  (credit_ok),
        .CREDIT_ON  (CREDIT_ON)
    );

    //------------------------------------------------------------------
    // link 握手同步级
    //------------------------------------------------------------------
    case2_noc_link_sync u_link_sync (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .LINK_UP   (LINK_UP),
        .KIND      (out_kind),
        .VALID_IN  (out_valid),
        .READY_IN  (link_ready),
        .VALID_OUT (link_valid_out),
        .READY_OUT (link_ready_out),
        .PTR_OUT   (link_ptr_in),
        .PTR_IN    (link_ptr_out),
        .SYNC_ERR  (sync_err)
    );

endmodule
