//==========================================================================
//  case1_apb_crossbar.v
//  APB 扇出：slot 选择 + 响应回选 + CDC 同步器阵列 + slot 阵列
//
//  结构要点（分析器最关心的部分）：
//    · 两级嵌套 for-generate：for (s) for (k) 例化 CDC 同步触发器链
//      u_ready_sync[s*`C1_CDC_STAGES+k]（每 slot、每级一个）
//    · case1_apb_cdc u_cdc：per-slot PCLK→HCLK 同步器组（gray + pulse）
//    · for (s) 例化 `C1_APB_SLV_NUM 个 case1_apb_periph_slot u_slot[s]
//
//  Ref: APB 子系统交叉开关（PSEL 译码 + PRDATA/PREADY 回选）+
//       多级 CDC 同步器阵列（每 slot 每信号独立同步）。
//==========================================================================
`include "case1_define.v"

module case1_apb_crossbar (
    input  wire                                    PCLK,
    input  wire                                    PRESETn,
    input  wire                                    HCLK,
    input  wire                                    HRESETn,
    input  wire [`C1_APB_ADDR_W-1:0]               REQ_ADDR,
    input  wire                                    REQ_WRITE,
    input  wire [`C1_APB_DATA_W-1:0]               REQ_WDATA,
    input  wire [`C1_APB_STRB_W-1:0]               REQ_STRB,
    input  wire [`C1_APB_PROT_W-1:0]               REQ_PROT,
    input  wire                                    REQ_VALID,
    output wire [`C1_APB_SLV_NUM-1:0]              PSEL,
    output wire [`C1_APB_DATA_W-1:0]               PRDATA,
    output wire                                    PREADY,
    output wire                                    PSLVERR,
    output wire [`C1_APB_SLV_NUM-1:0]              SLOT_CR_RET_VALID,
    output wire [`C1_APB_SLV_NUM*`C1_CR_CNT_W-1:0] SLOT_CR_RET_CNT,
    output wire [`C1_APB_SLV_NUM-1:0]              SLOT_ACTIVE,
    output wire [`C1_MON_CNT_W-1:0]                XBAR_TXN_CNT,
    output wire                                    XBAR_BUSY
);

    parameter SLOT_NUM    = `C1_APB_SLV_NUM;
    parameter SYNC_STAGES = `C1_CDC_STAGES;

    //------------------------------------------------------------------
    // slot 选择
    //------------------------------------------------------------------
    wire [`C1_APB_SLV_AW-1:0] slot_idx;
    reg  [`C1_APB_SLV_NUM-1:0] psel_r;

    assign slot_idx = REQ_ADDR[`C1_APB_SLOT_LSB+`C1_APB_SLV_AW-1:`C1_APB_SLOT_LSB];
    assign PSEL     = psel_r;

    always @(*) begin
        psel_r = {`C1_APB_SLV_NUM{1'b0}};
        if (REQ_VALID) begin
            case (slot_idx)
                `C1_SLV0_IDX: psel_r = `C1_HSEL_SLV0;
                `C1_SLV1_IDX: psel_r = `C1_HSEL_SLV1;
                `C1_SLV2_IDX: psel_r = `C1_HSEL_SLV2;
                default:      psel_r = `C1_HSEL_SLV3;
            endcase
        end
    end

    //------------------------------------------------------------------
    // per-slot APB 总线与状态
    //------------------------------------------------------------------
    wire [`C1_APB_ADDR_W-1:0]  slot_paddr      [0:`C1_APB_SLV_NUM-1];
    wire [`C1_APB_DATA_W-1:0]  slot_pwdata     [0:`C1_APB_SLV_NUM-1];
    wire [`C1_APB_STRB_W-1:0]  slot_pstrb      [0:`C1_APB_SLV_NUM-1];
    wire [`C1_APB_PROT_W-1:0]  slot_pprot      [0:`C1_APB_SLV_NUM-1];
    wire                       slot_penable    [0:`C1_APB_SLV_NUM-1];
    wire                       slot_pwrite     [0:`C1_APB_SLV_NUM-1];
    wire [`C1_APB_DATA_W-1:0]  slot_prdata     [0:`C1_APB_SLV_NUM-1];
    wire                       slot_pready     [0:`C1_APB_SLV_NUM-1];
    wire                       slot_pslverr    [0:`C1_APB_SLV_NUM-1];
    wire                       slot_active     [0:`C1_APB_SLV_NUM-1];
    wire                       slot_ret_valid  [0:`C1_APB_SLV_NUM-1];
    wire [`C1_CR_CNT_W-1:0]    slot_ret_cnt    [0:`C1_APB_SLV_NUM-1];
    wire [`C1_MON_CNT_W-1:0]   slot_txn_cnt    [0:`C1_APB_SLV_NUM-1];
    wire                       slot_irq        [0:`C1_APB_SLV_NUM-1];

    wire [`C1_APB_SLV_NUM-1:0] slot_active_bit;
    wire [`C1_APB_SLV_NUM-1:0] slot_active_sync;
    wire [`C1_APB_SLV_NUM-1:0] slot_ret_pulse;
    wire [`C1_GRAY_W-1:0]      gray_ptr_pclk;
    wire [`C1_GRAY_W-1:0]      gray_ptr_hclk;
    wire                       cdc_ready;
    wire                       cdc_not_ready;

    // 每 slot、每级一个同步触发器（两级嵌套 for-generate）
    wire [`C1_APB_SLV_NUM-1:0] slot_ready_chain [0:`C1_CDC_STAGES];

    //------------------------------------------------------------------
    // slot 阵列 + 嵌套 CDC 触发器等例化
    //------------------------------------------------------------------
    genvar s;
    genvar k;
    generate
        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_slot
            case1_apb_periph_slot #(
                .SLOT_IDX    (s),
                .PERIPH_TYPE (s)
            ) u_slot[s] (
                .PCLK         (PCLK),
                .PRESETn      (PRESETn),
                .HCLK         (HCLK),
                .HRESETn      (HRESETn),
                .PADDR        (slot_paddr[s]),
                .PSEL         (psel_r[s]),
                .PENABLE      (slot_penable[s]),
                .PWRITE       (slot_pwrite[s]),
                .PWDATA       (slot_pwdata[s]),
                .PSTRB        (slot_pstrb[s]),
                .PPROT        (slot_pprot[s]),
                .PRDATA       (slot_prdata[s]),
                .PREADY       (slot_pready[s]),
                .PSLVERR      (slot_pslverr[s]),
                .SLOT_ACTIVE  (slot_active[s]),
                .CR_RET_VALID (slot_ret_valid[s]),
                .CR_RET_CNT   (slot_ret_cnt[s]),
                .SLOT_TXN_CNT (slot_txn_cnt[s]),
                .SLOT_IRQ     (slot_irq[s])
            );

            assign slot_paddr[s]        = REQ_ADDR;
            assign slot_penable[s]      = REQ_VALID;
            assign slot_pwrite[s]       = REQ_WRITE;
            assign slot_pwdata[s]       = REQ_WDATA;
            assign slot_pstrb[s]        = REQ_STRB;
            assign slot_pprot[s]        = REQ_PROT;
            assign slot_active_bit[s]   = slot_active[s];
            assign SLOT_CR_RET_VALID[s] = slot_ret_valid[s];
            assign SLOT_CR_RET_CNT[s*`C1_CR_CNT_W +: `C1_CR_CNT_W] = slot_ret_cnt[s];
        end

        // for (s) for (k)：CDC 同步触发器链，把 slot 的 PREADY 同步到 HCLK 域
        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_ready_chain_in
            assign slot_ready_chain[0][s] = slot_pready[s];
        end

        for (s = 0; s < `C1_APB_SLV_NUM; s = s + 1) begin : g_ready_sync
            for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_stage
                case1_sync_ff u_ready_sync[s*`C1_CDC_STAGES+k] (
                    .CLK   (HCLK),
                    .RST_N (HRESETn),
                    .D_IN  (slot_ready_chain[k][s]),
                    .D_OUT (slot_ready_chain[k+1][s])
                );
            end
        end
    endgenerate

    assign gray_ptr_pclk = XBAR_TXN_CNT[`C1_GRAY_W-1:0];
    assign cdc_not_ready = ~cdc_ready;

    //------------------------------------------------------------------
    // per-slot PCLK→HCLK 同步器组（gray + pulse + 触发器阵列）
    //------------------------------------------------------------------
    case1_apb_cdc u_cdc (
        .PCLK              (PCLK),
        .PRESETn           (PRESETn),
        .HCLK              (HCLK),
        .HRESETn           (HRESETn),
        .SLOT_ACTIVE       (slot_active_bit),
        .SLOT_CR_RET_VALID (SLOT_CR_RET_VALID),
        .SLOT_CR_RET_CNT   (SLOT_CR_RET_CNT),
        .GRAY_PTR_PCLK     (gray_ptr_pclk),
        .SLOT_ACTIVE_SYNC  (slot_active_sync),
        .SLOT_RET_PULSE    (slot_ret_pulse),
        .GRAY_PTR_HCLK     (gray_ptr_hclk),
        .CDC_READY         (cdc_ready)
    );

    //------------------------------------------------------------------
    // 响应回选（PRDATA / PREADY / PSLVERR）+ 统计
    //------------------------------------------------------------------
    reg [`C1_APB_DATA_W-1:0]  rsp_prdata;
    reg                       rsp_pready;
    reg                       rsp_pslverr;
    reg [`C1_MON_CNT_W-1:0]   txn_sum;
    reg                       active_any;
    integer                   q;

    always @(*) begin
        rsp_prdata  = {`C1_APB_DATA_W{1'b0}};
        rsp_pready  = 1'b0;
        rsp_pslverr = 1'b0;
        txn_sum     = {`C1_MON_CNT_W{1'b0}};
        active_any  = 1'b0;
        for (q = 0; q < `C1_APB_SLV_NUM; q = q + 1) begin
            if (psel_r[q]) begin
                rsp_prdata  = slot_prdata[q];
                rsp_pready  = slot_pready[q];
                rsp_pslverr = slot_pslverr[q];
            end
            txn_sum    = txn_sum + slot_txn_cnt[q];
            active_any = active_any | slot_active[q];
        end
    end

    assign PRDATA       = rsp_prdata;
    assign PREADY       = rsp_pready;
    assign PSLVERR      = rsp_pslverr;
    assign XBAR_TXN_CNT = txn_sum;
    assign XBAR_BUSY    = active_any | cdc_not_ready;
    assign SLOT_ACTIVE  = slot_active_bit;

endmodule
