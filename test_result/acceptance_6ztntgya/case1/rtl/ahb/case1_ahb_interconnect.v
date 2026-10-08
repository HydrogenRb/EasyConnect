//==========================================================================
//  case1_ahb_interconnect.v
//  AHB-Lite 互连枢纽：解码 + 仲裁 + 每主机 credit 通道 + 每从机 credit 归还
//
//  结构：
//    · 主机总线以数组 m_*[] 收进来，仲裁后扇出成共享从机总线 s_*（位选）
//    · for-generate 例化 `C1_AHB_MASTER_NUM 个 case1_ahb_credit_master
//    · for-generate 例化 `C1_AHB_SLAVE_NUM  个 case1_ahb_credit_slave
//    · case1_ahb_decoder 产生 one-hot HSEL，case1_ahb_slave_mux 负责回选
//
//  Ref: AHB-Lite 多主机互连（IHI0033）+ NoC credit-based link flow control：
//       发送端扣 credit、接收端完成事务后归还 credit。
//==========================================================================
`include "case1_define.v"

module case1_ahb_interconnect (
    input  wire                          HCLK,
    input  wire                          PCLK,
    input  wire                          HRESETn,
    input  wire                          PRESETn,
    // ---- 主机 0 端口 ----
    input  wire [`C1_AHB_ADDR_W-1:0]     M0_HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]   M0_HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]    M0_HSIZE,
    input  wire [`C1_AHB_HBURST_W-1:0]   M0_HBURST,
    input  wire [`C1_AHB_HPROT_W-1:0]    M0_HPROT,
    input  wire                          M0_HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     M0_HWDATA,
    input  wire                          M0_HMASTLOCK,
    input  wire [`C1_AHB_STRB_W-1:0]     M0_HWSTRB,
    output wire                          M0_HREADY,
    output wire [`C1_AHB_HRESP_W-1:0]    M0_HRESP,
    output wire [`C1_AHB_DATA_W-1:0]     M0_HRDATA,
    output wire [`C1_CR_CNT_W-1:0]       M0_CREDIT,
    output wire                          M0_CREDIT_VALID,
    input  wire [`C1_CR_CNT_W-1:0]       M0_CREDIT_ISSUED,
    // ---- 主机 1 端口 ----
    input  wire [`C1_AHB_ADDR_W-1:0]     M1_HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]   M1_HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]    M1_HSIZE,
    input  wire [`C1_AHB_HBURST_W-1:0]   M1_HBURST,
    input  wire [`C1_AHB_HPROT_W-1:0]    M1_HPROT,
    input  wire                          M1_HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     M1_HWDATA,
    input  wire                          M1_HMASTLOCK,
    input  wire [`C1_AHB_STRB_W-1:0]     M1_HWSTRB,
    output wire                          M1_HREADY,
    output wire [`C1_AHB_HRESP_W-1:0]    M1_HRESP,
    output wire [`C1_AHB_DATA_W-1:0]     M1_HRDATA,
    output wire [`C1_CR_CNT_W-1:0]       M1_CREDIT,
    output wire                          M1_CREDIT_VALID,
    input  wire [`C1_CR_CNT_W-1:0]       M1_CREDIT_ISSUED,
    // ---- 监视 / 调试 ----
    output wire [`C1_MON_CNT_W-1:0]      CREDIT_STAT,
    output wire                          XBAR_IDLE
);

    //------------------------------------------------------------------
    // 主机总线数组（分析器看到的 m_* 数组 + 位选扇出）
    //------------------------------------------------------------------
    wire [`C1_AHB_ADDR_W-1:0]   m_haddr     [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_HTRANS_W-1:0] m_htrans    [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_HSIZE_W-1:0]  m_hsize     [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_HBURST_W-1:0] m_hburst    [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_HPROT_W-1:0]  m_hprot     [0:`C1_AHB_MASTER_NUM-1];
    wire                        m_hwrite    [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_DATA_W-1:0]   m_hwdata    [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_AHB_STRB_W-1:0]   m_hwstrb    [0:`C1_AHB_MASTER_NUM-1];
    wire                        m_hmastlock [0:`C1_AHB_MASTER_NUM-1];

    assign m_haddr[0]     = M0_HADDR;
    assign m_haddr[1]     = M1_HADDR;
    assign m_htrans[0]    = M0_HTRANS;
    assign m_htrans[1]    = M1_HTRANS;
    assign m_hsize[0]     = M0_HSIZE;
    assign m_hsize[1]     = M1_HSIZE;
    assign m_hburst[0]    = M0_HBURST;
    assign m_hburst[1]    = M1_HBURST;
    assign m_hprot[0]     = M0_HPROT;
    assign m_hprot[1]     = M1_HPROT;
    assign m_hwrite[0]    = M0_HWRITE;
    assign m_hwrite[1]    = M1_HWRITE;
    assign m_hwdata[0]    = M0_HWDATA;
    assign m_hwdata[1]    = M1_HWDATA;
    assign m_hwstrb[0]    = M0_HWSTRB;
    assign m_hwstrb[1]    = M1_HWSTRB;
    assign m_hmastlock[0] = M0_HMASTLOCK;
    assign m_hmastlock[1] = M1_HMASTLOCK;

    // 共享从机总线（由 grant 选中的主机驱动）
    wire [`C1_AHB_ADDR_W-1:0]   s_haddr;
    wire [`C1_AHB_HTRANS_W-1:0] s_htrans;
    wire [`C1_AHB_HSIZE_W-1:0]  s_hsize;
    wire [`C1_AHB_HBURST_W-1:0] s_hburst;
    wire [`C1_AHB_HPROT_W-1:0]  s_hprot;
    wire                        s_hwrite;
    wire [`C1_AHB_DATA_W-1:0]   s_hwdata;
    wire [`C1_AHB_STRB_W-1:0]   s_hwstrb;

    reg  [`C1_AHB_MASTER_AW-1:0] grant;
    wire [`C1_AHB_SLAVE_NUM-1:0] s_hsel;
    wire [`C1_AHB_SLAVE_AW-1:0]  slv_idx;
    wire                         decode_err;
    wire [`C1_AHB_SLAVE_NUM-1:0] s_hready;
    wire [`C1_AHB_SLAVE_NUM*`C1_AHB_DATA_W-1:0]  s_hrdata_pack;
    wire [`C1_AHB_SLAVE_NUM*`C1_AHB_HRESP_W-1:0] s_hresp_pack;
    wire [`C1_AHB_SLAVE_NUM-1:0] s_ret_valid;
    wire [`C1_AHB_SLAVE_NUM*`C1_CR_CNT_W-1:0]    s_ret_cnt_pack;

    // credit 通道
    wire [`C1_CR_CNT_W-1:0] m_credit      [0:`C1_AHB_MASTER_NUM-1];
    wire                    m_credit_empty[0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_CR_CNT_W-1:0] m_credit_issued[0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_CR_CNT_W-1:0] m_high_wm     [0:`C1_AHB_MASTER_NUM-1];
    reg  [`C1_CR_CNT_W-1:0] m_issued_d    [0:`C1_AHB_MASTER_NUM-1];
    wire                    m_taken       [0:`C1_AHB_MASTER_NUM-1];
    wire [`C1_CR_CNT_W-1:0] s_ret_cnt     [0:`C1_AHB_SLAVE_NUM-1];
    wire                    s_ret_pulse   [0:`C1_AHB_SLAVE_NUM-1];
    wire [`C1_CR_CNT_W-1:0] s_outstanding [0:`C1_AHB_SLAVE_NUM-1];
    wire [`C1_MON_CNT_W-1:0] s_credit_stat[0:`C1_AHB_SLAVE_NUM-1];
    wire                    s_tbl_busy    [0:`C1_AHB_SLAVE_NUM-1];

    wire                    ret_valid_agg;
    wire [`C1_CR_CNT_W-1:0] ret_cnt_agg;
    reg  [`C1_CR_CNT_W-1:0] ret_cnt_sum;
    wire                    apb_bridge_busy;
    wire [`C1_MON_CNT_W-1:0] mux_latency_max;

    assign m_credit_issued[0] = M0_CREDIT_ISSUED;
    assign m_credit_issued[1] = M1_CREDIT_ISSUED;
    assign m_taken[0]         = (m_credit_issued[0] != m_issued_d[0]);
    assign m_taken[1]         = (m_credit_issued[1] != m_issued_d[1]);
    assign M0_CREDIT          = m_credit[0];
    assign M1_CREDIT          = m_credit[1];
    assign M0_CREDIT_VALID    = ~m_credit_empty[0];
    assign M1_CREDIT_VALID    = ~m_credit_empty[1];

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            m_issued_d[0] <= {`C1_CR_CNT_W{1'b0}};
            m_issued_d[1] <= {`C1_CR_CNT_W{1'b0}};
        end else begin
            m_issued_d[0] <= m_credit_issued[0];
            m_issued_d[1] <= m_credit_issued[1];
        end
    end

    //------------------------------------------------------------------
    // 固定优先级仲裁（主机 0 优先；空闲时保持 0）
    //------------------------------------------------------------------
    always @(*) begin
        if (m_htrans[0] != `C1_AHB_HTRANS_IDLE) begin
            grant = 1'b0;
        end else if (m_htrans[1] != `C1_AHB_HTRANS_IDLE) begin
            grant = 1'b1;
        end else begin
            grant = 1'b0;
        end
    end

    assign s_haddr  = m_haddr[grant];
    assign s_htrans = m_htrans[grant];
    assign s_hsize  = m_hsize[grant];
    assign s_hburst = m_hburst[grant];
    assign s_hprot  = m_hprot[grant];
    assign s_hwrite = m_hwrite[grant];
    assign s_hwdata = m_hwdata[grant];
    assign s_hwstrb = m_hwstrb[grant];

    //------------------------------------------------------------------
    // 地址译码（HSEL / SLV_IDX / DECODE_ERR）
    //------------------------------------------------------------------
    case1_ahb_decoder u_decoder (
        .HCLK         (HCLK),
        .HRESETn      (HRESETn),
        .HADDR        (s_haddr),
        .HSEL_DEFAULT (1'b1),
        .HSEL         (s_hsel),
        .SLV_IDX      (slv_idx),
        .DECODE_VAL   (),
        .DECODE_ERR   (decode_err)
    );

    //------------------------------------------------------------------
    // 每个主机的 credit 通道（for-generate，2 个实例 u_m_credit[m]）
    //------------------------------------------------------------------
    genvar m;
    generate
        for (m = 0; m < `C1_AHB_MASTER_NUM; m = m + 1) begin : g_m_credit
            case1_ahb_credit_master #(
                .CR_INIT_LEVEL (`C1_CR_INIT),
                .CR_CLASS      (m)
            ) u_m_credit[m] (
                .HCLK            (HCLK),
                .HRESETn         (HRESETn),
                .CR_CREDIT       (m_credit[m]),
                .CR_EMPTY        (m_credit_empty[m]),
                .CR_TAKEN        (m_taken[m]),
                .CR_RET_VALID    (ret_valid_agg),
                .CR_RET_CNT      (ret_cnt_agg),
                .CR_GRANT        (),
                .CR_HIGH_WM_STAT (m_high_wm[m]),
                .CR_FULL         ()
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 每个从机的 credit 归还通道（for-generate，4 个 u_s_credit[s]）
    //------------------------------------------------------------------
    genvar s;
    generate
        for (s = 0; s < `C1_AHB_SLAVE_NUM; s = s + 1) begin : g_s_credit
            assign s_ret_pulse[s] = s_hsel[s] && (s_htrans != `C1_AHB_HTRANS_IDLE) &&
                                    s_hready[s];
        end

        for (s = 0; s < `C1_AHB_SLAVE_NUM; s = s + 1) begin : g_s_credit_inst
            case1_ahb_credit_slave #(
                .SLV_IDX     (s),
                .TRACK_DEPTH (`C1_TRACKER_DEPTH)
            ) u_s_credit[s] (
                .HCLK        (HCLK),
                .HRESETn     (HRESETn),
                .S_HSEL      (s_hsel[s]),
                .S_HREADY    (s_hready[s]),
                .S_TXN_START (s_ret_pulse[s]),
                .CR_RET_VALID(s_ret_valid[s]),
                .CR_RET_CNT  (s_ret_cnt[s]),
                .OUTSTANDING (s_outstanding[s]),
                .CREDIT_STAT (s_credit_stat[s]),
                .TBL_BUSY    (s_tbl_busy[s])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 从机回选（read data / response mux）
    //------------------------------------------------------------------
    reg [`C1_AHB_DATA_W-1:0]  resp_hrdata;
    reg [`C1_AHB_HRESP_W-1:0] resp_hresp;
    integer                   r_i;

    always @(*) begin
        resp_hrdata = {`C1_AHB_DATA_W{1'b0}};
        resp_hresp  = `C1_AHB_HRESP_OKAY;
        for (r_i = 0; r_i < `C1_AHB_SLAVE_NUM; r_i = r_i + 1) begin
            if (s_hsel[r_i]) begin
                resp_hrdata = s_hrdata_pack[r_i*`C1_AHB_DATA_W +: `C1_AHB_DATA_W];
                resp_hresp  = s_hresp_pack[r_i*`C1_AHB_HRESP_W +: `C1_AHB_HRESP_W];
            end
        end
    end

    assign M0_HREADY = |s_hready;
    assign M1_HREADY = |s_hready;
    assign M0_HRDATA = resp_hrdata;
    assign M1_HRDATA = resp_hrdata;
    assign M0_HRESP  = decode_err ? `C1_AHB_HRESP_ERROR : resp_hresp;
    assign M1_HRESP  = decode_err ? `C1_AHB_HRESP_ERROR : resp_hresp;

    //------------------------------------------------------------------
    // 从机子系统：默认从机阵列 + APB 桥（u_slave_mux）
    //------------------------------------------------------------------
    case1_ahb_slave_mux u_slave_mux (
        .HCLK            (HCLK),
        .PCLK            (PCLK),
        .HRESETn         (HRESETn),
        .PRESETn         (PRESETn),
        .S_HADDR         (s_haddr),
        .S_HTRANS        (s_htrans),
        .S_HSIZE         (s_hsize),
        .S_HBURST        (s_hburst),
        .S_HPROT         (s_hprot),
        .S_HWRITE        (s_hwrite),
        .S_HWDATA        (s_hwdata),
        .S_HWSTRB        (s_hwstrb),
        .S_HSEL          (s_hsel),
        .S_HREADY        (s_hready),
        .S_HRDATA        (s_hrdata_pack),
        .S_HRESP         (s_hresp_pack),
        .S_CR_RET_VALID  (s_ret_valid),
        .S_CR_RET_CNT    (s_ret_cnt_pack),
        .APB_BRIDGE_BUSY (apb_bridge_busy),
        .MUX_LATENCY_MAX (mux_latency_max)
    );

    //------------------------------------------------------------------
    // 归还 credit 聚合：所有从机的归还合并成一条返回流
    //------------------------------------------------------------------
    assign ret_valid_agg = s_ret_valid[0] | s_ret_valid[1] |
                           s_ret_valid[2] | s_ret_valid[3];

    always @(*) begin
        ret_cnt_sum = {`C1_CR_CNT_W{1'b0}};
        for (r_i = 0; r_i < `C1_AHB_SLAVE_NUM; r_i = r_i + 1) begin
            ret_cnt_sum = ret_cnt_sum + s_ret_cnt[r_i];
        end
    end

    assign ret_cnt_agg = ret_cnt_sum;

    assign CREDIT_STAT = {{(`C1_MON_CNT_W-`C1_CR_CNT_W*2){1'b0}},
                          m_high_wm[1], m_high_wm[0]};
    assign XBAR_IDLE   = (m_htrans[0] == `C1_AHB_HTRANS_IDLE) &&
                         (m_htrans[1] == `C1_AHB_HTRANS_IDLE) &&
                         (apb_bridge_busy == 1'b0);

endmodule
