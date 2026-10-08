//==========================================================================
//  case1_dma_engine.v
//  DMA 主机侧引擎：`C1_DMA_CH_NUM 个通道 + 描述符预取
//
//  for-generate 例化 4 个 case1_dma_desc_fetch u_fetch[c]（每通道一个描述符
//  缓冲，内部各含一个 RAM_SP），通道仲裁后产生 AHB 请求；
//  credit 由上游 master wrap 给入，发起请求时消耗，REQ_DONE 后由链路归还。
//
//  Ref: DMAC 多通道引擎（通道仲裁 + descriptor fetch）+
//       credit-based link flow control 的主机侧实现。
//==========================================================================
`include "case1_define.v"

module case1_dma_engine (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          DMA_START,
    input  wire [`C1_DMA_DESC_W-1:0]     DESC_IN,
    input  wire [`C1_CR_CNT_W-1:0]       CREDIT_IN,
    input  wire                          CREDIT_VALID,
    output wire [`C1_CR_CNT_W-1:0]       CREDIT_ISSUED,
    output wire                          REQ_VALID,
    output wire [`C1_AHB_ADDR_W-1:0]     REQ_ADDR,
    output wire                          REQ_WRITE,
    output wire [`C1_AHB_DATA_W-1:0]     REQ_WDATA,
    output wire [`C1_AHB_STRB_W-1:0]     REQ_STRB,
    input  wire                          REQ_DONE,
    output wire [`C1_MON_CNT_W-1:0]      DESC_CNT,
    output wire                          DMA_BUSY
);

    parameter CH_NUM     = `C1_DMA_CH_NUM;
    parameter DESC_DEPTH = `C1_CR_RET_BUF_DEPTH;

    wire [`C1_AHB_ADDR_W-1:0]  ch_desc_addr   [0:`C1_DMA_CH_NUM-1];
    wire [`C1_AHB_DATA_W-1:0]  ch_desc_rdata  [0:`C1_DMA_CH_NUM-1];
    wire                       ch_fetch_busy  [0:`C1_DMA_CH_NUM-1];
    wire [`C1_CR_CNT_W-1:0]    ch_credit_issued[0:`C1_DMA_CH_NUM-1];
    wire                       ch_desc_req    [0:`C1_DMA_CH_NUM-1];
    wire                       ch_enable      [0:`C1_DMA_CH_NUM-1];

    wire [`C1_DMA_CH_NUM-1:0]  ch_req_vec;
    wire [`C1_DMA_CH_NUM-1:0]  ch_busy_vec;
    reg  [`C1_CR_CNT_W-1:0]    issued_sum;
    reg  [`C1_MON_CNT_W-1:0]   desc_cnt_r;
    reg  [`C1_MON_CNT_W-1:0]   req_cnt_r;
    integer                    ci;

    //------------------------------------------------------------------
    // 通道阵列（for-generate：4 个描述符预取器）
    //------------------------------------------------------------------
    genvar gc;
    generate
        for (gc = 0; gc < `C1_DMA_CH_NUM; gc = gc + 1) begin : g_ch
            assign ch_enable[gc]   = DMA_START & (~ch_fetch_busy[gc]);
            assign ch_desc_req[gc] = ch_enable[gc] & CREDIT_VALID;
            assign ch_req_vec[gc]  = ch_desc_req[gc];
            assign ch_busy_vec[gc] = ch_fetch_busy[gc];

            case1_dma_desc_fetch #(
                .DESC_DEPTH    (`C1_CR_RET_BUF_DEPTH),
                .FETCH_LATENCY (4)
            ) u_fetch[gc] (
                .HCLK          (HCLK),
                .HRESETn       (HRESETn),
                .CH_ENABLE     (ch_enable[gc]),
                .DESC_REQ      (ch_desc_req[gc]),
                .DESC_ADDR     (ch_desc_addr[gc]),
                .DESC_RDATA    (ch_desc_rdata[gc]),
                .FETCH_BUSY    (ch_fetch_busy[gc]),
                .CREDIT_IN     (CREDIT_IN),
                .CREDIT_VALID  (CREDIT_VALID),
                .CREDIT_ISSUED (ch_credit_issued[gc])
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 通道请求聚合（固定优先级：通道 0 优先）
    //------------------------------------------------------------------
    always @(*) begin
        issued_sum = {`C1_CR_CNT_W{1'b0}};
        for (ci = 0; ci < `C1_DMA_CH_NUM; ci = ci + 1) begin
            issued_sum = issued_sum + ch_credit_issued[ci];
        end
    end

    assign CREDIT_ISSUED = issued_sum;
    assign REQ_VALID     = |ch_req_vec;
    assign REQ_ADDR      = ch_desc_addr[0];
    assign REQ_WRITE     = 1'b0;
    assign REQ_WDATA     = ch_desc_rdata[0];
    assign REQ_STRB      = {`C1_AHB_STRB_W{1'b1}};
    assign DMA_BUSY      = |ch_busy_vec;
    assign DESC_CNT      = desc_cnt_r;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            desc_cnt_r <= {`C1_MON_CNT_W{1'b0}};
            req_cnt_r  <= {`C1_MON_CNT_W{1'b0}};
        end else begin
            if (REQ_DONE) begin
                desc_cnt_r <= desc_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
            end
            if (|ch_req_vec) begin
                req_cnt_r <= req_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
            end
        end
    end

endmodule
