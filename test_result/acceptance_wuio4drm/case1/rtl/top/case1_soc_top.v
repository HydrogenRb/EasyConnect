//==========================================================================
//  case1_soc_top.v
//  case1 顶层：双 AHB-Lite 主机 + credit 流控互连 + AHB/APB 桥 + 性能监视
//
//  两个 AHB-Lite 主机（CPU / DMA）共享一条 AHB 互连；互连里的每个主机端口
//  持有一个 credit 计数器，发起事务扣一个 credit，事务完成后由从机侧归还
//  （credit return path）。credit 用尽时主机端口撤销请求，而不是长期拉低
//  HREADY 反压 —— 这是 NoC / 桥链路里常见的链路级流控做法。
//
//  时钟域：HCLK（AHB 侧）与 PCLK（APB 侧），PRESETn 与 HRESETn 异步。
//
//  Ref: ARM AHB-Lite 多主机互连（IHI0033）+ APB4 桥（IHI0024）+
//       基于 credit 的链路流控（NoC credit-based flow control）。
//==========================================================================
`include "case1_define.v"

module case1_soc_top (
    input  wire                          HCLK,
    input  wire                          PCLK,
    input  wire                          HRESETn,
    input  wire                          PRESETn,
    output wire [`C1_MON_CNT_W-1:0]      MON_TXN_CNT,
    output wire                          MON_IDLE,
    output wire [`C1_MON_CNT_W-1:0]      DBG_CREDIT_STAT
);

    //------------------------------------------------------------------
    // 主机 0（CPU）AHB-Lite 端口
    //------------------------------------------------------------------
    wire [`C1_AHB_ADDR_W-1:0]     m0_haddr;
    wire [`C1_AHB_HTRANS_W-1:0]   m0_htrans;
    wire [`C1_AHB_HSIZE_W-1:0]    m0_hsize;
    wire [`C1_AHB_HBURST_W-1:0]   m0_hburst;
    wire [`C1_AHB_HPROT_W-1:0]    m0_hprot;
    wire                          m0_hwrite;
    wire [`C1_AHB_DATA_W-1:0]     m0_hwdata;
    wire                          m0_hmastlock;
    wire [`C1_AHB_STRB_W-1:0]     m0_hwstrb;
    wire                          m0_hready;
    wire [`C1_AHB_HRESP_W-1:0]    m0_hresp;
    wire [`C1_AHB_DATA_W-1:0]     m0_hrdata;
    wire [`C1_CR_CNT_W-1:0]       m0_credit_in;
    wire                          m0_credit_valid;
    wire [`C1_CR_CNT_W-1:0]       m0_credit_issued;
    wire [`C1_MON_CNT_W-1:0]      m0_txn_cnt;
    wire                          m0_busy;

    //------------------------------------------------------------------
    // 主机 1（DMA）AHB-Lite 端口
    //------------------------------------------------------------------
    wire [`C1_AHB_ADDR_W-1:0]     m1_haddr;
    wire [`C1_AHB_HTRANS_W-1:0]   m1_htrans;
    wire [`C1_AHB_HSIZE_W-1:0]    m1_hsize;
    wire [`C1_AHB_HBURST_W-1:0]   m1_hburst;
    wire [`C1_AHB_HPROT_W-1:0]    m1_hprot;
    wire                          m1_hwrite;
    wire [`C1_AHB_DATA_W-1:0]     m1_hwdata;
    wire                          m1_hmastlock;
    wire [`C1_AHB_STRB_W-1:0]     m1_hwstrb;
    wire                          m1_hready;
    wire [`C1_AHB_HRESP_W-1:0]    m1_hresp;
    wire [`C1_AHB_DATA_W-1:0]     m1_hrdata;
    wire [`C1_CR_CNT_W-1:0]       m1_credit_in;
    wire                          m1_credit_valid;
    wire [`C1_CR_CNT_W-1:0]       m1_credit_issued;
    wire [`C1_MON_CNT_W-1:0]      m1_txn_cnt;
    wire                          m1_busy;

    //------------------------------------------------------------------
    // 互连 / 监视器 之间的状态总线
    //------------------------------------------------------------------
    wire [`C1_MON_CNT_W-1:0]                          xbar_credit_stat;
    wire                                              xbar_idle;
    wire [`C1_MON_CNT_W-1:0]                          mon_txn_cnt;
    wire [`C1_AHB_MASTER_NUM-1:0]                     m_busy;
    wire [`C1_AHB_MASTER_NUM*`C1_CR_CNT_W-1:0]        m_credit_level;
    wire [`C1_AHB_MASTER_NUM*`C1_MON_CNT_W-1:0]       m_txn_cnt;

    assign m_busy         = {m1_busy, m0_busy};
    assign m_credit_level = {m1_credit_in, m0_credit_in};
    assign m_txn_cnt      = {m1_txn_cnt, m0_txn_cnt};

    //------------------------------------------------------------------
    // CPU 主机（带 RV32 tracker 链的 master wrap 副本）
    //------------------------------------------------------------------
    case1_ahb_master_wrap #(
        .IS_CPU     (1)
    ) u_cpu_m0 (
        .HCLK            (HCLK),
        .HRESETn         (HRESETn),
        .CREDIT_IN       (m0_credit_in),
        .CREDIT_VALID    (m0_credit_valid),
        .CREDIT_ISSUED   (m0_credit_issued),
        .HADDR           (m0_haddr),
        .HTRANS          (m0_htrans),
        .HSIZE           (m0_hsize),
        .HBURST          (m0_hburst),
        .HPROT           (m0_hprot),
        .HWRITE          (m0_hwrite),
        .HWDATA          (m0_hwdata),
        .HMASTLOCK       (m0_hmastlock),
        .HWSTRB          (m0_hwstrb),
        .HREADY          (m0_hready),
        .HRESP           (m0_hresp),
        .HRDATA          (m0_hrdata),
        .TXN_CNT         (m0_txn_cnt),
        .BUSY            (m0_busy)
    );

    //------------------------------------------------------------------
    // DMA 主机（同一 master wrap 模块，不同实例名；无 tracker 分支）
    //------------------------------------------------------------------
    case1_ahb_master_wrap #(
        .IS_CPU     (0)
    ) u_dma_m0 (
        .HCLK            (HCLK),
        .HRESETn         (HRESETn),
        .CREDIT_IN       (m1_credit_in),
        .CREDIT_VALID    (m1_credit_valid),
        .CREDIT_ISSUED   (m1_credit_issued),
        .HADDR           (m1_haddr),
        .HTRANS          (m1_htrans),
        .HSIZE           (m1_hsize),
        .HBURST          (m1_hburst),
        .HPROT           (m1_hprot),
        .HWRITE          (m1_hwrite),
        .HWDATA          (m1_hwdata),
        .HMASTLOCK       (m1_hmastlock),
        .HWSTRB          (m1_hwstrb),
        .HREADY          (m1_hready),
        .HRESP           (m1_hresp),
        .HRDATA          (m1_hrdata),
        .TXN_CNT         (m1_txn_cnt),
        .BUSY            (m1_busy)
    );

    //------------------------------------------------------------------
    // AHB 互连（内含 decoder / credit 通道 / slave mux / APB 桥子树）
    //------------------------------------------------------------------
    case1_ahb_interconnect u_xbar (
        .HCLK            (HCLK),
        .PCLK            (PCLK),
        .HRESETn         (HRESETn),
        .PRESETn         (PRESETn),
        .M0_HADDR        (m0_haddr),
        .M0_HTRANS       (m0_htrans),
        .M0_HSIZE        (m0_hsize),
        .M0_HBURST       (m0_hburst),
        .M0_HPROT        (m0_hprot),
        .M0_HWRITE       (m0_hwrite),
        .M0_HWDATA       (m0_hwdata),
        .M0_HMASTLOCK    (m0_hmastlock),
        .M0_HWSTRB       (m0_hwstrb),
        .M0_HREADY       (m0_hready),
        .M0_HRESP        (m0_hresp),
        .M0_HRDATA       (m0_hrdata),
        .M0_CREDIT       (m0_credit_in),
        .M0_CREDIT_VALID (m0_credit_valid),
        .M0_CREDIT_ISSUED(m0_credit_issued),
        .M1_HADDR        (m1_haddr),
        .M1_HTRANS       (m1_htrans),
        .M1_HSIZE        (m1_hsize),
        .M1_HBURST       (m1_hburst),
        .M1_HPROT        (m1_hprot),
        .M1_HWRITE       (m1_hwrite),
        .M1_HWDATA       (m1_hwdata),
        .M1_HMASTLOCK    (m1_hmastlock),
        .M1_HWSTRB       (m1_hwstrb),
        .M1_HREADY       (m1_hready),
        .M1_HRESP        (m1_hresp),
        .M1_HRDATA       (m1_hrdata),
        .M1_CREDIT       (m1_credit_in),
        .M1_CREDIT_VALID (m1_credit_valid),
        .M1_CREDIT_ISSUED(m1_credit_issued),
        .CREDIT_STAT     (xbar_credit_stat),
        .XBAR_IDLE       (xbar_idle)
    );

    //------------------------------------------------------------------
    // 性能监视器：统计事务数、空闲周期、credit 水位
    //------------------------------------------------------------------
    case1_perf_monitor u_perf_mon (
        .HCLK             (HCLK),
        .PCLK             (PCLK),
        .HRESETn          (HRESETn),
        .PRESETn          (PRESETn),
        .M_BUSY           (m_busy),
        .M_CREDIT_LEVEL   (m_credit_level),
        .M_TXN_CNT        (m_txn_cnt),
        .XBAR_CREDIT_STAT (xbar_credit_stat),
        .XBAR_IDLE        (xbar_idle),
        .MON_TXN_CNT      (mon_txn_cnt),
        .MON_IDLE         (MON_IDLE),
        .DBG_CREDIT_STAT  (DBG_CREDIT_STAT)
    );

    assign MON_TXN_CNT = mon_txn_cnt;

endmodule
