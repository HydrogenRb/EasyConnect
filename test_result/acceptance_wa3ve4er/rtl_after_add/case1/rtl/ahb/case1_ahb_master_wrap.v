//==========================================================================
//  case1_ahb_master_wrap.v
//  AHB 主机 wrapper：master FSM + 主机侧请求源（CPU tracker 链 / DMA 引擎）
//
//  同一个模块在 case1_soc_top 里被例化两次（u_cpu_m0 / u_dma_m0）：
//    IS_CPU = 1 → 内部走 generate-if 的 CPU 分支，挂 RV32 tracker 链
//                 （case1_cpu_tracker_rv32 → case1_cpu_tracker）
//    IS_CPU = 0 → 内部走 DMA 分支，挂 case1_dma_engine
//  这是"同一模块、两个不同实例名、内部子树不同"的典型写法。
//
//  Ref: AHB-Lite 主机子系统（CPU/DMA 双主机）在真实 SoC 中的封装方式。
//==========================================================================
`include "case1_define.v"

module case1_ahb_master_wrap (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_CR_CNT_W-1:0]       CREDIT_IN,
    input  wire                          CREDIT_VALID,
    output wire [`C1_CR_CNT_W-1:0]       CREDIT_ISSUED,
    output wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    output wire [`C1_AHB_HTRANS_W-1:0]   HTRANS,
    output wire [`C1_AHB_HSIZE_W-1:0]    HSIZE,
    output wire [`C1_AHB_HBURST_W-1:0]   HBURST,
    output wire [`C1_AHB_HPROT_W-1:0]    HPROT,
    output wire                          HWRITE,
    output wire [`C1_AHB_DATA_W-1:0]     HWDATA,
    output wire                          HMASTLOCK,
    output wire [`C1_AHB_STRB_W-1:0]     HWSTRB,
    input  wire                          HREADY,
    input  wire [`C1_AHB_HRESP_W-1:0]    HRESP,
    input  wire [`C1_AHB_DATA_W-1:0]     HRDATA,
    output wire [`C1_MON_CNT_W-1:0]      TXN_CNT,
    output wire                          BUSY,

    output wire [8 -1:0] ec_debug // EasyConnect acceptance
);

    // IS_CPU = 1 时挂 tracker 链，= 0 时为 DMA 主机
    parameter IS_CPU     = 1;
    parameter TRACK_DEPTH = `C1_TRACKER_DEPTH;
    parameter DMA_CH_NUM  = `C1_DMA_CH_NUM;

    //------------------------------------------------------------------
    // 请求侧（两种主机源的公共接口）
    //------------------------------------------------------------------
    wire [`C1_AHB_ADDR_W-1:0]   req_addr;
    wire [`C1_AHB_DATA_W-1:0]   req_wdata;
    wire [`C1_AHB_STRB_W-1:0]   req_strb;
    wire                        req_write;
    wire                        req_valid;
    wire                        cr_taken;
    wire                        txn_done_w;

    // CPU tracker 链
    wire [`C1_AHB_ADDR_W-1:0]   trk_addr;
    wire                        trk_write;
    wire                        trk_valid;
    wire [`C1_TXN_ID_W-1:0]     trk_id;
    wire [`C1_MON_CNT_W-1:0]    trk_cnt;
    wire                        trk_full;

    // DMA 引擎
    wire [`C1_AHB_ADDR_W-1:0]   dma_addr;
    wire [`C1_AHB_DATA_W-1:0]   dma_wdata;
    wire [`C1_AHB_STRB_W-1:0]   dma_strb;
    wire                        dma_write;
    wire                        dma_valid;
    wire [`C1_CR_CNT_W-1:0]     dma_credit_issued;
    wire [`C1_MON_CNT_W-1:0]    dma_desc_cnt;
    wire                        dma_busy;

    reg  [`C1_CR_CNT_W-1:0]     issued_cnt;
    wire                        retire_pulse;
    wire                        trk_not_full;

    assign retire_pulse = CREDIT_VALID;
    assign txn_done_w   = cr_taken;
    assign trk_not_full = ~trk_full;
    assign CREDIT_ISSUED = issued_cnt;

    // 已发起 credit 计数（饱和回绕到 0，credit 归还由互连侧统计）
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            issued_cnt <= {`C1_CR_CNT_W{1'b0}};
        end else if (cr_taken) begin
            if (issued_cnt == `C1_CR_MAX) begin
                issued_cnt <= {`C1_CR_CNT_W{1'b0}};
            end else begin
                issued_cnt <= issued_cnt + 1'b1;
            end
        end
    end

    //------------------------------------------------------------------
    // 请求源选择：CPU tracker 分支 / DMA 分支（generate-if）
    //------------------------------------------------------------------
    generate
        if (IS_CPU == 1) begin : g_cpu_src
            // CPU 主机：tracker 链把 CPU 侧事务打成 AHB 探测请求
            case1_cpu_tracker_rv32 #(
                .TRACK_DEPTH (`C1_TRACKER_DEPTH),
                .CPU_ID      (0)
            ) u_track (
                .HCLK         (HCLK),
                .HRESETn      (HRESETn),
                .PC_ADDR      (HADDR),
                .RETIRE_VALID (retire_pulse),
                .TXN_DONE     (txn_done_w),
                .TXN_ADDR     (trk_addr),
                .TXN_WRITE    (trk_write),
                .TXN_VALID    (trk_valid),
                .TXN_ID       (trk_id),
                .TRACK_CNT    (trk_cnt),
                .TRACK_FULL   (trk_full)
            );

            assign req_addr  = trk_addr;
            assign req_write = trk_write;
            assign req_valid = trk_valid && trk_not_full;
            assign req_wdata = {`C1_AHB_DATA_W{1'b0}};
            assign req_strb  = {`C1_AHB_STRB_W{1'b0}};
        end else begin : g_dma_src
            // DMA 主机：描述符引擎直接产生读写请求
            case1_dma_engine #(
                .CH_NUM      (`C1_DMA_CH_NUM),
                .DESC_DEPTH  (`C1_CR_RET_BUF_DEPTH)
            ) u_dma (
                .HCLK            (HCLK),
                .HRESETn         (HRESETn),
                .DMA_START       (1'b1),
                .DESC_IN         ({`C1_DMA_DESC_W{1'b0}}),
                .CREDIT_IN       (CREDIT_IN),
                .CREDIT_VALID    (CREDIT_VALID),
                .CREDIT_ISSUED   (dma_credit_issued),
                .REQ_VALID       (dma_valid),
                .REQ_ADDR        (dma_addr),
                .REQ_WRITE       (dma_write),
                .REQ_WDATA       (dma_wdata),
                .REQ_STRB        (dma_strb),
                .REQ_DONE        (txn_done_w),
                .DESC_CNT        (dma_desc_cnt),
                .DMA_BUSY        (dma_busy),
            
        .ec_debug(ec_debug) // EasyConnect acceptance
);

            assign req_addr  = dma_addr;
            assign req_write = dma_write;
            assign req_valid = dma_valid;
            assign req_wdata = dma_wdata;
            assign req_strb  = dma_strb;
        end
    endgenerate

    //------------------------------------------------------------------
    // 公共 AHB 主机 FSM
    //------------------------------------------------------------------
    case1_ahb_master #(
        .CR_CLASS    (0),
        .HPROT_VALUE (`C1_AHB_HPROT_DATA)
    ) u_issue (
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .CR_CREDIT  (CREDIT_IN),
        .CR_EMPTY   (~CREDIT_VALID),
        .CR_TAKEN   (cr_taken),
        .REQ_VALID  (req_valid),
        .REQ_ADDR   (req_addr),
        .REQ_WRITE  (req_write),
        .REQ_WDATA  (req_wdata),
        .REQ_STRB   (req_strb),
        .HADDR      (HADDR),
        .HTRANS     (HTRANS),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HPROT      (HPROT),
        .HWRITE     (HWRITE),
        .HWDATA     (HWDATA),
        .HMASTLOCK  (HMASTLOCK),
        .HWSTRB     (HWSTRB),
        .HREADY     (HREADY),
        .HRESP      (HRESP),
        .HRDATA     (HRDATA),
        .TXN_CNT    (TXN_CNT),
        .BUSY       (BUSY)
    );

endmodule
