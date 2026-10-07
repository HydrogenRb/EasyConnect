//==========================================================================
//  case3_sync_fifo.v
//  同步 FIFO：RAM_SP_BE 做存储体，读写指针 + 计数逻辑在外围。
//  该模块不是叶子 —— 内部例化 RAM_SP_BE 与两个 case3_sync_2ff。
//
//  Ref: 经典 sync_fifo / aFIFO（Xilinx FIFO Generator 的 block-RAM 实现风格）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_sync_fifo (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       WR_EN,
    input  wire [`C3_DATA_W-1:0]      WR_DATA,
    input  wire                       RD_EN,
    output wire [`C3_DATA_W-1:0]      RD_DATA,
    output wire                       FIFO_FULL,
    output wire                       FIFO_EMPTY,
    output wire [`C3_FIFO_CNT_W-1:0]  FIFO_CNT,
    output wire                       FIFO_ERR
);

    parameter FIFO_DEPTH = `C3_FIFO_DEPTH;
    parameter FIFO_AFULL  = `C3_FIFO_DEPTH - 1;

    reg  [`C3_FIFO_PTR_W-1:0] wptr_r;
    reg  [`C3_FIFO_PTR_W-1:0] rptr_r;
    reg  [`C3_FIFO_CNT_W-1:0] cnt_r;
    wire [`C3_FIFO_PTR_W-1:0] wptr_next;
    wire [`C3_FIFO_PTR_W-1:0] rptr_next;
    wire                      wr_fire;
    wire                      rd_fire;
    wire                      full_w;
    wire                      empty_w;
    wire                      wptr_sync_bit;
    wire                      rptr_sync_bit;

    assign wptr_next = wptr_r + {{(`C3_FIFO_PTR_W-1){1'b0}}, 1'b1};
    assign rptr_next = rptr_r + {{(`C3_FIFO_PTR_W-1){1'b0}}, 1'b1};
    assign full_w    = (cnt_r == `C3_FIFO_DEPTH);
    assign empty_w   = (cnt_r == 0);
    assign wr_fire   = WR_EN & ~full_w;
    assign rd_fire   = RD_EN & ~empty_w;

    assign FIFO_FULL  = full_w;
    assign FIFO_EMPTY = empty_w;
    assign FIFO_CNT   = cnt_r;
    assign FIFO_ERR   = wptr_sync_bit ^ rptr_sync_bit;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            wptr_r <= {`C3_FIFO_PTR_W{1'b0}};
            rptr_r <= {`C3_FIFO_PTR_W{1'b0}};
            cnt_r  <= {`C3_FIFO_CNT_W{1'b0}};
        end else begin
            if (wr_fire) begin
                wptr_r <= wptr_next;
            end
            if (rd_fire) begin
                rptr_r <= rptr_next;
            end
            case ({wr_fire, rd_fire})
                2'b10:   cnt_r <= cnt_r + {{(`C3_FIFO_CNT_W-1){1'b0}}, 1'b1};
                2'b01:   cnt_r <= cnt_r - {{(`C3_FIFO_CNT_W-1){1'b0}}, 1'b1};
                default: cnt_r <= cnt_r;
            endcase
        end
    end

    // 库单元位置端口连接：CLK, CEN, WEN, BEN, ADDR, D, Q
    RAM_SP_BE u_fifo_mem (CLK, ~wr_fire, ~wr_fire, {`C3_BANK_NUM{1'b0}},
                          wptr_r, WR_DATA, RD_DATA);

    // 指针同步器（位置端口连接）
    case3_sync_2ff u_wptr_sync (CLK, RST_N, wptr_r[0], wptr_sync_bit);
    case3_sync_2ff u_rptr_sync (CLK, RST_N, rptr_r[0], rptr_sync_bit);

endmodule
