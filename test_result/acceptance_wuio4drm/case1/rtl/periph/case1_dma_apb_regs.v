//==========================================================================
//  case1_dma_apb_regs.v
//  DMA 通道的 APB 配置寄存器组（叶子模块，内部无任何例化）
//
//  寄存器：CH_EN / SRC_ADDR / DST_ADDR / LEN / CTRL / STATUS / DESC_PTR
//  每个通道一组影子寄存器，供 rtl/dma/case1_dma_engine.v 读取。
//
//  Ref: DMAC（PL330 风格）通道配置寄存器组（APB 外设叶子）。
//==========================================================================
`include "case1_define.v"

module case1_dma_apb_regs (
    input  wire                          PCLK,
    input  wire                          PRESETn,
    input  wire [`C1_REG_ADDR_W-1:0]     REG_ADDR,
    input  wire [`C1_REG_DATA_W-1:0]     REG_WDATA,
    input  wire                          REG_WR_EN,
    input  wire                          REG_RD_EN,
    output reg  [`C1_REG_DATA_W-1:0]     REG_RDATA,
    output reg  [`C1_MON_CNT_W-1:0]      REG_TXN_CNT,
    output reg                           REG_IRQ
);

    parameter BASE_ADDR = `C1_PERIPH_BASE;

    reg [`C1_DMA_CH_AW-1:0]    ch_sel;
    reg [`C1_DMA_CH_NUM-1:0]   ch_en;
    reg [`C1_REG_DATA_W-1:0]   ch_ctrl    [0:`C1_DMA_CH_NUM-1];
    reg [`C1_DMA_SRC_W-1:0]    ch_src     [0:`C1_DMA_CH_NUM-1];
    reg [`C1_DMA_DST_W-1:0]    ch_dst     [0:`C1_DMA_CH_NUM-1];
    reg [`C1_DMA_LEN_W-1:0]    ch_len     [0:`C1_DMA_CH_NUM-1];
    reg [`C1_REG_DATA_W-1:0]   ch_stat    [0:`C1_DMA_CH_NUM-1];
    reg [`C1_DMA_DESC_W-1:0]   ch_desc    [0:`C1_DMA_CH_NUM-1];
    reg [`C1_MON_CNT_W-1:0]    ch_txn_cnt [0:`C1_DMA_CH_NUM-1];
    reg [`C1_CR_TIMEOUT_W-1:0] arb_cnt;
    integer                    c;

    assign ch_sel = REG_ADDR[`C1_DMA_CH_AW-1:0];

    //------------------------------------------------------------------
    // 通道影子寄存器
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ch_en    <= {`C1_DMA_CH_NUM{1'b0}};
            arb_cnt  <= {`C1_CR_TIMEOUT_W{1'b0}};
            for (c = 0; c < `C1_DMA_CH_NUM; c = c + 1) begin
                ch_ctrl[c]    <= {`C1_REG_DATA_W{1'b0}};
                ch_src[c]     <= {`C1_DMA_SRC_W{1'b0}};
                ch_dst[c]     <= {`C1_DMA_DST_W{1'b0}};
                ch_len[c]     <= {`C1_DMA_LEN_W{1'b0}};
                ch_stat[c]    <= {`C1_REG_DATA_W{1'b0}};
                ch_desc[c]    <= {`C1_DMA_DESC_W{1'b0}};
                ch_txn_cnt[c] <= {`C1_MON_CNT_W{1'b0}};
            end
        end else begin
            arb_cnt <= arb_cnt + 1'b1;
            if (REG_WR_EN) begin
                case (REG_ADDR[`C1_REG_IDX_MSB:`C1_DMA_CH_AW])
                    4'h0: begin
                        ch_ctrl[ch_sel] <= REG_WDATA;
                        ch_en[ch_sel]   <= REG_WDATA[0];
                    end
                    4'h1: ch_src[ch_sel]  <= REG_WDATA[`C1_DMA_SRC_W-1:0];
                    4'h2: ch_dst[ch_sel]  <= REG_WDATA[`C1_DMA_DST_W-1:0];
                    4'h3: ch_len[ch_sel]  <= REG_WDATA[`C1_DMA_LEN_W-1:0];
                    4'h4: ch_stat[ch_sel] <= REG_WDATA;
                    4'h5: ch_desc[ch_sel][`C1_REG_DATA_W-1:0] <= REG_WDATA;
                    default: ch_ctrl[ch_sel] <= ch_ctrl[ch_sel];
                endcase
            end else if (REG_RD_EN) begin
                case (REG_ADDR[`C1_REG_IDX_MSB:`C1_DMA_CH_AW])
                    4'h0: REG_RDATA <= ch_ctrl[ch_sel];
                    4'h1: REG_RDATA <= ch_src[ch_sel];
                    4'h2: REG_RDATA <= ch_dst[ch_sel];
                    4'h3: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_DMA_LEN_W){1'b0}},
                                        ch_len[ch_sel]};
                    4'h4: REG_RDATA <= ch_stat[ch_sel];
                    4'h5: REG_RDATA <= ch_desc[ch_sel][`C1_REG_DATA_W-1:0];
                    default: REG_RDATA <= {{(`C1_REG_DATA_W-`C1_MON_CNT_W){1'b0}},
                                           ch_txn_cnt[ch_sel]};
                endcase
            end

            for (c = 0; c < `C1_DMA_CH_NUM; c = c + 1) begin
                if (ch_en[c] && (arb_cnt == {`C1_CR_TIMEOUT_W{1'b0}})) begin
                    ch_txn_cnt[c] <= ch_txn_cnt[c] + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                    ch_stat[c][0] <= (ch_len[c] == {`C1_DMA_LEN_W{1'b0}});
                end
            end

            REG_IRQ <= |(ch_stat[0][0] | ch_stat[1][0] |
                        ch_stat[2][0] | ch_stat[3][0]);
        end
    end

    //------------------------------------------------------------------
    // 读写计数与读数据寄存
    //------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            REG_TXN_CNT <= {`C1_MON_CNT_W{1'b0}};
        end else if (REG_WR_EN || REG_RD_EN) begin
            REG_TXN_CNT <= REG_TXN_CNT + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
        end
    end

endmodule
