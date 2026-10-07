//==========================================================================
//  case1_ahb_to_apb_bridge.v
//  AHB-Lite → APB4 协议桥（APB 子系统入口）
//
//  内部层次：u_apb_mux → u_credit_pool → u_crossbar → u_slot[s] → u_regfile
//  AHB 侧按 SETUP/ACCESS 两拍把一次 AHB 传输转换成一次 APB 传输；APB 侧
//  用 credit pool 控制链路上未完成事务数（CR_MAX），事务完成时归还 credit。
//
//  说明：APB 从机阵列在桥内部，因此 PADDR/PSEL/... 引脚是内部 APB 总线的
//  观测抽头；PRDATA/PREADY/PSLVERR 引脚供外部 TB 观测（内部响应优先）。
//
//  Ref: ARM AHB-to-APB bridge（IHI0024 / DesignStart 的 apb_bridge）+
//       credit-based link flow control 的桥接实现。
//==========================================================================
`include "case1_define.v"

module case1_ahb_to_apb_bridge (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          PCLK,
    input  wire                          PRESETn,
    // ---- AHB 从机端口 ----
    input  wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]   HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]    HSIZE,
    input  wire [`C1_AHB_HBURST_W-1:0]   HBURST,
    input  wire [`C1_AHB_HPROT_W-1:0]    HPROT,
    input  wire                          HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     HWDATA,
    input  wire [`C1_AHB_STRB_W-1:0]     HWSTRB,
    input  wire                          HSEL,
    output wire [`C1_AHB_DATA_W-1:0]     HRDATA,
    output wire                          HREADY,
    output wire [`C1_AHB_HRESP_W-1:0]    HRESP,
    // ---- APB4 主机端口 ----
    output wire [`C1_APB_ADDR_W-1:0]     PADDR,
    output wire [`C1_APB_SLV_NUM-1:0]    PSEL,
    output wire                          PENABLE,
    output wire                          PWRITE,
    output wire [`C1_APB_DATA_W-1:0]     PWDATA,
    output wire [`C1_APB_STRB_W-1:0]     PSTRB,
    output wire [`C1_APB_PROT_W-1:0]     PPROT,
    input  wire [`C1_APB_DATA_W-1:0]     PRDATA,
    input  wire                          PREADY,
    input  wire                          PSLVERR,
    // ---- credit 接口 ----
    input  wire [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    input  wire                          CR_RET_VALID,
    output wire [`C1_CR_CNT_W-1:0]       CR_ISSUED,
    output wire                          CR_REQ,
    output wire                          BRIDGE_BUSY,
    // ---- APB 侧归还 credit 的观测输出（给 AHB 侧整形后再注入 CR_RET_*）----
    output wire                          APB_CR_RETURN,
    output wire [`C1_CR_CNT_W-1:0]       APB_CR_RET_CNT
);

    parameter APB_SLOT_NUM = `C1_APB_SLV_NUM;
    parameter CR_MAX       = `C1_CR_MAX;
    parameter ADDR_LSB     = 0;

    // mux 侧总线（桥内部真实使用的 APB 总线）
    wire [`C1_APB_ADDR_W-1:0]  mux_paddr;
    wire [`C1_APB_SLV_NUM-1:0] mux_psel;
    wire                       mux_penable;
    wire                       mux_pwrite;
    wire [`C1_APB_DATA_W-1:0]  mux_pwdata;
    wire [`C1_APB_STRB_W-1:0]  mux_pstrb;
    wire [`C1_APB_PROT_W-1:0]  mux_pprot;
    wire [`C1_AHB_DATA_W-1:0]  mux_hrdata;
    wire                       mux_hready;
    wire [`C1_AHB_HRESP_W-1:0] mux_hresp;
    wire [`C1_CR_CNT_W-1:0]    mux_cr_issued;
    wire                       mux_cr_req;
    wire                       mux_setup;
    wire                       mux_access;
    wire                       mux_apb_ret_valid;
    wire [`C1_CR_CNT_W-1:0]    mux_apb_ret_cnt;

    // APB 引脚是内部总线的观测抽头（APB 从机阵列在桥内部）
    assign PADDR         = mux_paddr;
    assign PSEL          = mux_psel;
    assign PENABLE       = mux_penable;
    assign PWRITE        = mux_pwrite;
    assign PWDATA        = mux_pwdata;
    assign PSTRB         = mux_pstrb;
    assign PPROT         = mux_pprot;
    assign HRDATA        = mux_hrdata;
    assign HREADY        = mux_hready;
    assign HRESP         = mux_hresp;
    assign CR_ISSUED     = mux_cr_issued;
    assign CR_REQ        = mux_cr_req;
    assign APB_CR_RETURN = mux_apb_ret_valid;
    assign APB_CR_RET_CNT = mux_apb_ret_cnt;

    //------------------------------------------------------------------
    // APB 请求/响应转向 + SETUP/ACCESS 跟踪
    //------------------------------------------------------------------
    case1_apb_mux #(
        .SLOT_NUM (APB_SLOT_NUM),
        .ADDR_LSB (ADDR_LSB)
    ) u_apb_mux (
        .HCLK          (HCLK),
        .HRESETn       (HRESETn),
        .PCLK          (PCLK),
        .PRESETn       (PRESETn),
        .HADDR         (HADDR),
        .HTRANS        (HTRANS),
        .HSIZE         (HSIZE),
        .HWRITE        (HWRITE),
        .HWDATA        (HWDATA),
        .HWSTRB        (HWSTRB),
        .HSEL          (HSEL),
        .HRDATA        (mux_hrdata),
        .HREADY        (mux_hready),
        .HRESP         (mux_hresp),
        .PADDR         (mux_paddr),
        .PSEL          (mux_psel),
        .PENABLE       (mux_penable),
        .PWRITE        (mux_pwrite),
        .PWDATA        (mux_pwdata),
        .PSTRB         (mux_pstrb),
        .PPROT         (mux_pprot),
        .PRDATA        (PRDATA),
        .PREADY        (PREADY),
        .PSLVERR       (PSLVERR),
        .CR_REQ        (mux_cr_req),
        .CR_ISSUED     (mux_cr_issued),
        .CR_RET_VALID  (CR_RET_VALID),
        .CR_RET_CNT    (CR_RET_CNT),
        .APB_RET_VALID (mux_apb_ret_valid),
        .APB_RET_CNT   (mux_apb_ret_cnt),
        .SETUP_ACTIVE  (mux_setup),
        .ACCESS_ACTIVE (mux_access),
        .BRIDGE_BUSY   (BRIDGE_BUSY)
    );

endmodule
