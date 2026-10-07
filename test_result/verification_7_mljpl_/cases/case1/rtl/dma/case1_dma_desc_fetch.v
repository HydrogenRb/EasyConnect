//==========================================================================
//  case1_dma_desc_fetch.v
//  DMA 描述符预取器：描述符缓冲放在库单元 RAM_SP 里
//
//  每个通道一个实例（在 case1_dma_engine 里用 for-generate 例化 4 个），
//  按 DESC_REQ 从 RAM_SP 缓冲里取 64bit 描述符（拆成两个 32bit 半字），
//  并把 credit 消耗/归还透传给上游通道逻辑。
//
//  Ref: DMAC 的 descriptor fetch / microcode prefetch 单元 +
//       credit-based 链路的发送侧计数。
//==========================================================================
`include "case1_define.v"

module case1_dma_desc_fetch (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          CH_ENABLE,
    input  wire                          DESC_REQ,
    output wire [`C1_AHB_ADDR_W-1:0]     DESC_ADDR,
    output wire [`C1_AHB_DATA_W-1:0]     DESC_RDATA,
    output wire                          FETCH_BUSY,
    input  wire [`C1_CR_CNT_W-1:0]       CREDIT_IN,
    input  wire                          CREDIT_VALID,
    output wire [`C1_CR_CNT_W-1:0]       CREDIT_ISSUED,

    output wire ec_debug // EasyConnect 1.0 验收
);

    parameter DESC_DEPTH    = `C1_CR_RET_BUF_DEPTH;
    parameter FETCH_LATENCY = 4;

    reg  [`C1_FIFO_PTR_W-1:0]   desc_ptr;
    reg  [`C1_CR_CNT_W-1:0]     issued_r;
    reg  [`C1_CR_TIMEOUT_W-1:0] latency_cnt;
    reg                         fetch_busy_r;
    reg  [`C1_AHB_DATA_W-1:0]   rdata_r;
    reg  [`C1_AHB_DATA_W-1:0]   desc_hi_r;
    integer                     d;

    // 描述符缓冲：库单元 RAM_SP（叶子，位置连接）
    wire [`C1_RAM_ADDR_W-1:0]  buf_addr;
    wire [`C1_RAM_DATA_W-1:0]  buf_d;
    wire [`C1_RAM_DATA_W-1:0]  buf_q;
    wire [`C1_RAM_BEN_W-1:0]   buf_ben;

    reg [`C1_REG_DATA_W-1:0]   desc_mem [0:`C1_CR_RET_BUF_DEPTH-1];

    assign buf_addr = {{(`C1_RAM_ADDR_W-`C1_FIFO_PTR_W){1'b0}}, desc_ptr};
    assign buf_d    = desc_mem[desc_ptr[`C1_CR_RET_PTR_W-1:0]];
    assign buf_ben  = {`C1_RAM_BEN_W{1'b0}};

    RAM_SP u_desc_buf (HCLK, 1'b0, 1'b1, buf_ben, buf_addr, buf_d, buf_q);

    assign DESC_ADDR    = {{(`C1_AHB_ADDR_W-`C1_FIFO_PTR_W){1'b0}}, desc_ptr};
    assign DESC_RDATA   = rdata_r;
    assign FETCH_BUSY   = fetch_busy_r;
    assign CREDIT_ISSUED = issued_r;

    initial begin
        for (d = 0; d < `C1_CR_RET_BUF_DEPTH; d = d + 1) begin
            desc_mem[d] = {`C1_REG_DATA_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 预取状态机
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            desc_ptr      <= {`C1_FIFO_PTR_W{1'b0}};
            issued_r      <= {`C1_CR_CNT_W{1'b0}};
            latency_cnt   <= {`C1_CR_TIMEOUT_W{1'b0}};
            fetch_busy_r  <= 1'b0;
            rdata_r       <= {`C1_AHB_DATA_W{1'b0}};
            desc_hi_r     <= {`C1_AHB_DATA_W{1'b0}};
        end else if (CH_ENABLE == 1'b0) begin
            fetch_busy_r <= 1'b0;
            latency_cnt  <= {`C1_CR_TIMEOUT_W{1'b0}};
        end else if (DESC_REQ && (CREDIT_VALID == 1'b1) && (fetch_busy_r == 1'b0)) begin
            fetch_busy_r <= 1'b1;
            if (issued_r == `C1_CR_MAX) begin
                issued_r <= {`C1_CR_CNT_W{1'b0}};
            end else begin
                issued_r <= issued_r + 1'b1;
            end
        end else if (fetch_busy_r == 1'b1) begin
            if (latency_cnt >= FETCH_LATENCY) begin
                fetch_busy_r <= 1'b0;
                latency_cnt  <= {`C1_CR_TIMEOUT_W{1'b0}};
                rdata_r      <= buf_q;
                desc_hi_r    <= desc_mem[desc_ptr[`C1_CR_RET_PTR_W-1:0]];
                desc_ptr     <= desc_ptr + 1'b1;
            end else begin
                latency_cnt <= latency_cnt + 1'b1;
            end
        end
    end

endmodule
