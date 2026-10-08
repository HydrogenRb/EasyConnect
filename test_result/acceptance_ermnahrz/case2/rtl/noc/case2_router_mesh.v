//==========================================================================
//  case2_router_mesh.v
//  2x2 mesh：4 个 router（u_router[y][x]）+ 8 条边界 link + 4 条内部 link
//
//  端口分组（每组每通道 6 根信号，RX = 输入本模块，TX = 本模块输出）：
//    LOCAL : 4 条 lane（每个 router 的本地端口，接 4 个 RN）
//    N/S/E/W : 各 2 条 lane（mesh 边界 link，N lane0 接 HN）
//    SN    : 1 条 lane（共享 slave node 的 drop ring，扇出到每个 router 的
//            port `C2_LOCAL_PORT）
//  平坦索引：router r 的端口 p 在 PORT_*_RX/TX 总线上占
//            [ (r*`C2_PORT_NUM + p)*FLIT_W +: FLIT_W ]。
//
//  Ref: CHI mesh NoC top（router array + link array + 边界 lane）。
//==========================================================================
`include "case2_define.v"

module case2_router_mesh (
    input  wire                                       CLK,
    input  wire                                       RST_N,
    input  wire [`C2_ROUTE_W-1:0]                     ROUTE_MODE,
    input  wire [(`C2_LOCAL_LANE_NUM*`C2_REQ_FLIT_W)-1:0] LOCAL_REQ_RX,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_REQ_RX_VALID,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_REQ_RX_READY,
    output wire [(`C2_LOCAL_LANE_NUM*`C2_REQ_FLIT_W)-1:0] LOCAL_REQ_TX,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_REQ_TX_VALID,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_REQ_TX_READY,
    input  wire [(`C2_LOCAL_LANE_NUM*`C2_RSP_FLIT_W)-1:0] LOCAL_RSP_RX,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_RSP_RX_VALID,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_RSP_RX_READY,
    output wire [(`C2_LOCAL_LANE_NUM*`C2_RSP_FLIT_W)-1:0] LOCAL_RSP_TX,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_RSP_TX_VALID,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_RSP_TX_READY,
    input  wire [(`C2_LOCAL_LANE_NUM*`C2_SNP_FLIT_W)-1:0] LOCAL_SNP_RX,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_SNP_RX_VALID,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_SNP_RX_READY,
    output wire [(`C2_LOCAL_LANE_NUM*`C2_SNP_FLIT_W)-1:0] LOCAL_SNP_TX,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_SNP_TX_VALID,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_SNP_TX_READY,
    input  wire [(`C2_LOCAL_LANE_NUM*`C2_DAT_FLIT_W)-1:0] LOCAL_DAT_RX,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_DAT_RX_VALID,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_DAT_RX_READY,
    output wire [(`C2_LOCAL_LANE_NUM*`C2_DAT_FLIT_W)-1:0] LOCAL_DAT_TX,
    output wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_DAT_TX_VALID,
    input  wire [`C2_LOCAL_LANE_NUM-1:0]              LOCAL_DAT_TX_READY,
    output wire [(`C2_LOCAL_LANE_NUM*`C2_CREDIT_W)-1:0] LOCAL_CREDIT_ON,
    input  wire [(`C2_LOCAL_LANE_NUM*`C2_CREDIT_W)-1:0] LOCAL_CREDIT_RET,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] N_REQ_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_REQ_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_REQ_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] N_REQ_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_REQ_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_REQ_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] N_RSP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_RSP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_RSP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] N_RSP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_RSP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_RSP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] N_SNP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_SNP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_SNP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] N_SNP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_SNP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_SNP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] N_DAT_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_DAT_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_DAT_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] N_DAT_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              N_DAT_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              N_DAT_TX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] N_CREDIT_ON,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] N_CREDIT_RET,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] S_REQ_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_REQ_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_REQ_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] S_REQ_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_REQ_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_REQ_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] S_RSP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_RSP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_RSP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] S_RSP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_RSP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_RSP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] S_SNP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_SNP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_SNP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] S_SNP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_SNP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_SNP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] S_DAT_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_DAT_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_DAT_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] S_DAT_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              S_DAT_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              S_DAT_TX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] S_CREDIT_ON,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] S_CREDIT_RET,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] E_REQ_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_REQ_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_REQ_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] E_REQ_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_REQ_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_REQ_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] E_RSP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_RSP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_RSP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] E_RSP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_RSP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_RSP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] E_SNP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_SNP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_SNP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] E_SNP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_SNP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_SNP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] E_DAT_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_DAT_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_DAT_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] E_DAT_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              E_DAT_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              E_DAT_TX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] E_CREDIT_ON,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] E_CREDIT_RET,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] W_REQ_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_REQ_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_REQ_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W)-1:0] W_REQ_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_REQ_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_REQ_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] W_RSP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_RSP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_RSP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W)-1:0] W_RSP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_RSP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_RSP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] W_SNP_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_SNP_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_SNP_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W)-1:0] W_SNP_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_SNP_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_SNP_TX_READY,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] W_DAT_RX,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_DAT_RX_VALID,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_DAT_RX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W)-1:0] W_DAT_TX,
    output wire [`C2_BOUND_LANE_NUM-1:0]              W_DAT_TX_VALID,
    input  wire [`C2_BOUND_LANE_NUM-1:0]              W_DAT_TX_READY,
    output wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] W_CREDIT_ON,
    input  wire [(`C2_BOUND_LANE_NUM*`C2_CREDIT_W)-1:0] W_CREDIT_RET,
    input  wire [`C2_SN_LANE_NUM*`C2_REQ_FLIT_W-1:0]  SN_REQ_RX,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_REQ_RX_VALID,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_REQ_RX_READY,
    output wire [`C2_SN_LANE_NUM*`C2_REQ_FLIT_W-1:0]  SN_REQ_TX,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_REQ_TX_VALID,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_REQ_TX_READY,
    input  wire [`C2_SN_LANE_NUM*`C2_RSP_FLIT_W-1:0]  SN_RSP_RX,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_RSP_RX_VALID,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_RSP_RX_READY,
    output wire [`C2_SN_LANE_NUM*`C2_RSP_FLIT_W-1:0]  SN_RSP_TX,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_RSP_TX_VALID,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_RSP_TX_READY,
    input  wire [`C2_SN_LANE_NUM*`C2_SNP_FLIT_W-1:0]  SN_SNP_RX,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_SNP_RX_VALID,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_SNP_RX_READY,
    output wire [`C2_SN_LANE_NUM*`C2_SNP_FLIT_W-1:0]  SN_SNP_TX,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_SNP_TX_VALID,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_SNP_TX_READY,
    input  wire [`C2_SN_LANE_NUM*`C2_DAT_FLIT_W-1:0]  SN_DAT_RX,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_DAT_RX_VALID,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_DAT_RX_READY,
    output wire [`C2_SN_LANE_NUM*`C2_DAT_FLIT_W-1:0]  SN_DAT_TX,
    output wire [`C2_SN_LANE_NUM-1:0]                 SN_DAT_TX_VALID,
    input  wire [`C2_SN_LANE_NUM-1:0]                 SN_DAT_TX_READY,
    output wire [`C2_SN_LANE_NUM*`C2_CREDIT_W-1:0]    SN_CREDIT_ON,
    input  wire [`C2_SN_LANE_NUM*`C2_CREDIT_W-1:0]    SN_CREDIT_RET
);

    //------------------------------------------------------------------
    // router fabric 平坦总线（[router][port] 展开）
    //------------------------------------------------------------------
    wire [`C2_MESH_REQ_W-1:0] rt_req_in;
    wire [`C2_MESH_REQ_W-1:0] rt_req_out;
    wire [`C2_MESH_RSP_W-1:0] rt_rsp_in;
    wire [`C2_MESH_RSP_W-1:0] rt_rsp_out;
    wire [`C2_MESH_SNP_W-1:0] rt_snp_in;
    wire [`C2_MESH_SNP_W-1:0] rt_snp_out;
    wire [`C2_MESH_DAT_W-1:0] rt_dat_in;
    wire [`C2_MESH_DAT_W-1:0] rt_dat_out;

    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_req_in_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_req_in_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_req_out_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_req_out_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_rsp_in_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_rsp_in_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_rsp_out_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_rsp_out_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_snp_in_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_snp_in_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_snp_out_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_snp_out_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_dat_in_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_dat_in_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_dat_out_valid;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_dat_out_ready;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_active;
    wire [`C2_NOC_ROUTER_NUM*`C2_PORT_NUM-1:0] rt_link_up;
    wire [`C2_MESH_CREDIT_W-1:0]               rt_credit_in;
    wire [`C2_MESH_CREDIT_W-1:0]               rt_credit_out;
    wire [`C2_MESH_ROUTE_W-1:0]                rt_route;
    wire [`C2_BOUND_LANE_NUM*`C2_BUF_PTR_W-1:0] bound_ptr;
    wire [`C2_BOUND_LANE_NUM*`C2_BUF_PTR_W-1:0] bound_ptr_out;

    // 内部 link 全部在线（真实设计里由 LINKACTIVE 握手给出）
    assign rt_link_up = {(`C2_NOC_ROUTER_NUM*`C2_PORT_NUM){1'b1}};

    //------------------------------------------------------------------
    // local lane（RN 侧）与 port 4 的连接
    // 端口 4 与共享 SN drop ring 共用：REQ/DAT 收 RN，RSP/SNP 收 SN ring；
    // 发出的 REQ/DAT 按 route 结果决定回 RN 还是送 SN。
    //------------------------------------------------------------------
    wire [`C2_NOC_ROUTER_NUM-1:0] local_dat_sel;
    wire [`C2_NOC_ROUTER_NUM-1:0] sn_req_req;
    wire [`C2_NOC_ROUTER_NUM-1:0] sn_dat_req;
    wire [`C2_PORT_NUM-1:0]       sn_req_gnt_pad;
    wire [`C2_PORT_NUM-1:0]       sn_dat_gnt_pad;
    wire [`C2_NOC_ROUTER_NUM-1:0] sn_req_gnt;
    wire [`C2_NOC_ROUTER_NUM-1:0] sn_dat_gnt;
    wire [`C2_PORT_AW-1:0]        sn_req_idx;
    wire [`C2_PORT_AW-1:0]        sn_dat_idx;
    wire                          sn_req_valid;
    wire                          sn_dat_valid;
    wire                          sn_req_fail;
    wire                          sn_dat_fail;

    reg [`C2_REQ_FLIT_W-1:0] sn_req_mux;
    reg [`C2_SNP_FLIT_W-1:0] sn_snp_mux;
    reg [`C2_DAT_FLIT_W-1:0] sn_dat_mux;

    assign sn_req_gnt = sn_req_gnt_pad[`C2_NOC_ROUTER_NUM-1:0];
    assign sn_dat_gnt = sn_dat_gnt_pad[`C2_NOC_ROUTER_NUM-1:0];

    assign sn_req_req[0] = rt_req_out_valid[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_req_req[1] = rt_req_out_valid[1*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_req_req[2] = rt_req_out_valid[2*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_req_req[3] = rt_req_out_valid[3*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_dat_req[0] = rt_dat_out_valid[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_dat_req[1] = rt_dat_out_valid[1*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_dat_req[2] = rt_dat_out_valid[2*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign sn_dat_req[3] = rt_dat_out_valid[3*`C2_PORT_NUM + `C2_PORT_LOCAL];

    assign local_dat_sel[0] = (rt_route[(0*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_PORT_AW +: `C2_PORT_AW] != `C2_PORT_LOCAL);
    assign local_dat_sel[1] = (rt_route[(1*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_PORT_AW +: `C2_PORT_AW] != `C2_PORT_LOCAL);
    assign local_dat_sel[2] = (rt_route[(2*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_PORT_AW +: `C2_PORT_AW] != `C2_PORT_LOCAL);
    assign local_dat_sel[3] = (rt_route[(3*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_PORT_AW +: `C2_PORT_AW] != `C2_PORT_LOCAL);

    // SN drop ring 汇聚：4 个 router 的 local 端口争用一条 SN link
    case2_noc_arbiter u_sn_req_arb (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ       ({{(`C2_PORT_NUM-`C2_NOC_ROUTER_NUM){1'b0}}, sn_req_req}),
        .CREDIT    ({`C2_PORT_NUM{1'b1}}),
        .HOLD      (~SN_REQ_TX_READY),
        .GNT       (sn_req_gnt_pad),
        .GNT_IDX   (sn_req_idx),
        .GNT_VALID (sn_req_valid),
        .ALLOC_FAIL(sn_req_fail)
    );

    case2_noc_arbiter u_sn_dat_arb (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REQ       ({{(`C2_PORT_NUM-`C2_NOC_ROUTER_NUM){1'b0}}, sn_dat_req}),
        .CREDIT    ({`C2_PORT_NUM{1'b1}}),
        .HOLD      (~SN_DAT_TX_READY),
        .GNT       (sn_dat_gnt_pad),
        .GNT_IDX   (sn_dat_idx),
        .GNT_VALID (sn_dat_valid),
        .ALLOC_FAIL(sn_dat_fail)
    );

    always @(*) begin
        if (sn_req_gnt[0])      sn_req_mux = rt_req_out[(0*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (sn_req_gnt[1]) sn_req_mux = rt_req_out[(1*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (sn_req_gnt[2]) sn_req_mux = rt_req_out[(2*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else if (sn_req_gnt[3]) sn_req_mux = rt_req_out[(3*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
        else                    sn_req_mux = {`C2_REQ_FLIT_W{1'b0}};
    end

    always @(*) begin
        if (sn_req_gnt[0])      sn_snp_mux = rt_snp_out[(0*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (sn_req_gnt[1]) sn_snp_mux = rt_snp_out[(1*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (sn_req_gnt[2]) sn_snp_mux = rt_snp_out[(2*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else if (sn_req_gnt[3]) sn_snp_mux = rt_snp_out[(3*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
        else                    sn_snp_mux = {`C2_SNP_FLIT_W{1'b0}};
    end

    always @(*) begin
        if (sn_dat_gnt[0])      sn_dat_mux = rt_dat_out[(0*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (sn_dat_gnt[1]) sn_dat_mux = rt_dat_out[(1*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (sn_dat_gnt[2]) sn_dat_mux = rt_dat_out[(2*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else if (sn_dat_gnt[3]) sn_dat_mux = rt_dat_out[(3*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
        else                    sn_dat_mux = {`C2_DAT_FLIT_W{1'b0}};
    end

    assign SN_REQ_TX          = sn_req_mux;
    assign SN_REQ_TX_VALID    = sn_req_valid;
    assign SN_SNP_TX          = sn_snp_mux;
    assign SN_SNP_TX_VALID    = sn_req_valid;
    assign SN_DAT_TX          = sn_dat_mux;
    assign SN_DAT_TX_VALID    = sn_dat_valid;
    assign SN_REQ_RX_READY    = rt_req_in_ready[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign SN_RSP_RX_READY    = rt_rsp_in_ready[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign SN_SNP_RX_READY    = rt_snp_in_ready[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign SN_DAT_RX_READY    = rt_dat_in_ready[0*`C2_PORT_NUM + `C2_PORT_LOCAL];
    assign SN_CREDIT_ON       = rt_credit_out[(0*`C2_PORT_NUM + `C2_PORT_LOCAL)*`C2_CREDIT_W +: `C2_CREDIT_W];

    //------------------------------------------------------------------
    // local lane 与 port 4 的逐 lane 连接
    //------------------------------------------------------------------
    genvar gl;
    generate
        for (gl = 0; gl < `C2_LOCAL_LANE_NUM; gl = gl + 1) begin : g_local_lane
            localparam R_IDX  = gl;
            localparam P_IDX  = R_IDX*`C2_PORT_NUM + `C2_PORT_LOCAL;

            assign rt_req_in[P_IDX*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                   LOCAL_REQ_TX[gl*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
            assign LOCAL_REQ_RX[gl*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                   rt_req_out[P_IDX*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
            assign rt_req_in_valid[P_IDX] = LOCAL_REQ_TX_VALID[gl];
            assign rt_req_in_ready[P_IDX] = LOCAL_REQ_TX_READY[gl];
            assign rt_req_out_valid[P_IDX] = LOCAL_REQ_RX_VALID[gl];
            assign LOCAL_REQ_RX_READY[gl] = rt_req_out_ready[P_IDX];

            assign rt_rsp_in[P_IDX*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] = SN_RSP_RX;
            assign LOCAL_RSP_RX[gl*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                   rt_rsp_out[P_IDX*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
            assign rt_rsp_in_valid[P_IDX] = SN_RSP_RX_VALID;
            assign rt_rsp_in_ready[P_IDX] = SN_RSP_TX_READY;
            assign rt_rsp_out_valid[P_IDX] = LOCAL_RSP_RX_VALID[gl];
            assign LOCAL_RSP_RX_READY[gl] = rt_rsp_out_ready[P_IDX];

            assign rt_snp_in[P_IDX*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] = SN_SNP_RX;
            assign LOCAL_SNP_RX[gl*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                   rt_snp_out[P_IDX*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
            assign rt_snp_in_valid[P_IDX] = SN_SNP_RX_VALID;
            assign rt_snp_in_ready[P_IDX] = SN_SNP_TX_READY;
            assign rt_snp_out_valid[P_IDX] = LOCAL_SNP_RX_VALID[gl];
            assign LOCAL_SNP_RX_READY[gl] = rt_snp_out_ready[P_IDX];

            assign rt_dat_in[P_IDX*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                   local_dat_sel[R_IDX] ? SN_DAT_RX
                                        : LOCAL_DAT_TX[gl*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
            assign LOCAL_DAT_RX[gl*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                   local_dat_sel[R_IDX] ? {`C2_DAT_FLIT_W{1'b0}}
                                        : rt_dat_out[P_IDX*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
            assign rt_dat_in_valid[P_IDX] = local_dat_sel[R_IDX] ? SN_DAT_RX_VALID
                                                                 : LOCAL_DAT_TX_VALID[gl];
            assign rt_dat_in_ready[P_IDX] = local_dat_sel[R_IDX] ? SN_DAT_TX_READY
                                                                 : LOCAL_DAT_TX_READY[gl];
            assign rt_dat_out_valid[P_IDX] = LOCAL_DAT_RX_VALID[gl];
            assign LOCAL_DAT_RX_READY[gl] = rt_dat_out_ready[P_IDX];

            assign rt_credit_in[P_IDX*`C2_CREDIT_W +: `C2_CREDIT_W] =
                   LOCAL_CREDIT_RET[gl*`C2_CREDIT_W +: `C2_CREDIT_W] | SN_CREDIT_RET;
            assign LOCAL_CREDIT_ON[gl*`C2_CREDIT_W +: `C2_CREDIT_W] =
                   rt_credit_out[P_IDX*`C2_CREDIT_W +: `C2_CREDIT_W];
        end
    endgenerate

    //------------------------------------------------------------------
    // router 阵列 + link 阵列：u_router[y][x]（嵌套 for-generate）
    //------------------------------------------------------------------
    genvar gy;
    genvar gx;
    generate
        for (gy = 0; gy < `C2_NOC_Y; gy = gy + 1) begin : g_router_row
            for (gx = 0; gx < `C2_NOC_X; gx = gx + 1) begin : g_router_col
                localparam R_IDX  = gy*`C2_NOC_X + gx;
                localparam N_LANE = `C2_LANE_N_BASE + gx;
                localparam S_LANE = `C2_LANE_S_BASE + gx;
                localparam W_LANE = `C2_LANE_W_BASE + gy;
                localparam E_LANE = `C2_LANE_E_BASE + gy;
                localparam N_LINK = `C2_RN_NUM + gx;
                localparam S_LINK = `C2_RN_NUM + `C2_BOUND_LANE_NUM + gx;
                localparam W_LINK = `C2_RN_NUM + 2*`C2_BOUND_LANE_NUM + gy;
                localparam E_LINK = `C2_RN_NUM + 3*`C2_BOUND_LANE_NUM + gy;

                case2_noc_router u_router (
                    .CLK              (CLK),
                    .RST_N            (RST_N),
                    .ROUTE_MODE       (ROUTE_MODE),
                    .PORT_LINK_UP     (rt_link_up[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_REQ_RX      (rt_req_in[R_IDX*`C2_ROUTER_REQ_W +: `C2_ROUTER_REQ_W]),
                    .PORT_REQ_RX_VALID(rt_req_in_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_REQ_RX_READY(rt_req_in_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_REQ_TX      (rt_req_out[R_IDX*`C2_ROUTER_REQ_W +: `C2_ROUTER_REQ_W]),
                    .PORT_REQ_TX_VALID(rt_req_out_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_REQ_TX_READY(rt_req_out_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_RSP_RX      (rt_rsp_in[R_IDX*`C2_ROUTER_RSP_W +: `C2_ROUTER_RSP_W]),
                    .PORT_RSP_RX_VALID(rt_rsp_in_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_RSP_RX_READY(rt_rsp_in_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_RSP_TX      (rt_rsp_out[R_IDX*`C2_ROUTER_RSP_W +: `C2_ROUTER_RSP_W]),
                    .PORT_RSP_TX_VALID(rt_rsp_out_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_RSP_TX_READY(rt_rsp_out_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_SNP_RX      (rt_snp_in[R_IDX*`C2_ROUTER_SNP_W +: `C2_ROUTER_SNP_W]),
                    .PORT_SNP_RX_VALID(rt_snp_in_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_SNP_RX_READY(rt_snp_in_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_SNP_TX      (rt_snp_out[R_IDX*`C2_ROUTER_SNP_W +: `C2_ROUTER_SNP_W]),
                    .PORT_SNP_TX_VALID(rt_snp_out_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_SNP_TX_READY(rt_snp_out_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_DAT_RX      (rt_dat_in[R_IDX*`C2_ROUTER_DAT_W +: `C2_ROUTER_DAT_W]),
                    .PORT_DAT_RX_VALID(rt_dat_in_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_DAT_RX_READY(rt_dat_in_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_DAT_TX      (rt_dat_out[R_IDX*`C2_ROUTER_DAT_W +: `C2_ROUTER_DAT_W]),
                    .PORT_DAT_TX_VALID(rt_dat_out_valid[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_DAT_TX_READY(rt_dat_out_ready[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM]),
                    .PORT_CREDIT_IN   (rt_credit_in[R_IDX*`C2_ROUTER_CREDIT_W +: `C2_ROUTER_CREDIT_W]),
                    .PORT_CREDIT_OUT  (rt_credit_out[R_IDX*`C2_ROUTER_CREDIT_W +: `C2_ROUTER_CREDIT_W]),
                    .PORT_ROUTE       (rt_route[R_IDX*`C2_ROUTER_ROUTE_W +: `C2_ROUTER_ROUTE_W]),
                    .PORT_ACTIVE      (rt_active[R_IDX*`C2_PORT_NUM +: `C2_PORT_NUM])
                );

                //----------------------------------------------
                // 北端口：gy==0 时是 mesh 边界 link（N lane gx）
                //----------------------------------------------
                if (gy == 0) begin : g_bound_n
                    case2_mesh_link u_link_req (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_IN       ({{`C2_REQ_PAD_W{1'b0}}, N_REQ_RX[N_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]}),
                        .FLIT_IN_VALID (N_REQ_RX_VALID[N_LANE]),
                        .FLIT_IN_READY (N_REQ_RX_READY[N_LANE]),
                        .FLIT_OUT      (rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                        .FLIT_OUT_VALID(rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_OUT_READY(rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .CREDIT_ON     (N_CREDIT_RET[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (N_CREDIT_ON[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_rsp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_IN       ({{`C2_RSP_PAD_W{1'b0}}, N_RSP_RX[N_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]}),
                        .FLIT_IN_VALID (N_RSP_RX_VALID[N_LANE]),
                        .FLIT_IN_READY (N_RSP_RX_READY[N_LANE]),
                        .FLIT_OUT      (rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_OUT_READY(rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .CREDIT_ON     (N_CREDIT_RET[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (N_CREDIT_ON[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_snp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_IN       ({{`C2_SNP_PAD_W{1'b0}}, N_SNP_RX[N_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]}),
                        .FLIT_IN_VALID (N_SNP_RX_VALID[N_LANE]),
                        .FLIT_IN_READY (N_SNP_RX_READY[N_LANE]),
                        .FLIT_OUT      (rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_OUT_READY(rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .CREDIT_ON     (N_CREDIT_RET[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (N_CREDIT_ON[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_dat (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_IN       (N_DAT_RX[N_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_IN_VALID (N_DAT_RX_VALID[N_LANE]),
                        .FLIT_IN_READY (N_DAT_RX_READY[N_LANE]),
                        .FLIT_OUT      (rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_OUT_VALID(rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .FLIT_OUT_READY(rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N]),
                        .CREDIT_ON     (N_CREDIT_RET[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (N_CREDIT_ON[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[N_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    assign N_REQ_TX[N_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign N_REQ_TX_VALID[N_LANE] = rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N] = N_REQ_TX_READY[N_LANE];
                    assign N_RSP_TX[N_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign N_RSP_TX_VALID[N_LANE] = rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N] = N_RSP_TX_READY[N_LANE];
                    assign N_SNP_TX[N_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign N_SNP_TX_VALID[N_LANE] = rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N] = N_SNP_TX_READY[N_LANE];
                    assign N_DAT_TX[N_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign N_DAT_TX_VALID[N_LANE] = rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N] = N_DAT_TX_READY[N_LANE];

                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           N_CREDIT_RET[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W];
                    assign N_CREDIT_ON[N_LANE*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end else begin : g_internal_n
                    //------------------------------------------
                    // 内部纵向 link 的上半段：北端口收 (gy-1,gx) 的南端口
                    //------------------------------------------
                    assign rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_req_out_valid[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_req_out_ready[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_rsp_out_valid[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_rsp_out_ready[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_snp_out_valid[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_snp_out_ready[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_dat_out_valid[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_dat_out_ready[((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_N)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(((gy-1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_S)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end

                //----------------------------------------------
                // 南端口：gy==`C2_NOC_Y-1 时是边界 link（S lane gx）
                //----------------------------------------------
                if (gy == `C2_NOC_Y-1) begin : g_bound_s
                    case2_mesh_link u_link_req (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_IN       ({{`C2_REQ_PAD_W{1'b0}}, S_REQ_RX[S_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]}),
                        .FLIT_IN_VALID (S_REQ_RX_VALID[S_LANE]),
                        .FLIT_IN_READY (S_REQ_RX_READY[S_LANE]),
                        .FLIT_OUT      (rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                        .FLIT_OUT_VALID(rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_OUT_READY(rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .CREDIT_ON     (S_CREDIT_RET[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (S_CREDIT_ON[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_rsp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_IN       ({{`C2_RSP_PAD_W{1'b0}}, S_RSP_RX[S_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]}),
                        .FLIT_IN_VALID (S_RSP_RX_VALID[S_LANE]),
                        .FLIT_IN_READY (S_RSP_RX_READY[S_LANE]),
                        .FLIT_OUT      (rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_OUT_READY(rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .CREDIT_ON     (S_CREDIT_RET[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (S_CREDIT_ON[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_snp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_IN       ({{`C2_SNP_PAD_W{1'b0}}, S_SNP_RX[S_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]}),
                        .FLIT_IN_VALID (S_SNP_RX_VALID[S_LANE]),
                        .FLIT_IN_READY (S_SNP_RX_READY[S_LANE]),
                        .FLIT_OUT      (rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_OUT_READY(rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .CREDIT_ON     (S_CREDIT_RET[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (S_CREDIT_ON[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_dat (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_IN       (S_DAT_RX[S_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_IN_VALID (S_DAT_RX_VALID[S_LANE]),
                        .FLIT_IN_READY (S_DAT_RX_READY[S_LANE]),
                        .FLIT_OUT      (rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_OUT_VALID(rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .FLIT_OUT_READY(rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S]),
                        .CREDIT_ON     (S_CREDIT_RET[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (S_CREDIT_ON[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[S_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    assign S_REQ_TX[S_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign S_REQ_TX_VALID[S_LANE] = rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] = S_REQ_TX_READY[S_LANE];
                    assign S_RSP_TX[S_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign S_RSP_TX_VALID[S_LANE] = rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] = S_RSP_TX_READY[S_LANE];
                    assign S_SNP_TX[S_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign S_SNP_TX_VALID[S_LANE] = rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] = S_SNP_TX_READY[S_LANE];
                    assign S_DAT_TX[S_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign S_DAT_TX_VALID[S_LANE] = rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] = S_DAT_TX_READY[S_LANE];

                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           S_CREDIT_RET[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W];
                    assign S_CREDIT_ON[S_LANE*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end else begin : g_internal_s
                    //------------------------------------------
                    // 内部纵向 link 的下半段：南端口发往 (gy+1,gx) 的北端口
                    //------------------------------------------
                    assign rt_req_in[(((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign rt_req_in_valid[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_req_in_ready[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_rsp_in[(((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign rt_rsp_in_valid[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_rsp_in_ready[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_snp_in[(((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign rt_snp_in_valid[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_snp_in_ready[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_dat_in[(((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign rt_dat_in_valid[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N] =
                           rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_S];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_S] =
                           rt_dat_in_ready[((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N];
                    assign rt_credit_in[(((gy+1)*`C2_NOC_X + gx)*`C2_PORT_NUM + `C2_PORT_N)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_S)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end

                //----------------------------------------------
                // 西端口：gx==0 时是边界 link（W lane gy）
                //----------------------------------------------
                if (gx == 0) begin : g_bound_w
                    case2_mesh_link u_link_req (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_IN       ({{`C2_REQ_PAD_W{1'b0}}, W_REQ_RX[W_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]}),
                        .FLIT_IN_VALID (W_REQ_RX_VALID[W_LANE]),
                        .FLIT_IN_READY (W_REQ_RX_READY[W_LANE]),
                        .FLIT_OUT      (rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                        .FLIT_OUT_VALID(rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_OUT_READY(rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .CREDIT_ON     (W_CREDIT_RET[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (W_CREDIT_ON[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_rsp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_IN       ({{`C2_RSP_PAD_W{1'b0}}, W_RSP_RX[W_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]}),
                        .FLIT_IN_VALID (W_RSP_RX_VALID[W_LANE]),
                        .FLIT_IN_READY (W_RSP_RX_READY[W_LANE]),
                        .FLIT_OUT      (rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_OUT_READY(rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .CREDIT_ON     (W_CREDIT_RET[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (W_CREDIT_ON[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_snp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_IN       ({{`C2_SNP_PAD_W{1'b0}}, W_SNP_RX[W_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]}),
                        .FLIT_IN_VALID (W_SNP_RX_VALID[W_LANE]),
                        .FLIT_IN_READY (W_SNP_RX_READY[W_LANE]),
                        .FLIT_OUT      (rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_OUT_READY(rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .CREDIT_ON     (W_CREDIT_RET[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (W_CREDIT_ON[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_dat (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_IN       (W_DAT_RX[W_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_IN_VALID (W_DAT_RX_VALID[W_LANE]),
                        .FLIT_IN_READY (W_DAT_RX_READY[W_LANE]),
                        .FLIT_OUT      (rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_OUT_VALID(rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .FLIT_OUT_READY(rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W]),
                        .CREDIT_ON     (W_CREDIT_RET[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (W_CREDIT_ON[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[W_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    assign W_REQ_TX[W_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign W_REQ_TX_VALID[W_LANE] = rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W] = W_REQ_TX_READY[W_LANE];
                    assign W_RSP_TX[W_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign W_RSP_TX_VALID[W_LANE] = rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W] = W_RSP_TX_READY[W_LANE];
                    assign W_SNP_TX[W_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign W_SNP_TX_VALID[W_LANE] = rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W] = W_SNP_TX_READY[W_LANE];
                    assign W_DAT_TX[W_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign W_DAT_TX_VALID[W_LANE] = rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W] = W_DAT_TX_READY[W_LANE];

                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           W_CREDIT_RET[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W];
                    assign W_CREDIT_ON[W_LANE*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end else begin : g_internal_w
                    //------------------------------------------
                    // 内部横向 link 的右半段：西端口收 (gy,gx-1) 的东端口
                    //------------------------------------------
                    assign rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM*`C2_REQ_FLIT_W + `C2_PORT_E*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_req_out_valid[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_req_out_ready[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM*`C2_RSP_FLIT_W + `C2_PORT_E*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_rsp_out_valid[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_rsp_out_ready[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM*`C2_SNP_FLIT_W + `C2_PORT_E*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_snp_out_valid[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_snp_out_ready[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM*`C2_DAT_FLIT_W + `C2_PORT_E*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_dat_out_valid[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_dat_out_ready[(gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_W)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[((gy*`C2_NOC_X + (gx-1))*`C2_PORT_NUM + `C2_PORT_E)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end

                //----------------------------------------------
                // 东端口：gx==`C2_NOC_X-1 时是边界 link（E lane gy）
                //----------------------------------------------
                if (gx == `C2_NOC_X-1) begin : g_bound_e
                    case2_mesh_link u_link_req (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_IN       ({{`C2_REQ_PAD_W{1'b0}}, E_REQ_RX[E_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]}),
                        .FLIT_IN_VALID (E_REQ_RX_VALID[E_LANE]),
                        .FLIT_IN_READY (E_REQ_RX_READY[E_LANE]),
                        .FLIT_OUT      (rt_req_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W]),
                        .FLIT_OUT_VALID(rt_req_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_OUT_READY(rt_req_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .CREDIT_ON     (E_CREDIT_RET[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (E_CREDIT_ON[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_rsp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_IN       ({{`C2_RSP_PAD_W{1'b0}}, E_RSP_RX[E_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]}),
                        .FLIT_IN_VALID (E_RSP_RX_VALID[E_LANE]),
                        .FLIT_IN_READY (E_RSP_RX_READY[E_LANE]),
                        .FLIT_OUT      (rt_rsp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_rsp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_OUT_READY(rt_rsp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .CREDIT_ON     (E_CREDIT_RET[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (E_CREDIT_ON[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_snp (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_IN       ({{`C2_SNP_PAD_W{1'b0}}, E_SNP_RX[E_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]}),
                        .FLIT_IN_VALID (E_SNP_RX_VALID[E_LANE]),
                        .FLIT_IN_READY (E_SNP_RX_READY[E_LANE]),
                        .FLIT_OUT      (rt_snp_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W]),
                        .FLIT_OUT_VALID(rt_snp_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_OUT_READY(rt_snp_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .CREDIT_ON     (E_CREDIT_RET[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (E_CREDIT_ON[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    case2_mesh_link u_link_dat (
                        .CLK           (CLK),
                        .RST_N         (RST_N),
                        .LINK_UP       (rt_link_up[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_IN       (E_DAT_RX[E_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_IN_VALID (E_DAT_RX_VALID[E_LANE]),
                        .FLIT_IN_READY (E_DAT_RX_READY[E_LANE]),
                        .FLIT_OUT      (rt_dat_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W]),
                        .FLIT_OUT_VALID(rt_dat_in_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .FLIT_OUT_READY(rt_dat_in_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E]),
                        .CREDIT_ON     (E_CREDIT_RET[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .CREDIT_RET    (E_CREDIT_ON[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W]),
                        .PTR_IN        (bound_ptr[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W]),
                        .PTR_OUT       (bound_ptr_out[E_LANE*`C2_BUF_PTR_W +: `C2_BUF_PTR_W])
                    );

                    assign E_REQ_TX[E_LANE*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign E_REQ_TX_VALID[E_LANE] = rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] = E_REQ_TX_READY[E_LANE];
                    assign E_RSP_TX[E_LANE*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign E_RSP_TX_VALID[E_LANE] = rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] = E_RSP_TX_READY[E_LANE];
                    assign E_SNP_TX[E_LANE*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign E_SNP_TX_VALID[E_LANE] = rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] = E_SNP_TX_READY[E_LANE];
                    assign E_DAT_TX[E_LANE*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign E_DAT_TX_VALID[E_LANE] = rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] = E_DAT_TX_READY[E_LANE];

                    assign rt_credit_in[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           E_CREDIT_RET[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W];
                    assign E_CREDIT_ON[E_LANE*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end else begin : g_internal_e
                    //------------------------------------------
                    // 内部横向 link 的左半段：东端口发往 (gy,gx+1) 的西端口
                    //------------------------------------------
                    assign rt_req_in[((gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] =
                           rt_req_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
                    assign rt_req_in_valid[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_req_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_req_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_req_in_ready[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_rsp_in[((gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] =
                           rt_rsp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
                    assign rt_rsp_in_valid[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_rsp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_rsp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_rsp_in_ready[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_snp_in[((gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] =
                           rt_snp_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
                    assign rt_snp_in_valid[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_snp_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_snp_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_snp_in_ready[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_dat_in[((gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] =
                           rt_dat_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
                    assign rt_dat_in_valid[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W] =
                           rt_dat_out_valid[R_IDX*`C2_PORT_NUM + `C2_PORT_E];
                    assign rt_dat_out_ready[R_IDX*`C2_PORT_NUM + `C2_PORT_E] =
                           rt_dat_in_ready[(gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W];
                    assign rt_credit_in[((gy*`C2_NOC_X + (gx+1))*`C2_PORT_NUM + `C2_PORT_W)*`C2_CREDIT_W +: `C2_CREDIT_W] =
                           rt_credit_out[(R_IDX*`C2_PORT_NUM + `C2_PORT_E)*`C2_CREDIT_W +: `C2_CREDIT_W];
                end
            end
        end
    endgenerate

endmodule
