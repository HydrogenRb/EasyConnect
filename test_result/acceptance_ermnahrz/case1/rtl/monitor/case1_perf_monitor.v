//==========================================================================
//  case1_perf_monitor.v
//  SoC 性能监视器：事务计数 / 空闲周期 / credit 水位 / 总线占用
//
//  HCLK 域统计两个主机的 busy 与事务计数、互连 credit 水位；统计结果经
//  for-generate 例化的 case1_gray_sync u_dbg_sync[k] 同步到 PCLK 域供
//  调试读出；内部再挂一个 case1_cpu_tracker_rv32 u_bus_track 做总线侧
//  在途事务跟踪（与 master wrap 里的 tracker 是同一模块的不同实例）。
//
//  Ref: SoC performance monitor / bus monitor（事务计数 + 延迟统计 +
//       跨时钟域调试读出）。
//==========================================================================
`include "case1_define.v"

module case1_perf_monitor (
    input  wire                                        HCLK,
    input  wire                                        PCLK,
    input  wire                                        HRESETn,
    input  wire                                        PRESETn,
    input  wire [`C1_AHB_MASTER_NUM-1:0]               M_BUSY,
    input  wire [`C1_AHB_MASTER_NUM*`C1_CR_CNT_W-1:0]  M_CREDIT_LEVEL,
    input  wire [`C1_AHB_MASTER_NUM*`C1_MON_CNT_W-1:0] M_TXN_CNT,
    input  wire [`C1_MON_CNT_W-1:0]                    XBAR_CREDIT_STAT,
    input  wire                                        XBAR_IDLE,
    output wire [`C1_MON_CNT_W-1:0]                    MON_TXN_CNT,
    output wire                                        MON_IDLE,
    output wire [`C1_MON_CNT_W-1:0]                    DBG_CREDIT_STAT
);

    parameter EVT_FIFO_DEPTH = `C1_CR_RET_BUF_DEPTH;

    reg  [`C1_MON_CNT_W-1:0]  txn_cnt_r;
    reg  [`C1_MON_CNT_W-1:0]  idle_cnt_r;
    reg  [`C1_MON_CNT_W-1:0]  stall_cnt_r;
    reg  [`C1_MON_CNT_W-1:0]  credit_stat_r;
    reg  [`C1_MON_CNT_W-1:0]  txn_sum_r;
    reg  [`C1_MON_CNT_W-1:0]  credit_sum_r;
    reg                       idle_r;
    integer                   mi;

    // 总线侧 tracker（同一模块在 master wrap 里也有一个实例）
    wire [`C1_AHB_ADDR_W-1:0]  bus_trk_addr;
    wire                       bus_trk_write;
    wire                       bus_trk_valid;
    wire [`C1_TXN_ID_W-1:0]    bus_trk_id;
    wire [`C1_MON_CNT_W-1:0]   bus_trk_cnt;
    wire                       bus_trk_full;

    // 调试计数器跨到 PCLK 域的格雷码同步链
    wire [`C1_GRAY_W-1:0]      gray_chain [0:`C1_CDC_STAGES];
    wire [`C1_GRAY_W-1:0]      gray_bin   [0:`C1_CDC_STAGES-1];

    assign gray_chain[0] = txn_cnt_r[`C1_GRAY_W-1:0];

    genvar k;
    generate
        for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_dbg_sync
            case1_gray_sync u_dbg_sync[k] (
                HCLK,
                HRESETn,
                PCLK,
                PRESETn,
                gray_chain[k],
                gray_chain[k+1],
                gray_bin[k]
            );
        end
    endgenerate

    case1_cpu_tracker_rv32 #(
        .TRACK_DEPTH (`C1_TRACKER_DEPTH),
        .CPU_ID      (1)
    ) u_bus_track (
        .HCLK        (HCLK),
        .HRESETn     (HRESETn),
        .PC_ADDR     (M_TXN_CNT[`C1_AHB_ADDR_W-1:0]),
        .RETIRE_VALID(M_BUSY[0]),
        .TXN_DONE    (XBAR_IDLE),
        .TXN_ADDR    (bus_trk_addr),
        .TXN_WRITE   (bus_trk_write),
        .TXN_VALID   (bus_trk_valid),
        .TXN_ID      (bus_trk_id),
        .TRACK_CNT   (bus_trk_cnt),
        .TRACK_FULL  (bus_trk_full)
    );

    //------------------------------------------------------------------
    // 事务 / 空闲 / credit 水位统计
    //------------------------------------------------------------------
    always @(*) begin
        txn_sum_r    = {`C1_MON_CNT_W{1'b0}};
        credit_sum_r = {`C1_MON_CNT_W{1'b0}};
        for (mi = 0; mi < `C1_AHB_MASTER_NUM; mi = mi + 1) begin
            txn_sum_r    = txn_sum_r +
                           M_TXN_CNT[mi*`C1_MON_CNT_W +: `C1_MON_CNT_W];
            credit_sum_r = credit_sum_r +
                           {{(`C1_MON_CNT_W-`C1_CR_CNT_W){1'b0}},
                            M_CREDIT_LEVEL[mi*`C1_CR_CNT_W +: `C1_CR_CNT_W]};
        end
    end

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            txn_cnt_r     <= {`C1_MON_CNT_W{1'b0}};
            idle_cnt_r    <= {`C1_MON_CNT_W{1'b0}};
            stall_cnt_r   <= {`C1_MON_CNT_W{1'b0}};
            credit_stat_r <= {`C1_MON_CNT_W{1'b0}};
            idle_r        <= 1'b1;
        end else begin
            txn_cnt_r <= txn_sum_r + bus_trk_cnt;
            if (XBAR_IDLE && (M_BUSY == {`C1_AHB_MASTER_NUM{1'b0}})) begin
                idle_cnt_r <= idle_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                idle_r     <= 1'b1;
            end else begin
                idle_r <= 1'b0;
            end
            if (M_BUSY != {`C1_AHB_MASTER_NUM{1'b0}}) begin
                stall_cnt_r <= stall_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
            end
            if (credit_sum_r <= `C1_CR_LOW_WM) begin
                credit_stat_r <= XBAR_CREDIT_STAT;
            end else begin
                credit_stat_r <= credit_sum_r;
            end
        end
    end

    assign MON_TXN_CNT     = txn_cnt_r;
    assign MON_IDLE        = idle_r;
    assign DBG_CREDIT_STAT = credit_stat_r;

endmodule
