//==========================================================================
//  case1_apb_credit_pool.v
//  APB 链路 credit 池：per-class 计数 + 高低水位 + 归还 FIFO + APB 扇出
//
//  credit 类别按地址低位划成 `C1_CR_CLASS_NUM 类（QoS/通道分组），每类的
//  未完成数与水位在 PCLK 域维护；slot 完成时把归还数量压进 u_ret_fifo
//  （case1_sync_fifo），再由 RET_VALID/RET_CNT 交给 AHB 侧整形后归还。
//  池内部例化 case1_apb_crossbar，完成到 `C1_APB_SLV_NUM 个 slot 的扇出。
//
//  Ref: NoC credit pool / per-VC credit counter + credit return FIFO。
//==========================================================================
`include "case1_define.v"

module case1_apb_credit_pool (
    input  wire                          PCLK,
    input  wire                          PRESETn,
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_APB_ADDR_W-1:0]     REQ_ADDR,
    input  wire                          REQ_WRITE,
    input  wire [`C1_APB_DATA_W-1:0]     REQ_WDATA,
    input  wire [`C1_APB_STRB_W-1:0]     REQ_STRB,
    input  wire [`C1_APB_PROT_W-1:0]     REQ_PROT,
    input  wire                          REQ_VALID,
    output wire [`C1_APB_SLV_NUM-1:0]    PSEL,
    output wire [`C1_APB_DATA_W-1:0]     PRDATA,
    output wire                          PREADY,
    output wire                          PSLVERR,
    output wire                          CR_REQ,
    output wire [`C1_CR_CNT_W-1:0]       CR_ISSUED,
    input  wire                          CR_RET_VALID,
    input  wire [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    output wire                          RET_VALID,
    output wire [`C1_CR_CNT_W-1:0]       RET_CNT,
    output wire                          WM_LOW,
    output wire                          WM_HIGH,
    output wire                          RET_FIFO_EMPTY,
    output wire                          RET_FIFO_FULL
);

    parameter CR_MAX     = `C1_CR_MAX;
    parameter POOL_DEPTH = `C1_CR_RET_BUF_DEPTH;

    // crossbar（APB 扇出）互连
    wire [`C1_APB_SLV_NUM-1:0]              slot_ret_valid;
    wire [`C1_APB_SLV_NUM*`C1_CR_CNT_W-1:0] slot_ret_cnt;
    wire [`C1_APB_SLV_NUM-1:0]              slot_active;
    wire [`C1_MON_CNT_W-1:0]                xbar_txn_cnt;
    wire                                    xbar_busy;

    // 归还 FIFO
    wire [`C1_CDC_BUS_W-1:0]     ret_din;
    wire [`C1_CDC_BUS_W-1:0]     ret_dout;
    wire                         ret_push;
    wire                         ret_ready;
    wire                         ret_pop_valid;
    wire [`C1_FIFO_CNT_W-1:0]    ret_level;
    wire                         ret_empty;
    wire                         ret_full;
    wire                         ret_afull;
    wire                         ret_ae;
    wire                         ret_pop_ready;

    // per-class credit 计数
    reg  [`C1_CR_CNT_W-1:0]      class_cnt [0:`C1_CR_CLASS_NUM-1];
    reg  [`C1_MON_CNT_W-1:0]     issued_cnt_r;
    reg  [`C1_CR_CNT_W-1:0]      slot_ret_sum;
    wire [`C1_CR_CNT_W-1:0]      class_sel;
    wire                         credit_room;
    integer                      c;

    //------------------------------------------------------------------
    // slot 归还数量求和 → 压入归还 FIFO
    //------------------------------------------------------------------
    always @(*) begin
        slot_ret_sum = {`C1_CR_CNT_W{1'b0}};
        for (c = 0; c < `C1_APB_SLV_NUM; c = c + 1) begin
            slot_ret_sum = slot_ret_sum +
                           slot_ret_cnt[c*`C1_CR_CNT_W +: `C1_CR_CNT_W];
        end
    end

    assign ret_push  = slot_ret_valid[0] | slot_ret_valid[1] |
                       slot_ret_valid[2] | slot_ret_valid[3];
    assign ret_din   = {{(`C1_CDC_BUS_W-`C1_CR_CNT_W){1'b0}}, slot_ret_sum};
    assign RET_VALID = ret_pop_valid;
    assign RET_CNT   = ret_dout[`C1_CR_CNT_W-1:0];

    // FIFO 弹出由 AHB 侧的归还握手确认
    assign ret_pop_ready = CR_RET_VALID;

    case1_sync_fifo #(
        .DEPTH (`C1_CR_RET_BUF_DEPTH),
        .ASYNC (0)
    ) u_ret_fifo (
        .CLK          (PCLK),
        .RST_N        (PRESETn),
        .DIN          (ret_din),
        .DIN_VALID    (ret_push),
        .DIN_READY    (ret_ready),
        .DOUT         (ret_dout),
        .DOUT_VALID   (ret_pop_valid),
        .DOUT_READY   (ret_pop_ready),
        .FLUSH        (1'b0),
        .FIFO_LEVEL   (ret_level),
        .FIFO_EMPTY   (ret_empty),
        .FIFO_FULL    (ret_full),
        .FIFO_AFULL   (ret_afull),
        .FIFO_AE      (ret_ae)
    );

    //------------------------------------------------------------------
    // 链路请求 / 已发起统计
    //------------------------------------------------------------------
    assign class_sel = {{(`C1_CR_CNT_W-`C1_CR_CLASS_AW){1'b0}},
                        REQ_ADDR[`C1_CR_CLASS_AW-1:0]};
    assign CR_REQ    = REQ_VALID && credit_room;
    assign CR_ISSUED = issued_cnt_r;
    assign WM_LOW    = (class_cnt[0] <= `C1_CR_LOW_WM);
    assign WM_HIGH   = (class_cnt[0] >= `C1_CR_HIGH_WM);
    assign RET_FIFO_EMPTY = ret_empty;
    assign RET_FIFO_FULL  = ret_full;
    assign credit_room    = (class_cnt[0] < `C1_CR_MAX);

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            issued_cnt_r <= {`C1_MON_CNT_W{1'b0}};
            for (c = 0; c < `C1_CR_CLASS_NUM; c = c + 1) begin
                class_cnt[c] <= {`C1_CR_CNT_W{1'b0}};
            end
        end else begin
            if (REQ_VALID && credit_room) begin
                class_cnt[class_sel] <= class_cnt[class_sel] + 1'b1;
                issued_cnt_r         <= issued_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
            end
            if (ret_push && (class_cnt[class_sel] != {`C1_CR_CNT_W{1'b0}})) begin
                class_cnt[class_sel] <= class_cnt[class_sel] - 1'b1;
            end
            if (CR_RET_VALID && (class_cnt[class_sel] != {`C1_CR_CNT_W{1'b0}})) begin
                class_cnt[class_sel] <= class_cnt[class_sel] - CR_RET_CNT;
            end
        end
    end

    //------------------------------------------------------------------
    // APB 扇出（crossbar + slot 阵列 + CDC）
    //------------------------------------------------------------------
    case1_apb_crossbar #(
        .SLOT_NUM     (`C1_APB_SLV_NUM),
        .SYNC_STAGES  (`C1_CDC_STAGES)
    ) u_crossbar (
        .PCLK              (PCLK),
        .PRESETn           (PRESETn),
        .HCLK              (HCLK),
        .HRESETn           (HRESETn),
        .REQ_ADDR          (REQ_ADDR),
        .REQ_WRITE         (REQ_WRITE),
        .REQ_WDATA         (REQ_WDATA),
        .REQ_STRB          (REQ_STRB),
        .REQ_PROT          (REQ_PROT),
        .REQ_VALID         (REQ_VALID),
        .PSEL              (PSEL),
        .PRDATA            (PRDATA),
        .PREADY            (PREADY),
        .PSLVERR           (PSLVERR),
        .SLOT_CR_RET_VALID (slot_ret_valid),
        .SLOT_CR_RET_CNT   (slot_ret_cnt),
        .SLOT_ACTIVE       (slot_active),
        .XBAR_TXN_CNT      (xbar_txn_cnt),
        .XBAR_BUSY         (xbar_busy)
    );

endmodule
