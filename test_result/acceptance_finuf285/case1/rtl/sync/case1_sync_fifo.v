//==========================================================================
//  case1_sync_fifo.v
//  通用 FWFT 同步 FIFO（存储用库单元 RAM_SP_BE），带异步变体
//
//  ASYNC = 0：读写同域，普通同步 FIFO；
//  ASYNC = 1：读写域不同，指针经 case1_gray_sync 逐级同步（generate-if +
//             for-generate 例化 `C1_CDC_STAGES 级格雷码同步器）。
//
//  Ref: 异步/同步 FIFO 宏（RAM_SP_BE 存储 + 格雷码指针同步），
//       例如 AFIFO / sync_fifo 生成器输出。
//==========================================================================
`include "case1_define.v"

module case1_sync_fifo (
    input  wire                          CLK,
    input  wire                          RST_N,
    input  wire [`C1_CDC_BUS_W-1:0]      DIN,
    input  wire                          DIN_VALID,
    output wire                          DIN_READY,
    output wire [`C1_CDC_BUS_W-1:0]      DOUT,
    output wire                          DOUT_VALID,
    input  wire                          DOUT_READY,
    input  wire                          FLUSH,
    output wire [`C1_FIFO_CNT_W-1:0]     FIFO_LEVEL,
    output wire                          FIFO_EMPTY,
    output wire                          FIFO_FULL,
    output wire                          FIFO_AFULL,
    output wire                          FIFO_AE
);

    parameter DEPTH = `C1_FIFO_DEPTH;
    parameter ASYNC = 0;

    reg  [`C1_FIFO_PTR_W-1:0]  wptr_r;
    reg  [`C1_FIFO_PTR_W-1:0]  rptr_r;
    reg  [`C1_FIFO_CNT_W-1:0]  level_r;
    reg                        full_r;
    reg                        empty_r;

    wire                       push;
    wire                       pop;
    wire                       full_n;
    wire                       empty_n;
    wire [`C1_RAM_ADDR_W-1:0]  ram_addr;
    wire [`C1_RAM_DATA_W-1:0]  ram_din;
    wire [`C1_RAM_DATA_W-1:0]  ram_dout;
    wire [`C1_RAM_BEN_W-1:0]   ram_ben;
    wire                       ram_cen;

    wire [`C1_GRAY_W-1:0]      gray_chain [0:`C1_CDC_STAGES];
    wire [`C1_GRAY_W-1:0]      gray_bin   [0:`C1_CDC_STAGES-1];

    assign push      = DIN_VALID & full_n;
    assign pop       = DOUT_READY & empty_n;
    assign DIN_READY = full_n;
    assign DOUT      = ram_dout;
    assign DOUT_VALID = empty_n;
    assign FIFO_LEVEL = level_r;
    assign FIFO_EMPTY = empty_r;
    assign FIFO_FULL  = full_r;
    assign FIFO_AFULL = (level_r >= `C1_FIFO_AFULL_TH);
    assign FIFO_AE    = (level_r <= `C1_FIFO_AEMPTY_TH);

    assign ram_addr = {{(`C1_RAM_ADDR_W-`C1_FIFO_PTR_W){1'b0}}, wptr_r};
    assign ram_din  = DIN;
    assign ram_ben  = {`C1_RAM_BEN_W{1'b0}};
    assign ram_cen  = ~(push | pop);

    // 存储体：库单元 RAM_SP_BE（叶子，位置连接）
    RAM_SP_BE u_fifo_mem (CLK, ram_cen, ~push, ram_ben, ram_addr, ram_din, ram_dout);

    // 指针（写指针的格雷码形式用于跨域同步）
    assign gray_chain[0] = wptr_r ^ (wptr_r >> 1);

    assign full_n  = ~full_r;
    assign empty_n = ~empty_r;

    genvar k;
    generate
        if (ASYNC == 1) begin : g_async_ptr
            for (k = 0; k < `C1_CDC_STAGES; k = k + 1) begin : g_gray_sync
                case1_gray_sync u_gray_sync[k] (
                    CLK,
                    RST_N,
                    CLK,
                    RST_N,
                    gray_chain[k],
                    gray_chain[k+1],
                    gray_bin[k]
                );
            end
        end else begin : g_sync_ptr
            assign gray_chain[1] = gray_chain[0];
            assign gray_bin[0]   = wptr_r;
        end
    endgenerate

    //------------------------------------------------------------------
    // 读写指针与水位
    //------------------------------------------------------------------
    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            wptr_r  <= {`C1_FIFO_PTR_W{1'b0}};
            rptr_r  <= {`C1_FIFO_PTR_W{1'b0}};
            level_r <= {`C1_FIFO_CNT_W{1'b0}};
            full_r  <= 1'b0;
            empty_r <= 1'b1;
        end else if (FLUSH) begin
            wptr_r  <= {`C1_FIFO_PTR_W{1'b0}};
            rptr_r  <= {`C1_FIFO_PTR_W{1'b0}};
            level_r <= {`C1_FIFO_CNT_W{1'b0}};
            full_r  <= 1'b0;
            empty_r <= 1'b1;
        end else begin
            case ({push, pop})
                2'b10: begin
                    wptr_r  <= wptr_r + 1'b1;
                    level_r <= level_r + 1'b1;
                    empty_r <= 1'b0;
                    full_r  <= (level_r >= `C1_FIFO_DEPTH - 1);
                end
                2'b01: begin
                    rptr_r  <= rptr_r + 1'b1;
                    level_r <= level_r - 1'b1;
                    full_r  <= 1'b0;
                    empty_r <= (level_r <= {{(`C1_FIFO_CNT_W-1){1'b0}}, 1'b1});
                end
                2'b11: begin
                    wptr_r <= wptr_r + 1'b1;
                    rptr_r <= rptr_r + 1'b1;
                end
                default: begin
                    full_r <= full_r;
                end
            endcase
        end
    end

endmodule
