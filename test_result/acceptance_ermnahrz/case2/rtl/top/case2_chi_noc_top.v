//==========================================================================
//  case2_chi_noc_top.v
//  case2 顶层：CHI NoC（2x2 mesh + 4 RN + 1 HN + 8 SN + credit 管理）
//
//  连接关系：
//    u_rn[0..3]  <-> mesh LOCAL lane 0..3   （每个 router 的本地端口）
//    u_hn        <-> mesh N lane 0          （router(0,0) 的北向 link）
//    u_sn        <-> mesh SN drop ring      （扇出到每个 router 的 port 4）
//    其余边界 lane（N1 / S0 / S1 / E0 / E1 / W0 / W1）本样本保留未用：
//    N lane1 显式接零，S/E/W 三组端口不接线（表示未使用的 mesh 边界）。
//    u_credit_mgr <-> mesh 各 lane 的 credit 端口（16 条 link 的预算表）
//
//  Ref: Arm CHI 一致性 NoC 顶层（RN-F / HN-F / SN-F + mesh）。
//==========================================================================
`include "case2_define.v"

module case2_chi_noc_top (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C2_CFG_ADDR_W-1:0]  CFG_ADDR,
    input  wire                       CFG_WR,
    input  wire                       CFG_RD,
    input  wire [`C2_CFG_DATA_W-1:0]  CFG_WDATA,
    output wire [`C2_CFG_DATA_W-1:0]  CFG_RDATA,
    output wire                       NOC_IDLE,
    output wire [`C2_CREDIT_W-1:0]    CREDIT_DBG
);
    wire [16 -1:0] w_ec_debug; // Moved acceptance


    wire                       rst_sync_n;
    wire                       mesh_gclk;
    wire [`C2_CFG_NUM-1:0]     cfg_sel;
    wire [`C2_CFG_SEL_W-1:0]   cfg_idx;
    wire [`C2_CHI_OPCODE_W-1:0] cfg_opcode;
    wire [`C2_CHI_QOS_W-1:0]    cfg_qos;
    wire [`C2_CHI_MEMATTR_W-1:0] cfg_memattr;
    wire [`C2_CHI_SNPATTR_W-1:0] cfg_snpattr;
    wire [`C2_CHI_DATA_W-1:0]   cfg_wdata_ext;
    wire [`C2_CHI_ADDR_W-1:0]   cfg_addr_ext;
    wire [`C2_CHI_BE_W-1:0]     cfg_be;
    wire [`C2_RN_NUM-1:0]       rn_req_start;
    wire [`C2_RN_NUM-1:0]       rn_idle;
    wire                        hn_idle;
    wire                        sn_idle;
    wire                        mesh_active;
    wire                        credit_empty;
    wire                        mgr_active;
    wire [`C2_CFG_DATA_W-1:0]   cfg_rdata_mux;
    wire [`C2_LINK_NUM-1:0]     credit_link_up;
    wire [`C2_LINK_NUM-1:0]     credit_ok;
    wire [`C2_LINK_NUM*`C2_CREDIT_W-1:0] credit_ret_bus;
    wire [`C2_LINK_NUM*`C2_CREDIT_W-1:0] credit_on_bus;

    wire [`C2_CFG_DATA_W-1:0]   cfg_fifo_rd;
    wire                        cfg_fifo_empty;
    wire [`C2_FLIT_W-1:0]       dbg_flit;
    wire [`C2_BUF_PTR_W-1:0]    dbg_wr_ptr;
    wire [`C2_BUF_PTR_W-1:0]    dbg_rd_ptr;
    wire [`C2_BUF_RAM_DW-1:0]   dbg_ram_word;
    wire [`C2_CREDIT_W-1:0]     dbg_ram_credit;
    wire                        dbg_ram_ready;
    wire [`C2_REQ_FLIT_W-1:0]   sn_req_rx_ext;
    wire [`C2_REQ_FLIT_W-1:0]   sn_req_tx_ext;
    wire [`C2_RSP_FLIT_W-1:0]   sn_rsp_rx_ext;
    wire [`C2_RSP_FLIT_W-1:0]   sn_rsp_tx_ext;
    wire [`C2_SNP_FLIT_W-1:0]   sn_snp_rx_ext;
    wire [`C2_SNP_FLIT_W-1:0]   sn_snp_tx_ext;
    wire [`C2_DAT_FLIT_W-1:0]   sn_dat_rx_ext;
    wire [`C2_DAT_FLIT_W-1:0]   sn_dat_tx_ext;
    wire                        sn_req_rx_valid_ext;
    wire                        sn_req_tx_valid_ext;
    wire                        sn_req_rx_ready_ext;
    wire                        sn_req_tx_ready_ext;
    wire                        sn_rsp_rx_valid_ext;
    wire                        sn_rsp_tx_valid_ext;
    wire                        sn_rsp_rx_ready_ext;
    wire                        sn_rsp_tx_ready_ext;
    wire                        sn_snp_rx_valid_ext;
    wire                        sn_snp_tx_valid_ext;
    wire                        sn_snp_rx_ready_ext;
    wire                        sn_snp_tx_ready_ext;
    wire                        sn_dat_rx_valid_ext;
    wire                        sn_dat_tx_valid_ext;
    wire                        sn_dat_rx_ready_ext;
    wire                        sn_dat_tx_ready_ext;

    //------------------------------------------------------------------
    // mesh <-> LOCAL lane 总线（RN 侧，4 条 lane 打包）
    //------------------------------------------------------------------
    wire [`C2_LOCAL_LANE_NUM*`C2_REQ_FLIT_W-1:0] mesh_local_req_tx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_req_tx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_req_tx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_REQ_FLIT_W-1:0] mesh_local_req_rx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_req_rx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_req_rx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_RSP_FLIT_W-1:0] mesh_local_rsp_tx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_rsp_tx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_rsp_tx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_RSP_FLIT_W-1:0] mesh_local_rsp_rx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_rsp_rx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_rsp_rx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_SNP_FLIT_W-1:0] mesh_local_snp_tx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_snp_tx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_snp_tx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_SNP_FLIT_W-1:0] mesh_local_snp_rx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_snp_rx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_snp_rx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_DAT_FLIT_W-1:0] mesh_local_dat_tx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_dat_tx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_dat_tx_ready;
    wire [`C2_LOCAL_LANE_NUM*`C2_DAT_FLIT_W-1:0] mesh_local_dat_rx;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_dat_rx_valid;
    wire [`C2_LOCAL_LANE_NUM-1:0]                mesh_local_dat_rx_ready;

    //------------------------------------------------------------------
    // HN <-> mesh N lane0（boundary lane 打包总线）
    //------------------------------------------------------------------
    wire [`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W-1:0] mesh_n_req_rx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_req_rx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_req_rx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_REQ_FLIT_W-1:0] mesh_n_req_tx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_req_tx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_req_tx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W-1:0] mesh_n_rsp_rx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_rsp_rx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_rsp_rx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_RSP_FLIT_W-1:0] mesh_n_rsp_tx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_rsp_tx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_rsp_tx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W-1:0] mesh_n_snp_rx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_snp_rx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_snp_rx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_SNP_FLIT_W-1:0] mesh_n_snp_tx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_snp_tx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_snp_tx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W-1:0] mesh_n_dat_rx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_dat_rx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_dat_rx_ready;
    wire [`C2_BOUND_LANE_NUM*`C2_DAT_FLIT_W-1:0] mesh_n_dat_tx;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_dat_tx_valid;
    wire [`C2_BOUND_LANE_NUM-1:0]                mesh_n_dat_tx_ready;

    //------------------------------------------------------------------
    // 复位同步 + mesh 时钟门控（位置连接风格）
    //------------------------------------------------------------------
    case2_sync_2ff u_rst_sync (CLK, RST_N, RST_N, rst_sync_n);
    case2_clk_gate u_mesh_cg (CLK, RST_N, mesh_active, mesh_gclk);

    //------------------------------------------------------------------
    // CFG 译码
    //------------------------------------------------------------------
    assign cfg_idx       = CFG_ADDR[`C2_CFG_ADDR_MSB:`C2_CFG_ADDR_MSB-`C2_CFG_SEL_W+1];
    assign cfg_sel       = ({{(`C2_CFG_NUM-1){1'b0}}, 1'b1} << cfg_idx);
    assign cfg_opcode    = CFG_WDATA[`C2_CHI_OPCODE_W-1:0];
    assign cfg_qos       = CFG_WDATA[`C2_CHI_OPCODE_W +: `C2_CHI_QOS_W];
    assign cfg_memattr   = CFG_WDATA[`C2_CHI_OPCODE_W+`C2_CHI_QOS_W +: `C2_CHI_MEMATTR_W];
    assign cfg_snpattr   = CFG_WDATA[`C2_CHI_OPCODE_W+`C2_CHI_QOS_W+`C2_CHI_MEMATTR_W];
    assign cfg_be        = {{(`C2_CHI_BE_W-`C2_CFG_DATA_W){1'b0}}, CFG_WDATA};
    assign cfg_wdata_ext = {{(`C2_CHI_DATA_W-`C2_CFG_DATA_W){1'b0}}, CFG_WDATA};
    assign cfg_addr_ext  = {CFG_ADDR, {(`C2_CHI_ADDR_W-`C2_CFG_ADDR_W){1'b0}}};
    assign rn_req_start  = cfg_sel[`C2_RN_NUM-1:0] & {`C2_RN_NUM{CFG_WR}};

    assign CFG_RDATA = cfg_rdata_mux;
    assign NOC_IDLE  = (&rn_idle) & hn_idle & sn_idle & (~mesh_active);

    always @(*) begin
        if (cfg_sel[0]) begin
            cfg_rdata_mux = {{(`C2_CFG_DATA_W-`C2_CREDIT_W){1'b0}}, CREDIT_DBG};
        end else if (cfg_sel[1]) begin
            cfg_rdata_mux = {{(`C2_CFG_DATA_W-`C2_LINK_NUM){1'b0}}, credit_ok};
        end else if (cfg_sel[2]) begin
            cfg_rdata_mux = {{(`C2_CFG_DATA_W-`C2_RN_NUM){1'b0}}, rn_idle};
        end else if (cfg_sel[3]) begin
            cfg_rdata_mux = cfg_fifo_empty ? {`C2_CFG_DATA_W{1'b0}} : cfg_fifo_rd;
        end else if (cfg_sel[4]) begin
            cfg_rdata_mux = dbg_ram_word;
        end else begin
            cfg_rdata_mux = {`C2_CFG_DATA_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 4 个 RN：mesh LOCAL lane r（u_rn[r]，同一模块 4 个不同实例名）
    //------------------------------------------------------------------
    genvar gr;
    generate
        for (gr = 0; gr < `C2_RN_NUM; gr = gr + 1) begin : g_rn
            wire [`C2_REQ_FLIT_W-1:0] rn_req_tx;
            wire                      rn_req_tx_valid;
            wire                      rn_req_tx_ready;
            wire [`C2_REQ_FLIT_W-1:0] rn_req_rx;
            wire                      rn_req_rx_valid;
            wire                      rn_req_rx_ready;
            wire [`C2_RSP_FLIT_W-1:0] rn_rsp_rx;
            wire                      rn_rsp_rx_valid;
            wire                      rn_rsp_rx_ready;
            wire [`C2_RSP_FLIT_W-1:0] rn_rsp_tx;
            wire                      rn_rsp_tx_valid;
            wire                      rn_rsp_tx_ready;
            wire [`C2_SNP_FLIT_W-1:0] rn_snp_rx;
            wire                      rn_snp_rx_valid;
            wire                      rn_snp_rx_ready;
            wire [`C2_SNP_FLIT_W-1:0] rn_snp_tx;
            wire                      rn_snp_tx_valid;
            wire                      rn_snp_tx_ready;
            wire [`C2_DAT_FLIT_W-1:0] rn_dat_rx;
            wire                      rn_dat_rx_valid;
            wire                      rn_dat_rx_ready;
            wire [`C2_DAT_FLIT_W-1:0] rn_dat_tx;
            wire                      rn_dat_tx_valid;
            wire                      rn_dat_tx_ready;
            wire                      rn_wdata_ready;
            wire [`C2_CHI_RESP_W-1:0] rn_resp;
            wire [`C2_CHI_RESPERR_W-1:0] rn_resperr;
            wire [`C2_CHI_TXNID_W-1:0] rn_txnid;

            case2_rn_wrap u_rn (
                .CLK            (CLK),
                .RST_N          (rst_sync_n),
                .NODEID         (`C2_RN_ID_BASE + gr),
                .HOMEID         (`C2_HN_ID_BASE),
                .REQ_START      (rn_req_start[gr]),
                .REQ_OPCODE     (cfg_opcode),
                .REQ_ADDR       (cfg_addr_ext),
                .REQ_SIZE       (CFG_ADDR[`C2_CHI_SIZE_W-1:0]),
                .REQ_QOS        (cfg_qos),
                .REQ_MEMATTR    (cfg_memattr),
                .REQ_SNPATTR    (cfg_snpattr),
                .WDATA          (cfg_wdata_ext),
                .WBE            (cfg_be),
                .WDATA_VALID    (CFG_WR & cfg_sel[gr]),
                .WDATA_READY    (rn_wdata_ready),
                .REQ_TX         (rn_req_tx),
                .REQ_TX_VALID   (rn_req_tx_valid),
                .REQ_TX_READY   (rn_req_tx_ready),
                .RSP_RX         (rn_rsp_rx),
                .RSP_RX_VALID   (rn_rsp_rx_valid),
                .RSP_RX_READY   (rn_rsp_rx_ready),
                .SNP_RX         (rn_snp_rx),
                .SNP_RX_VALID   (rn_snp_rx_valid),
                .SNP_RX_READY   (rn_snp_rx_ready),
                .DAT_RX         (rn_dat_rx),
                .DAT_RX_VALID   (rn_dat_rx_valid),
                .DAT_RX_READY   (rn_dat_rx_ready),
                .RSP_TX         (rn_rsp_tx),
                .RSP_TX_VALID   (rn_rsp_tx_valid),
                .RSP_TX_READY   (rn_rsp_tx_ready),
                .DAT_TX         (rn_dat_tx),
                .DAT_TX_VALID   (rn_dat_tx_valid),
                .DAT_TX_READY   (rn_dat_tx_ready),
                .CREDIT_ON      (credit_ret_bus[gr*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .CREDIT_RET     (credit_on_bus[gr*`C2_CREDIT_W +: `C2_CREDIT_W]),
                .RESP           (rn_resp),
                .RESPERR        (rn_resperr),
                .TXNID          (rn_txnid),
                .RN_IDLE        (rn_idle[gr]),
            
        .ec_debug_in(w_ec_debug) // Moved acceptance
);

            // REQ：RN -> mesh（mesh 的 LOCAL_REQ_RX 是输入）
            assign mesh_local_req_rx[gr*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W] = rn_req_tx;
            assign mesh_local_req_rx_valid[gr]  = rn_req_tx_valid;
            assign rn_req_tx_ready              = mesh_local_req_rx_ready[gr];
            // REQ：mesh -> RN（mesh 的 LOCAL_REQ_TX 是输出）
            assign rn_req_rx                    = mesh_local_req_tx[gr*`C2_REQ_FLIT_W +: `C2_REQ_FLIT_W];
            assign rn_req_rx_valid              = mesh_local_req_tx_valid[gr];
            assign mesh_local_req_tx_ready[gr]  = rn_req_rx_ready;
            // RSP：RN（snoop 响应）-> mesh
            assign mesh_local_rsp_rx[gr*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W] = rn_rsp_tx;
            assign mesh_local_rsp_rx_valid[gr]  = rn_rsp_tx_valid;
            assign rn_rsp_tx_ready              = mesh_local_rsp_rx_ready[gr];
            // RSP：mesh -> RN
            assign rn_rsp_rx                    = mesh_local_rsp_tx[gr*`C2_RSP_FLIT_W +: `C2_RSP_FLIT_W];
            assign rn_rsp_rx_valid              = mesh_local_rsp_tx_valid[gr];
            assign mesh_local_rsp_tx_ready[gr]  = rn_rsp_rx_ready;
            // SNP：mesh -> RN
            assign rn_snp_rx                    = mesh_local_snp_tx[gr*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W];
            assign rn_snp_rx_valid              = mesh_local_snp_tx_valid[gr];
            assign mesh_local_snp_tx_ready[gr]  = rn_snp_rx_ready;
            // SNP：RN -> mesh
            assign mesh_local_snp_rx[gr*`C2_SNP_FLIT_W +: `C2_SNP_FLIT_W] = rn_snp_tx;
            assign mesh_local_snp_rx_valid[gr]  = rn_snp_tx_valid;
            assign rn_snp_tx_ready              = mesh_local_snp_rx_ready[gr];
            // DAT：RN（写数据）-> mesh
            assign mesh_local_dat_rx[gr*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W] = rn_dat_tx;
            assign mesh_local_dat_rx_valid[gr]  = rn_dat_tx_valid;
            assign rn_dat_tx_ready              = mesh_local_dat_rx_ready[gr];
            // DAT：mesh（读数据）-> RN
            assign rn_dat_rx                    = mesh_local_dat_tx[gr*`C2_DAT_FLIT_W +: `C2_DAT_FLIT_W];
            assign rn_dat_rx_valid              = mesh_local_dat_tx_valid[gr];
            assign mesh_local_dat_tx_ready[gr]  = rn_dat_rx_ready;
        end
    endgenerate

    //------------------------------------------------------------------
    // mesh 例化（LOCAL / N / SN 三组接线；S/E/W 保留未用）
    //------------------------------------------------------------------
    case2_router_mesh u_mesh (
        .CLK               (mesh_gclk),
        .RST_N             (rst_sync_n),
        .ROUTE_MODE        (`C2_ROUTE_X_FIRST),
        .LOCAL_REQ_RX      (mesh_local_req_rx),
        .LOCAL_REQ_RX_VALID(mesh_local_req_rx_valid),
        .LOCAL_REQ_RX_READY(mesh_local_req_rx_ready),
        .LOCAL_REQ_TX      (mesh_local_req_tx),
        .LOCAL_REQ_TX_VALID(mesh_local_req_tx_valid),
        .LOCAL_REQ_TX_READY(mesh_local_req_tx_ready),
        .LOCAL_RSP_RX      (mesh_local_rsp_rx),
        .LOCAL_RSP_RX_VALID(mesh_local_rsp_rx_valid),
        .LOCAL_RSP_RX_READY(mesh_local_rsp_rx_ready),
        .LOCAL_RSP_TX      (mesh_local_rsp_tx),
        .LOCAL_RSP_TX_VALID(mesh_local_rsp_tx_valid),
        .LOCAL_RSP_TX_READY(mesh_local_rsp_tx_ready),
        .LOCAL_SNP_RX      (mesh_local_snp_rx),
        .LOCAL_SNP_RX_VALID(mesh_local_snp_rx_valid),
        .LOCAL_SNP_RX_READY(mesh_local_snp_rx_ready),
        .LOCAL_SNP_TX      (mesh_local_snp_tx),
        .LOCAL_SNP_TX_VALID(mesh_local_snp_tx_valid),
        .LOCAL_SNP_TX_READY(mesh_local_snp_tx_ready),
        .LOCAL_DAT_RX      (mesh_local_dat_rx),
        .LOCAL_DAT_RX_VALID(mesh_local_dat_rx_valid),
        .LOCAL_DAT_RX_READY(mesh_local_dat_rx_ready),
        .LOCAL_DAT_TX      (mesh_local_dat_tx),
        .LOCAL_DAT_TX_VALID(mesh_local_dat_tx_valid),
        .LOCAL_DAT_TX_READY(mesh_local_dat_tx_ready),
        .LOCAL_CREDIT_ON   (credit_ret_bus[0 +: `C2_LOCAL_LANE_NUM*`C2_CREDIT_W]),
        .LOCAL_CREDIT_RET  (credit_on_bus[0 +: `C2_LOCAL_LANE_NUM*`C2_CREDIT_W]),
        .N_REQ_RX          (mesh_n_req_rx),
        .N_REQ_RX_VALID    (mesh_n_req_rx_valid),
        .N_REQ_RX_READY    (mesh_n_req_rx_ready),
        .N_REQ_TX          (mesh_n_req_tx),
        .N_REQ_TX_VALID    (mesh_n_req_tx_valid),
        .N_REQ_TX_READY    (mesh_n_req_tx_ready),
        .N_RSP_RX          (mesh_n_rsp_rx),
        .N_RSP_RX_VALID    (mesh_n_rsp_rx_valid),
        .N_RSP_RX_READY    (mesh_n_rsp_rx_ready),
        .N_RSP_TX          (mesh_n_rsp_tx),
        .N_RSP_TX_VALID    (mesh_n_rsp_tx_valid),
        .N_RSP_TX_READY    (mesh_n_rsp_tx_ready),
        .N_SNP_RX          (mesh_n_snp_rx),
        .N_SNP_RX_VALID    (mesh_n_snp_rx_valid),
        .N_SNP_RX_READY    (mesh_n_snp_rx_ready),
        .N_SNP_TX          (mesh_n_snp_tx),
        .N_SNP_TX_VALID    (mesh_n_snp_tx_valid),
        .N_SNP_TX_READY    (mesh_n_snp_tx_ready),
        .N_DAT_RX          (mesh_n_dat_rx),
        .N_DAT_RX_VALID    (mesh_n_dat_rx_valid),
        .N_DAT_RX_READY    (mesh_n_dat_rx_ready),
        .N_DAT_TX          (mesh_n_dat_tx),
        .N_DAT_TX_VALID    (mesh_n_dat_tx_valid),
        .N_DAT_TX_READY    (mesh_n_dat_tx_ready),
        .N_CREDIT_ON       (credit_ret_bus[`C2_RN_NUM*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .N_CREDIT_RET      (credit_on_bus[`C2_RN_NUM*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .S_REQ_RX          (),
        .S_REQ_RX_VALID    (),
        .S_REQ_RX_READY    (),
        .S_REQ_TX          (),
        .S_REQ_TX_VALID    (),
        .S_REQ_TX_READY    (1'b0),
        .S_RSP_RX          (),
        .S_RSP_RX_VALID    (),
        .S_RSP_RX_READY    (),
        .S_RSP_TX          (),
        .S_RSP_TX_VALID    (),
        .S_RSP_TX_READY    (1'b0),
        .S_SNP_RX          (),
        .S_SNP_RX_VALID    (),
        .S_SNP_RX_READY    (),
        .S_SNP_TX          (),
        .S_SNP_TX_VALID    (),
        .S_SNP_TX_READY    (1'b0),
        .S_DAT_RX          (),
        .S_DAT_RX_VALID    (),
        .S_DAT_RX_READY    (),
        .S_DAT_TX          (),
        .S_DAT_TX_VALID    (),
        .S_DAT_TX_READY    (1'b0),
        .S_CREDIT_ON       (credit_ret_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .S_CREDIT_RET      (credit_on_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .E_REQ_RX          (),
        .E_REQ_RX_VALID    (),
        .E_REQ_RX_READY    (),
        .E_REQ_TX          (),
        .E_REQ_TX_VALID    (),
        .E_REQ_TX_READY    (1'b0),
        .E_RSP_RX          (),
        .E_RSP_RX_VALID    (),
        .E_RSP_RX_READY    (),
        .E_RSP_TX          (),
        .E_RSP_TX_VALID    (),
        .E_RSP_TX_READY    (1'b0),
        .E_SNP_RX          (),
        .E_SNP_RX_VALID    (),
        .E_SNP_RX_READY    (),
        .E_SNP_TX          (),
        .E_SNP_TX_VALID    (),
        .E_SNP_TX_READY    (1'b0),
        .E_DAT_RX          (),
        .E_DAT_RX_VALID    (),
        .E_DAT_RX_READY    (),
        .E_DAT_TX          (),
        .E_DAT_TX_VALID    (),
        .E_DAT_TX_READY    (1'b0),
        .E_CREDIT_ON       (credit_ret_bus[(`C2_RN_NUM+3*`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .E_CREDIT_RET      (credit_on_bus[(`C2_RN_NUM+3*`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .W_REQ_RX          (),
        .W_REQ_RX_VALID    (),
        .W_REQ_RX_READY    (),
        .W_REQ_TX          (),
        .W_REQ_TX_VALID    (),
        .W_REQ_TX_READY    (1'b0),
        .W_RSP_RX          (),
        .W_RSP_RX_VALID    (),
        .W_RSP_RX_READY    (),
        .W_RSP_TX          (),
        .W_RSP_TX_VALID    (),
        .W_RSP_TX_READY    (1'b0),
        .W_SNP_RX          (),
        .W_SNP_RX_VALID    (),
        .W_SNP_RX_READY    (),
        .W_SNP_TX          (),
        .W_SNP_TX_VALID    (),
        .W_SNP_TX_READY    (1'b0),
        .W_DAT_RX          (),
        .W_DAT_RX_VALID    (),
        .W_DAT_RX_READY    (),
        .W_DAT_TX          (),
        .W_DAT_TX_VALID    (),
        .W_DAT_TX_READY    (1'b0),
        .W_CREDIT_ON       (credit_ret_bus[(`C2_RN_NUM+2*`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .W_CREDIT_RET      (credit_on_bus[(`C2_RN_NUM+2*`C2_BOUND_LANE_NUM)*`C2_CREDIT_W +: `C2_BOUND_LANE_NUM*`C2_CREDIT_W]),
        .SN_REQ_RX         (sn_req_tx_ext),
        .SN_REQ_RX_VALID   (sn_req_tx_valid_ext),
        .SN_REQ_RX_READY   (sn_req_tx_ready_ext),
        .SN_REQ_TX         (sn_req_rx_ext),
        .SN_REQ_TX_VALID   (sn_req_rx_valid_ext),
        .SN_REQ_TX_READY   (sn_req_rx_ready_ext),
        .SN_RSP_RX         (sn_rsp_rx_ext),
        .SN_RSP_RX_VALID   (sn_rsp_rx_valid_ext),
        .SN_RSP_RX_READY   (sn_rsp_rx_ready_ext),
        .SN_RSP_TX         (sn_rsp_tx_ext),
        .SN_RSP_TX_VALID   (sn_rsp_tx_valid_ext),
        .SN_RSP_TX_READY   (sn_rsp_tx_ready_ext),
        .SN_SNP_RX         (sn_snp_rx_ext),
        .SN_SNP_RX_VALID   (sn_snp_rx_valid_ext),
        .SN_SNP_RX_READY   (sn_snp_rx_ready_ext),
        .SN_SNP_TX         (sn_snp_tx_ext),
        .SN_SNP_TX_VALID   (sn_snp_tx_valid_ext),
        .SN_SNP_TX_READY   (sn_snp_tx_ready_ext),
        .SN_DAT_RX         (sn_dat_rx_ext),
        .SN_DAT_RX_VALID   (sn_dat_rx_valid_ext),
        .SN_DAT_RX_READY   (sn_dat_rx_ready_ext),
        .SN_DAT_TX         (sn_dat_tx_ext),
        .SN_DAT_TX_VALID   (sn_dat_tx_valid_ext),
        .SN_DAT_TX_READY   (sn_dat_tx_ready_ext),
        .SN_CREDIT_ON      (credit_ret_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM*`C2_BOUND_GROUP_NUM)*`C2_CREDIT_W +: `C2_CREDIT_W]),
        .SN_CREDIT_RET     (credit_on_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM*`C2_BOUND_GROUP_NUM)*`C2_CREDIT_W +: `C2_CREDIT_W])
    );

    //------------------------------------------------------------------
    // HN（N lane0）：HN 与 mesh 的 4 个通道对接
    //------------------------------------------------------------------
    case2_hn_wrap u_hn (
        .CLK           (CLK),
        .RST_N         (rst_sync_n),
        .NODEID        (`C2_HN_ID_BASE),
        .MEM_BASE      (`C2_ADDR_MEM_BASE),
        .REQ_RX        (mesh_n_req_tx[0 +: `C2_REQ_FLIT_W]),
        .REQ_RX_VALID  (mesh_n_req_tx_valid[0]),
        .REQ_RX_READY  (mesh_n_req_tx_ready[0]),
        .SNP_TX        (mesh_n_snp_rx[0 +: `C2_SNP_FLIT_W]),
        .SNP_TX_VALID  (mesh_n_snp_rx_valid[0]),
        .SNP_TX_READY  (mesh_n_snp_rx_ready[0]),
        .RSP_RX        (mesh_n_rsp_tx[0 +: `C2_RSP_FLIT_W]),
        .RSP_RX_VALID  (mesh_n_rsp_tx_valid[0]),
        .RSP_RX_READY  (mesh_n_rsp_tx_ready[0]),
        .DAT_RX        (mesh_n_dat_tx[0 +: `C2_DAT_FLIT_W]),
        .DAT_RX_VALID  (mesh_n_dat_tx_valid[0]),
        .DAT_RX_READY  (mesh_n_dat_tx_ready[0]),
        .RSP_TX        (mesh_n_rsp_rx[0 +: `C2_RSP_FLIT_W]),
        .RSP_TX_VALID  (mesh_n_rsp_rx_valid[0]),
        .RSP_TX_READY  (mesh_n_rsp_rx_ready[0]),
        .DAT_TX        (mesh_n_dat_rx[0 +: `C2_DAT_FLIT_W]),
        .DAT_TX_VALID  (mesh_n_dat_rx_valid[0]),
        .DAT_TX_READY  (mesh_n_dat_rx_ready[0]),
        .REQ_TX        (mesh_n_req_rx[0 +: `C2_REQ_FLIT_W]),
        .REQ_TX_VALID  (mesh_n_req_rx_valid[0]),
        .REQ_TX_READY  (mesh_n_req_rx_ready[0]),
        .SNP_RX        (mesh_n_snp_tx[0 +: `C2_SNP_FLIT_W]),
        .SNP_RX_VALID  (mesh_n_snp_tx_valid[0]),
        .SNP_RX_READY  (mesh_n_snp_tx_ready[0]),
        .CREDIT_ON     (credit_ret_bus[`C2_RN_NUM*`C2_CREDIT_W +: `C2_CREDIT_W]),
        .CREDIT_RET    (credit_on_bus[`C2_RN_NUM*`C2_CREDIT_W +: `C2_CREDIT_W]),
        .SNP_VEC       (),
        .HIT_ANY       (),
        .HN_IDLE       (hn_idle),
    
        .ec_debug(w_ec_debug) // Moved acceptance
);

    // N lane1 未使用：显式接零 / 置 ready
    assign mesh_n_rsp_rx_valid[1] = 1'b0;
    assign mesh_n_snp_rx_valid[1] = 1'b0;
    assign mesh_n_dat_rx_valid[1] = 1'b0;
    assign mesh_n_req_tx_ready[1] = 1'b1;
    assign mesh_n_rsp_tx_ready[1] = 1'b1;
    assign mesh_n_snp_tx_ready[1] = 1'b1;
    assign mesh_n_dat_tx_ready[1] = 1'b1;

    //------------------------------------------------------------------
    // SN（共享 drop ring，扇出到每个 router 的 port `C2_LOCAL_PORT）
    //------------------------------------------------------------------
    case2_sn_wrap u_sn (
        .CLK           (CLK),
        .RST_N         (rst_sync_n),
        .NODEID        (`C2_SN_ID_BASE),
        .REQ_RX        (sn_req_rx_ext),
        .REQ_RX_VALID  (sn_req_rx_valid_ext),
        .REQ_RX_READY  (sn_req_rx_ready_ext),
        .REQ_TX        (sn_req_tx_ext),
        .REQ_TX_VALID  (sn_req_tx_valid_ext),
        .REQ_TX_READY  (sn_req_tx_ready_ext),
        .RSP_TX        (sn_rsp_rx_ext),
        .RSP_TX_VALID  (sn_rsp_rx_valid_ext),
        .RSP_TX_READY  (sn_rsp_rx_ready_ext),
        .RSP_RX        (sn_rsp_tx_ext),
        .RSP_RX_VALID  (sn_rsp_tx_valid_ext),
        .RSP_RX_READY  (sn_rsp_tx_ready_ext),
        .SNP_TX        (sn_snp_rx_ext),
        .SNP_TX_VALID  (sn_snp_rx_valid_ext),
        .SNP_TX_READY  (sn_snp_rx_ready_ext),
        .SNP_RX        (sn_snp_tx_ext),
        .SNP_RX_VALID  (sn_snp_tx_valid_ext),
        .SNP_RX_READY  (sn_snp_tx_ready_ext),
        .DAT_TX        (sn_dat_rx_ext),
        .DAT_TX_VALID  (sn_dat_rx_valid_ext),
        .DAT_TX_READY  (sn_dat_rx_ready_ext),
        .DAT_RX        (sn_dat_tx_ext),
        .DAT_RX_VALID  (sn_dat_tx_valid_ext),
        .DAT_RX_READY  (sn_dat_tx_ready_ext),
        .CREDIT_ON     (credit_ret_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM*`C2_BOUND_GROUP_NUM)*`C2_CREDIT_W +: `C2_CREDIT_W]),
        .CREDIT_RET    (credit_on_bus[(`C2_RN_NUM+`C2_BOUND_LANE_NUM*`C2_BOUND_GROUP_NUM)*`C2_CREDIT_W +: `C2_CREDIT_W]),
        .SN_ACTIVE     (),
        .SN_IDLE       (sn_idle)
    );

    //------------------------------------------------------------------
    // credit 预算管理（16 条 link：4 local + 8 boundary + 4 SN 段）
    //------------------------------------------------------------------
    assign credit_link_up[0]  = 1'b1;
    assign credit_link_up[1]  = 1'b1;
    assign credit_link_up[2]  = 1'b1;
    assign credit_link_up[3]  = 1'b1;
    assign credit_link_up[4]  = 1'b1;
    assign credit_link_up[5]  = 1'b0;
    assign credit_link_up[6]  = 1'b0;
    assign credit_link_up[7]  = 1'b0;
    assign credit_link_up[8]  = 1'b0;
    assign credit_link_up[9]  = 1'b0;
    assign credit_link_up[10] = 1'b0;
    assign credit_link_up[11] = 1'b0;
    assign credit_link_up[12] = 1'b1;
    assign credit_link_up[13] = 1'b0;
    assign credit_link_up[14] = 1'b0;
    assign credit_link_up[15] = 1'b0;

    case2_router_credit_mgr u_credit_mgr (
        .CLK          (CLK),
        .RST_N        (rst_sync_n),
        .LINK_UP      (credit_link_up),
        .CREDIT_RET   (credit_ret_bus),
        .CREDIT_ON    (credit_on_bus),
        .CREDIT_OK    (credit_ok),
        .CREDIT_DBG   (CREDIT_DBG),
        .CREDIT_EMPTY (credit_empty),
        .MGR_ACTIVE   (mgr_active)
    );

    //------------------------------------------------------------------
    // 调试缓冲（内部例化 RAM_SP_BE）+ CFG FIFO（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    assign dbg_flit   = {{(`C2_FLIT_W-`C2_CFG_DATA_W){1'b0}}, CFG_WDATA};
    assign dbg_wr_ptr = CFG_ADDR[`C2_BUF_PTR_W-1:0];
    assign dbg_rd_ptr = CFG_ADDR[`C2_BUF_PTR_W-1:0];

    case2_noc_buf_ram_wrap u_dbg_ram (
        .CLK        (CLK),
        .RST_N      (rst_sync_n),
        .FLIT_WR    (CFG_WR),
        .FLIT_IN    (dbg_flit),
        .WR_PTR     (dbg_wr_ptr),
        .RD_PTR     (dbg_rd_ptr),
        .FLIT_OUT   (),
        .RAM_READY  (dbg_ram_ready),
        .RAM_CREDIT (dbg_ram_credit),
        .RAM_Q_WORD (dbg_ram_word)
    );

    case2_sync_fifo u_cfg_fifo (
        .CLK        (CLK),
        .RST_N      (rst_sync_n),
        .WR_DATA    (CFG_WDATA),
        .WR_EN      (CFG_WR),
        .WR_READY   (),
        .RD_DATA    (cfg_fifo_rd),
        .RD_EN      (CFG_RD),
        .RD_VALID   (),
        .FIFO_LEVEL (),
        .FIFO_FULL  (),
        .FIFO_EMPTY (cfg_fifo_empty)
    );

    assign mesh_active = mgr_active | (~credit_empty) | (~(&rn_idle));

endmodule
