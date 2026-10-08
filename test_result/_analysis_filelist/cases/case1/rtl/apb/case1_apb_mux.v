//==========================================================================
//  case1_apb_mux.v
//  APB 请求/响应转向 + SETUP/ACCESS 相位跟踪
//
//  把 AHB 侧的一次传输压成 APB 的 SETUP(1 拍) + ACCESS(N 拍) 序列，
//  统计 SETUP/ACCESS 停留时间，并把请求交给 credit pool 排空；响应侧
//  把 pool 的 PREADY/PRDATA/PSLVERR 折回 AHB 的 HREADY/HRDATA/HRESP，
//  池产生的归还 credit 也从这里引到桥的观测输出。
//
//  Ref: APB4 状态机（IHI0024 §3.1 SETUP/ACCESS phase）+
//       AHB2APB 桥的响应折返逻辑。
//==========================================================================
`include "case1_define.v"

module case1_apb_mux (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          PCLK,
    input  wire                          PRESETn,
    // AHB 侧
    input  wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]   HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]    HSIZE,
    input  wire                          HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     HWDATA,
    input  wire [`C1_AHB_STRB_W-1:0]     HWSTRB,
    input  wire                          HSEL,
    output wire [`C1_AHB_DATA_W-1:0]     HRDATA,
    output wire                          HREADY,
    output wire [`C1_AHB_HRESP_W-1:0]    HRESP,
    // APB 侧（内部总线，同时抽头到桥的引脚）
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
    // credit
    output wire                          CR_REQ,
    output wire [`C1_CR_CNT_W-1:0]       CR_ISSUED,
    input  wire                          CR_RET_VALID,
    input  wire [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    output wire                          APB_RET_VALID,
    output wire [`C1_CR_CNT_W-1:0]       APB_RET_CNT,
    // 状态
    output wire                          SETUP_ACTIVE,
    output wire                          ACCESS_ACTIVE,
    output wire                          BRIDGE_BUSY
);

    parameter SLOT_NUM = `C1_APB_SLV_NUM;
    parameter ADDR_LSB = `C1_APB_SLOT_LSB;

    reg  [`C1_APB_STATE_W-1:0]  apb_state;
    reg  [`C1_APB_ADDR_W-1:0]   paddr_r;
    reg  [`C1_APB_DATA_W-1:0]   pwdata_r;
    reg  [`C1_APB_STRB_W-1:0]   pstrb_r;
    reg                         pwrite_r;
    reg  [`C1_MON_CNT_W-1:0]    setup_cnt_r;
    reg  [`C1_MON_CNT_W-1:0]    access_cnt_r;
    reg  [`C1_APB_DATA_W-1:0]   ext_prdata_r;
    reg                         ext_pready_r;
    reg                         ext_pslverr_r;
    wire                        req_valid_w;
    wire                        req_accept;

    // 池侧响应 / 归还
    wire [`C1_APB_SLV_NUM-1:0] pool_psel;
    wire [`C1_APB_DATA_W-1:0]  pool_prdata;
    wire                       pool_pready;
    wire                       pool_pslverr;

    assign SETUP_ACTIVE  = (apb_state == `C1_APB_ST_SETUP);
    assign ACCESS_ACTIVE = (apb_state == `C1_APB_ST_ACCESS);
    assign HREADY        = pool_pready;
    assign HRESP         = pool_pslverr ? `C1_AHB_HRESP_ERROR : `C1_AHB_HRESP_OKAY;
    assign HRDATA        = pool_prdata;
    assign PADDR         = paddr_r;
    assign PENABLE       = (apb_state == `C1_APB_ST_ACCESS);
    assign PWRITE        = pwrite_r;
    assign PWDATA        = pwdata_r;
    assign PSTRB         = pstrb_r;
    assign PPROT         = `C1_APB_PPROT_DATA;
    assign PSEL          = pool_psel;

    assign req_valid_w   = (apb_state == `C1_APB_ST_SETUP) ||
                           (apb_state == `C1_APB_ST_ACCESS);
    assign req_accept    = (apb_state == `C1_APB_ST_IDLE) && HSEL &&
                           (HTRANS != `C1_AHB_HTRANS_IDLE);
    assign BRIDGE_BUSY   = (apb_state != `C1_APB_ST_IDLE);

    //------------------------------------------------------------------
    // AHB → APB 相位转换
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            apb_state    <= `C1_APB_ST_IDLE;
            paddr_r      <= {`C1_APB_ADDR_W{1'b0}};
            pwdata_r     <= {`C1_APB_DATA_W{1'b0}};
            pstrb_r      <= {`C1_APB_STRB_W{1'b0}};
            pwrite_r     <= 1'b0;
            setup_cnt_r  <= {`C1_MON_CNT_W{1'b0}};
            access_cnt_r <= {`C1_MON_CNT_W{1'b0}};
        end else begin
            case (apb_state)
                `C1_APB_ST_IDLE: begin
                    if (req_accept) begin
                        paddr_r     <= HADDR;
                        pwdata_r    <= HWDATA;
                        pstrb_r     <= HWSTRB;
                        pwrite_r    <= HWRITE;
                        apb_state   <= `C1_APB_ST_SETUP;
                        setup_cnt_r <= setup_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                    end
                end
                `C1_APB_ST_SETUP: begin
                    apb_state    <= `C1_APB_ST_ACCESS;
                    access_cnt_r <= access_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                end
                `C1_APB_ST_ACCESS: begin
                    if (pool_pready) begin
                        apb_state <= `C1_APB_ST_DONE;
                    end
                end
                `C1_APB_ST_DONE: begin
                    apb_state <= `C1_APB_ST_IDLE;
                end
                default: begin
                    apb_state <= `C1_APB_ST_IDLE;
                end
            endcase
        end
    end

    //------------------------------------------------------------------
    // APB 引脚观测采样（外部 TB 可在引脚上驱动激励，这里只做采样）
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ext_prdata_r  <= {`C1_APB_DATA_W{1'b0}};
            ext_pready_r  <= 1'b1;
            ext_pslverr_r <= 1'b0;
        end else begin
            ext_prdata_r  <= PRDATA;
            ext_pready_r  <= PREADY;
            ext_pslverr_r <= PSLVERR;
        end
    end

    //------------------------------------------------------------------
    // credit pool：per-class 计数 + 归还 FIFO + APB 扇出（内含 crossbar）
    //------------------------------------------------------------------
    case1_apb_credit_pool #(
        .CR_MAX     (`C1_CR_MAX),
        .POOL_DEPTH (`C1_CR_RET_BUF_DEPTH)
    ) u_credit_pool (
        .PCLK           (PCLK),
        .PRESETn        (PRESETn),
        .HCLK           (HCLK),
        .HRESETn        (HRESETn),
        .REQ_ADDR       (paddr_r),
        .REQ_WRITE      (pwrite_r),
        .REQ_WDATA      (pwdata_r),
        .REQ_STRB       (pstrb_r),
        .REQ_PROT       (`C1_APB_PPROT_DATA),
        .REQ_VALID      (req_valid_w),
        .PSEL           (pool_psel),
        .PRDATA         (pool_prdata),
        .PREADY         (pool_pready),
        .PSLVERR        (pool_pslverr),
        .CR_REQ         (CR_REQ),
        .CR_ISSUED      (CR_ISSUED),
        .CR_RET_VALID   (CR_RET_VALID),
        .CR_RET_CNT     (CR_RET_CNT),
        .RET_VALID      (APB_RET_VALID),
        .RET_CNT        (APB_RET_CNT),
        .WM_LOW         (),
        .WM_HIGH        (),
        .RET_FIFO_EMPTY (),
        .RET_FIFO_FULL  ()
    );

endmodule
