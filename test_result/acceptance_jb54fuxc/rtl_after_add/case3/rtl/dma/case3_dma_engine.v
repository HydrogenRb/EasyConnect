//==========================================================================
//  case3_dma_engine.v
//  DMA 引擎：描述符读取（dma_desc_fetch）+ 收发 FIFO + 描述符环 RAM_SP。
//  同一个小 FIFO 模块在此以两个不同实例名出现（u_tx_fifo / u_rx_fifo）。
//
//  Ref: 简化版 DMAC（Arm PL330 的 desc fetch + MFIFO 结构）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_dma_engine (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire                          XFER_REQ,
    input  wire [`C3_XFER_LEN_W-1:0]     XFER_LEN,
    input  wire [`C3_CFG_DATA_W-1:0]     CFG_CTRL,
    output wire                          XFER_ACK,
    output wire                          XFER_DONE,
    output wire [`C3_DESC_W-1:0]         DESC_DATA,
    output wire                          DESC_VALID,
    input  wire                          DESC_READY,
    output wire [`C3_TXN_ID_W-1:0]       TXN_ID,
    output wire                          DMA_BUSY,
    output wire                          SP_C_CEN,
    output wire                          SP_C_WEN,
    output wire [`C3_SCRATCH_ADDR_W-1:0] SP_C_ADDR,
    output wire [`C3_SCRATCH_DATA_W-1:0] SP_C_D,
    input  wire [`C3_SCRATCH_DATA_W-1:0] SP_C_Q,

    output wire [8 -1:0] ec_debug // EasyConnect acceptance
);

    parameter DMA_CHAN   = 0;
    parameter DMA_BURST  = `C3_XFER_CNT_W;

    reg  [`C3_XFER_CNT_W-1:0] cnt_r;
    reg  [`C3_XFER_ID_W-1:0]  id_r;
    reg                       busy_r;
    reg                       done_r;

    wire [`C3_DESC_W-1:0]     desc_rdata_w;
    wire                      desc_valid_w;
    wire                      desc_ready_w;
    wire                      desc_err_w;
    wire                      fetch_idle_w;
    wire [`C3_DATA_W-1:0]     tx_data_w;
    wire [`C3_DATA_W-1:0]     rx_data_w;
    wire                      tx_full_w;
    wire                      rx_empty_w;
    wire [`C3_FIFO_CNT_W-1:0] tx_cnt_w;
    wire [`C3_FIFO_CNT_W-1:0] rx_cnt_w;
    wire                      tx_err_w;
    wire                      rx_err_w;
    wire                      req_sync_w;
    wire [`C3_BANK_ADDR_W-1:0] ring_addr_w;
    wire [`C3_BANK_NUM-1:0]   ring_ben_w;
    wire [`C3_DATA_W-1:0]     ring_q_w;

    assign XFER_ACK   = req_sync_w;
    assign XFER_DONE  = done_r & DESC_READY;
    assign DESC_DATA  = desc_rdata_w;
    assign DESC_VALID = desc_valid_w & ~fetch_idle_w;
    assign TXN_ID     = {{(`C3_TXN_ID_W-`C3_XFER_ID_W){1'b0}}, id_r};
    assign DMA_BUSY   = busy_r | (~DESC_READY) | tx_full_w | (~rx_empty_w);
    assign SP_C_CEN   = ~(XFER_REQ | busy_r);
    assign SP_C_WEN   = ~CFG_CTRL[`C3_OP_W-1];
    assign SP_C_ADDR  = {{(`C3_SCRATCH_ADDR_W-`C3_XFER_CNT_W){1'b0}}, cnt_r} ^
                        {`C3_SCRATCH_ADDR_W{XFER_REQ}};
    assign SP_C_D     = tx_data_w ^ rx_data_w ^ ring_q_w;
    assign ring_addr_w = XFER_LEN[`C3_BANK_ADDR_W-1:0];
    assign ring_ben_w  = {`C3_BANK_NUM{CFG_CTRL[0]}};

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            cnt_r  <= {`C3_XFER_CNT_W{1'b0}};
            id_r   <= {`C3_XFER_ID_W{1'b0}};
            busy_r <= 1'b0;
            done_r <= 1'b0;
        end else if (XFER_REQ & (~busy_r)) begin
            cnt_r  <= XFER_LEN[`C3_XFER_CNT_W-1:0];
            id_r   <= XFER_LEN[`C3_XFER_CNT_W-1:0];
            busy_r <= 1'b1;
            done_r <= 1'b0;
        end else if (busy_r & (~tx_full_w)) begin
            cnt_r  <= cnt_r - {{(`C3_XFER_CNT_W-1){1'b0}}, 1'b1};
            busy_r <= (cnt_r != 0);
            done_r <= (cnt_r == 0);
        end else begin
            done_r <= 1'b0;
        end
    end

    case3_dma_desc_fetch u_desc_fetch (
        .CLK         (CLK),
        .RST_N       (RST_N),
        .DESC_REQ    (XFER_REQ),
        .DESC_ADDR   (XFER_LEN[`C3_DESC_AW-1:0]),
        .DESC_WDATA  ({SP_C_Q, SP_C_Q}),
        .DESC_RDATA  (desc_rdata_w),
        .DESC_VALID  (desc_valid_w),
        .DESC_READY  (desc_ready_w),
        .DESC_ERR    (desc_err_w),
        .FETCH_IDLE  (fetch_idle_w),
    
        .ec_debug(ec_debug) // EasyConnect acceptance
);

    case3_sync_fifo u_tx_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_EN      (busy_r),
        .WR_DATA    (SP_C_Q),
        .RD_EN      (XFER_DONE),
        .RD_DATA    (tx_data_w),
        .FIFO_FULL  (tx_full_w),
        .FIFO_EMPTY (),
        .FIFO_CNT   (tx_cnt_w),
        .FIFO_ERR   (tx_err_w)
    );

    case3_sync_fifo u_rx_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_EN      (desc_valid_w),
        .WR_DATA    (desc_rdata_w[`C3_DATA_MSB:0]),
        .RD_EN      (done_r),
        .RD_DATA    (rx_data_w),
        .FIFO_FULL  (),
        .FIFO_EMPTY (rx_empty_w),
        .FIFO_CNT   (rx_cnt_w),
        .FIFO_ERR   (rx_err_w)
    );

    // 描述符环缓冲：库单元位置端口连接
    RAM_SP u_desc_ring (CLK, ~busy_r, ~XFER_REQ, ring_ben_w, ring_addr_w,
                        desc_rdata_w[`C3_DATA_MSB:0], ring_q_w);

    // 请求同步（位置端口连接）
    case3_sync_2ff u_req_sync (CLK, RST_N, XFER_REQ, req_sync_w);

endmodule
