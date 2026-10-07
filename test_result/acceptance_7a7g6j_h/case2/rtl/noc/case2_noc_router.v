//==========================================================================
//  case2_noc_router.v
//  一个 mesh router：`C2_PORT_NUM 个端口（u_port[i]）+ 路由 + VC 分配 + xbar
//
//  端口约定：PORT_*_RX 是"路由器从 link 收到的 flit"（进 crossbar），
//            PORT_*_TX 是"路由器向 link 发出的 flit"（crossbar 出口）。
//  端口 i 与 PORT_*_RX/TX 总线的关系：bit 段 [i*FLIT_W +: FLIT_W]。
//
//  Ref: CHI NoC router（route compute + VC alloc + crossbar + output port）。
//==========================================================================
`include "case2_define.v"

module case2_noc_router (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_ROUTE_W-1:0]      ROUTE_MODE,
    input  wire [`C2_PORT_NUM-1:0]     PORT_LINK_UP,
    input  wire [`C2_ROUTER_REQ_W-1:0] PORT_REQ_RX,
    input  wire [`C2_PORT_NUM-1:0]     PORT_REQ_RX_VALID,
    output wire [`C2_PORT_NUM-1:0]     PORT_REQ_RX_READY,
    output wire [`C2_ROUTER_REQ_W-1:0] PORT_REQ_TX,
    output wire [`C2_PORT_NUM-1:0]     PORT_REQ_TX_VALID,
    input  wire [`C2_PORT_NUM-1:0]     PORT_REQ_TX_READY,
    input  wire [`C2_ROUTER_RSP_W-1:0] PORT_RSP_RX,
    input  wire [`C2_PORT_NUM-1:0]     PORT_RSP_RX_VALID,
    output wire [`C2_PORT_NUM-1:0]     PORT_RSP_RX_READY,
    output wire [`C2_ROUTER_RSP_W-1:0] PORT_RSP_TX,
    output wire [`C2_PORT_NUM-1:0]     PORT_RSP_TX_VALID,
    input  wire [`C2_PORT_NUM-1:0]     PORT_RSP_TX_READY,
    input  wire [`C2_ROUTER_SNP_W-1:0] PORT_SNP_RX,
    input  wire [`C2_PORT_NUM-1:0]     PORT_SNP_RX_VALID,
    output wire [`C2_PORT_NUM-1:0]     PORT_SNP_RX_READY,
    output wire [`C2_ROUTER_SNP_W-1:0] PORT_SNP_TX,
    output wire [`C2_PORT_NUM-1:0]     PORT_SNP_TX_VALID,
    input  wire [`C2_PORT_NUM-1:0]     PORT_SNP_TX_READY,
    input  wire [`C2_ROUTER_DAT_W-1:0] PORT_DAT_RX,
    input  wire [`C2_PORT_NUM-1:0]     PORT_DAT_RX_VALID,
    output wire [`C2_PORT_NUM-1:0]     PORT_DAT_RX_READY,
    output wire [`C2_ROUTER_DAT_W-1:0] PORT_DAT_TX,
    output wire [`C2_PORT_NUM-1:0]     PORT_DAT_TX_VALID,
    input  wire [`C2_PORT_NUM-1:0]     PORT_DAT_TX_READY,
    input  wire [`C2_ROUTER_CREDIT_W-1:0] PORT_CREDIT_IN,
    output wire [`C2_ROUTER_CREDIT_W-1:0] PORT_CREDIT_OUT,
    output wire [`C2_ROUTER_ROUTE_W-1:0]  PORT_ROUTE,
    output wire [`C2_PORT_NUM-1:0]        PORT_ACTIVE
);

    parameter X_IDX = 0;
    parameter Y_IDX = 0;

    wire [`C2_PORT_NUM*`C2_VC_NUM-1:0] vc_alloc;
    wire [`C2_PORT_NUM*`C2_VC_NUM-1:0] vc_busy;
    wire [`C2_PORT_NUM-1:0]            credit_ok_vec;
    wire [`C2_PORT_NUM-1:0]            alloc_fail;
    wire [`C2_PORT_NUM-1:0]            req_hold;
    wire [`C2_PORT_AW-1:0]             gnt_idx;
    wire [`C2_PORT_AW-1:0]             route_port;
    wire [`C2_ROUTE_W-1:0]             route_sel;
    wire [`C2_NOC_X_W-1:0]             dst_x;
    wire [`C2_NOC_Y_W-1:0]             dst_y;
    wire                               route_valid;
    wire                               local_req_valid;

    assign local_req_valid = PORT_REQ_RX_VALID[`C2_PORT_LOCAL];

    always @(*) begin
        credit_ok_vec = {`C2_PORT_NUM{1'b0}};
        credit_ok_vec[0] = |PORT_CREDIT_IN[0*`C2_CREDIT_W +: `C2_CREDIT_W];
        credit_ok_vec[1] = |PORT_CREDIT_IN[1*`C2_CREDIT_W +: `C2_CREDIT_W];
        credit_ok_vec[2] = |PORT_CREDIT_IN[2*`C2_CREDIT_W +: `C2_CREDIT_W];
        credit_ok_vec[3] = |PORT_CREDIT_IN[3*`C2_CREDIT_W +: `C2_CREDIT_W];
        credit_ok_vec[4] = |PORT_CREDIT_IN[4*`C2_CREDIT_W +: `C2_CREDIT_W];
    end

    //------------------------------------------------------------------
    // 端口阵列 u_port[0..4]（同一模块 5 个实例）
    //------------------------------------------------------------------
    genvar gp;
    generate
        for (gp = 0; gp < `C2_PORT_NUM; gp = gp + 1) begin : g_port
            case2_noc_router_port #(.PORT_IDX(gp), .X_IDX(X_IDX), .Y_IDX(Y_IDX)) u_port (
                .CLK           (CLK),
                .RST_N         (RST_N),
                .LINK_UP       (PORT_LINK_UP[gp]),
                .REQ_RX        (PORT_REQ_RX[gp*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                .REQ_RX_VALID  (PORT_REQ_RX_VALID[gp]),
                .REQ_RX_READY  (PORT_REQ_RX_READY[gp]),
                .REQ_TX        (PORT_REQ_TX[gp*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                .REQ_TX_VALID  (PORT_REQ_TX_VALID[gp]),
                .REQ_TX_READY  (PORT_REQ_TX_READY[gp]),
                .RSP_RX        (PORT_RSP_RX[gp*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                .RSP_RX_VALID  (PORT_RSP_RX_VALID[gp]),
                .RSP_RX_READY  (PORT_RSP_RX_READY[gp]),
                .RSP_TX        (PORT_RSP_TX[gp*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                .RSP_TX_VALID  (PORT_RSP_TX_VALID[gp]),
                .RSP_TX_READY  (PORT_RSP_TX_READY[gp]),
                .SNP_RX        (PORT_SNP_RX[gp*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                .SNP_RX_VALID  (PORT_SNP_RX_VALID[gp]),
                .SNP_RX_READY  (PORT_SNP_RX_READY[gp]),
                .SNP_TX        (PORT_SNP_TX[gp*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                .SNP_TX_VALID  (PORT_SNP_TX_VALID[gp]),
                .SNP_TX_READY  (PORT_SNP_TX_READY[gp]),
                .DAT_RX        (PORT_DAT_RX[gp*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                .DAT_RX_VALID  (PORT_DAT_RX_VALID[gp]),
                .DAT_RX_READY  (PORT_DAT_RX_READY[gp]),
                .DAT_TX        (PORT_DAT_TX[gp*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                .DAT_TX_VALID  (PORT_DAT_TX_VALID[gp]),
                .DAT_TX_READY  (PORT_DAT_TX_READY[gp]),
                .CREDIT_RET    (PORT_CREDIT_IN[gp*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .CREDIT_ON     (PORT_CREDIT_OUT[gp*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .VC_ALLOC      (vc_alloc[gp*`C2_VC_NUM +: `C2_VC_NUM]),
                .VC_BUSY       (vc_busy[gp*`C2_VC_NUM +: `C2_VC_NUM]),
                .ROUTE_SEL     (route_sel),
                .PORT_ACTIVE   (PORT_ACTIVE[gp])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 路由计算（参数用 #() 覆盖）
    //------------------------------------------------------------------
    case2_noc_route #(.X_IDX(X_IDX), .Y_IDX(Y_IDX)) u_route (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .ADDR       (PORT_REQ_RX[`C2_PORT_LOCAL*`C2_REQ_FLIT_W + `C2_REQ_FIELD_ADDR_LSB +: `C2_CHI_ADDR_W]),
        .TGTID      (PORT_REQ_RX[`C2_PORT_LOCAL*`C2_REQ_FLIT_W + `C2_REQ_FIELD_TGTID_LSB +: `C2_CHI_NODEID_W]),
        .ROUTE_MODE (ROUTE_MODE),
        .ROUTE_REQ  (local_req_valid),
        .PORT_IDX   (`C2_PORT_LOCAL),
        .ROUTE_PORT (route_port),
        .ROUTE_SEL  (route_sel),
        .DST_X      (dst_x),
        .DST_Y      (dst_y),
        .ROUTE_VALID(route_valid)
    );

    //------------------------------------------------------------------
    // VC 分配
    //------------------------------------------------------------------
    case2_noc_alloc u_alloc (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .REQ_VALID  (PORT_REQ_RX_VALID),
        .CREDIT_VEC (credit_ok_vec),
        .VC_FREE    (~vc_busy[0 +: `C2_VC_NUM]),
        .VC_ALLOC   (vc_alloc),
        .ALLOC_FAIL (alloc_fail),
        .GNT_IDX    (gnt_idx),
        .REQ_HOLD   (req_hold)
    );

    //------------------------------------------------------------------
    // crossbar
    //------------------------------------------------------------------
    case2_noc_xbar u_xbar (
        .CLK           (CLK),
        .RST_N         (RST_N),
        .REQ_IN        (PORT_REQ_RX),
        .REQ_IN_VALID  (PORT_REQ_RX_VALID),
        .REQ_IN_READY  (PORT_REQ_RX_READY),
        .REQ_OUT       (PORT_REQ_TX),
        .REQ_OUT_VALID (PORT_REQ_TX_VALID),
        .REQ_OUT_READY (PORT_REQ_TX_READY),
        .RSP_IN        (PORT_RSP_RX),
        .RSP_IN_VALID  (PORT_RSP_RX_VALID),
        .RSP_IN_READY  (PORT_RSP_RX_READY),
        .RSP_OUT       (PORT_RSP_TX),
        .RSP_OUT_VALID (PORT_RSP_TX_VALID),
        .RSP_OUT_READY (PORT_RSP_TX_READY),
        .SNP_IN        (PORT_SNP_RX),
        .SNP_IN_VALID  (PORT_SNP_RX_VALID),
        .SNP_IN_READY  (PORT_SNP_RX_READY),
        .SNP_OUT       (PORT_SNP_TX),
        .SNP_OUT_VALID (PORT_SNP_TX_VALID),
        .SNP_OUT_READY (PORT_SNP_TX_READY),
        .DAT_IN        (PORT_DAT_RX),
        .DAT_IN_VALID  (PORT_DAT_RX_VALID),
        .DAT_IN_READY  (PORT_DAT_RX_READY),
        .DAT_OUT       (PORT_DAT_TX),
        .DAT_OUT_VALID (PORT_DAT_TX_VALID),
        .DAT_OUT_READY (PORT_DAT_TX_READY),
        .CREDIT_REQ    (credit_ok_vec),
        .CREDIT_RSP    (credit_ok_vec),
        .CREDIT_SNP    (credit_ok_vec),
        .CREDIT_DAT    (credit_ok_vec),
        .OUT_BUSY      ()
    );

    //------------------------------------------------------------------
    // 各端口的路由结果（mesh 用它决定本地 DAT 的去向）
    //------------------------------------------------------------------
    genvar gr;
    generate
        for (gr = 0; gr < `C2_PORT_NUM; gr = gr + 1) begin : g_route_idx
            assign PORT_ROUTE[gr*`C2_PORT_AW +: `C2_PORT_AW] =
                   (gr == `C2_PORT_LOCAL) ? route_port : `C2_PORT_LOCAL;
        end
    endgenerate

endmodule
