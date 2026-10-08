//==========================================================================
//  case1_apb_cdc.v
//  per-slot PCLK → HCLK 同步器组（gray 同步器阵列 + 脉冲同步器 + 触发器链）
//
//  每个 APB slot 的 active / 归还脉冲 / credit 指针都要跨回 HCLK 域：
//    · case1_gray_sync  ×`C1_CDC_STAGES   —— 多 bit 指针走格雷码逐级同步
//    · case1_pulse_sync ×`C1_APB_SLV_NUM  —— 单 bit 归还脉冲
//    · 两级嵌套 for-generate 的 case1_sync_ff 链 —— 逐级触发器阵列
//
//  Ref: 多时钟域同步器阵列（2-FF synchronizer、gray-code pointer crossing、
//       pulse synchronizer），例如 async FIFO 指针同步与桥的握手同步。
//==========================================================================
`include "case1_define.v"

module case1_apb_cdc (
    input  wire                                    PCLK,
    input  wire                                    PRESETn,
    input  wire                                    HCLK,
    input  wire                                    HRESETn,
    input  wire [`C1_APB_SLV_NUM-1:0]              SLOT_ACTIVE,
    input  wire [`C1_APB_SLV_NUM-1:0]              SLOT_CR_RET_VALID,
    input  wire [`C1_APB_SLV_NUM*`C1_CR_CNT_W-1:0] SLOT_CR_RET_CNT,
    input  wire [`C1_GRAY_W-1:0]                   GRAY_PTR_PCLK,
    output wire [`C1_APB_SLV_NUM-1:0]              SLOT_ACTIVE_SYNC,
    output wire [`C1_APB_SLV_NUM-1:0]              SLOT_RET_PULSE,
    output wire [`C1_GRAY_W-1:0]                   GRAY_PTR_HCLK,
    output wire                                    CDC_READY
);

    parameter SLOT_NUM    = `C1_APB_SLV_NUM;
    parameter SYNC_STAGES = `C1_CDC_STAGES;

    // 触发器链（索引 0 = 原始输入，1..SYNC_STAGES = 逐级输出）
    wire [`C1_APB_SLV_NUM-1:0] active_chain [0:`C1_CDC_STAGES];
    wire [`C1_GRAY_W-1:0]      gray_chain   [0:`C1_CDC_STAGES];
    wire [`C1_GRAY_W-1:0]      gray_bin     [0:`C1_CDC_STAGES-1];
    reg  [`C1_CDC_STAGES:0]    ready_cnt;
    integer                    z;

    assign GRAY_PTR_HCLK = gray_chain[`C1_CDC_STAGES];
    assign CDC_READY     = (ready_cnt >= `C1_CDC_STAGES);

    genvar s;
    genvar k;
    generate
        // slot 级：active 触发器链（for (s) for (k) 两级嵌套）
        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_active_in
            assign active_chain[0][s] = SLOT_ACTIVE[s];
        end

        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_active_sync
            for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_stage
                case1_sync_ff u_active_ff[s*`C1_CDC_STAGES+k] (
                    .CLK   (HCLK),
                    .RST_N (HRESETn),
                    .D_IN  (active_chain[k][s]),
                    .D_OUT (active_chain[k+1][s])
                );
            end
        end

        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_active_out
            assign SLOT_ACTIVE_SYNC[s] = active_chain[`C1_CDC_STAGES][s];
        end

        // slot 级：归还脉冲同步（位置连接的小叶子）
        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_pulse_sync
            case1_pulse_sync u_pulse[s] (
                PCLK,
                PRESETn,
                HCLK,
                HRESETn,
                SLOT_CR_RET_VALID[s],
                SLOT_RET_PULSE[s]
            );
        end

        // 指针级：格雷码同步器链
        for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_gray_sync
            case1_gray_sync u_gray[k] (
                PCLK,
                PRESETn,
                HCLK,
                HRESETn,
                (k == 0) ? GRAY_PTR_PCLK : gray_chain[k],
                gray_chain[k+1],
                gray_bin[k]
            );
        end
    endgenerate

    //------------------------------------------------------------------
    // 同步器就绪计数（复位后经过 `C1_CDC_STAGES 拍才认为 CDC 可用）
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ready_cnt <= {(`C1_CDC_STAGES+1){1'b0}};
        end else if (ready_cnt < `C1_CDC_STAGES) begin
            ready_cnt <= ready_cnt + 1'b1;
        end
    end

endmodule
