//==========================================================================
//  case2_sync_fifo.v
//  同步 FIFO（描述符 / flit 头 FIFO）：RAM_SP_BE + 读写指针
//
//  实现说明：FIFO 的存储体是库宏单元 RAM_SP_BE（单口、字节使能），
//  每个 entry 为 `C2_BUF_RAM_DW 位（flit 头/描述符字），宽 flit 的
//  payload 由 case2_noc_vc_buf / case2_noc_buf_ram_wrap 另存。
//
//  Ref: NoC link FIFO / CHI TX-RX FIFO wrapper。
//==========================================================================
`include "case2_define.v"

module case2_sync_fifo (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C2_BUF_RAM_DW-1:0] WR_DATA,
    input  wire                     WR_EN,
    output wire                     WR_READY,
    output wire [`C2_BUF_RAM_DW-1:0] RD_DATA,
    input  wire                     RD_EN,
    output wire                     RD_VALID,
    output wire [`C2_BUF_PTR_W-1:0] FIFO_LEVEL,
    output wire                     FIFO_FULL,
    output wire                     FIFO_EMPTY
);

    wire [`C2_BUF_PTR_W-1:0] wr_ptr;
    wire [`C2_BUF_PTR_W-1:0] rd_ptr;
    wire [`C2_BUF_PTR_W-1:0] wr_ptr_next;
    wire [`C2_BUF_PTR_W-1:0] rd_ptr_next;
    wire [`C2_BUF_DEPTH-1:0] wr_vec;
    wire [`C2_BUF_DEPTH-1:0] rd_vec;
    wire                     wr_full;
    wire                     wr_empty;
    wire                     rd_full;
    wire                     rd_empty;
    wire                     ram_wr_en;
    wire                     ram_rd_en;

    wire [`C2_BUF_RAM_AW-1:0] ram_addr;
    wire [`C2_BUF_RAM_DW-1:0] ram_d;
    wire [`C2_BUF_RAM_DW-1:0] ram_q;
    wire                      ram_q_valid;
    wire                      ram_cen;
    wire                      ram_wen;
    wire [`C2_RAM_BEN_W-1:0]  ram_ben;

    assign FIFO_EMPTY = (wr_ptr == rd_ptr);
    assign FIFO_FULL  = (wr_ptr == (rd_ptr - {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1}));
    assign WR_READY   = ~FIFO_FULL;
    assign RD_VALID   = ram_q_valid;
    assign FIFO_LEVEL = wr_ptr - rd_ptr;

    always @(*) begin
        ram_wr_en = WR_EN & (~FIFO_FULL);
        ram_rd_en = RD_EN & (~FIFO_EMPTY);
    end

    assign ram_cen  = ~(ram_wr_en | ram_rd_en);
    assign ram_wen  = ~ram_wr_en;
    assign ram_ben  = {`C2_RAM_BEN_W{1'b0}};
    assign ram_d    = WR_DATA;
    assign ram_addr = ram_wr_en ?
                      {{(`C2_BUF_RAM_AW-`C2_BUF_PTR_W){1'b0}}, wr_ptr} :
                      {{(`C2_BUF_RAM_AW-`C2_BUF_PTR_W){1'b0}}, rd_ptr};

    //------------------------------------------------------------------
    // 写 / 读指针
    //------------------------------------------------------------------
    case2_alloc_ptr u_wr_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (ram_wr_en),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (wr_ptr),
        .WR_PTR    (wr_ptr_next),
        .PTR_VEC   (wr_vec),
        .FULL      (wr_full),
        .EMPTY     (wr_empty)
    );

    case2_alloc_ptr u_rd_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (ram_rd_en),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (rd_ptr),
        .WR_PTR    (rd_ptr_next),
        .PTR_VEC   (rd_vec),
        .FULL      (rd_full),
        .EMPTY     (rd_empty)
    );

    //------------------------------------------------------------------
    // 读数据有效打拍（位置连接风格）
    //------------------------------------------------------------------
    case2_sync_2ff u_rd_valid_sync (CLK, RST_N, ram_rd_en, ram_q_valid);

    //------------------------------------------------------------------
    // 存储体：库宏单元 RAM_SP_BE（参数用 #() 覆盖）
    //------------------------------------------------------------------
    RAM_SP_BE #(.AW(`C2_BUF_RAM_AW), .DW(`C2_BUF_RAM_DW), .DEPTH(`C2_BUF_RAM_DEPTH)) u_fifo_ram (
        CLK,
        ram_cen,
        ram_wen,
        ram_ben,
        ram_addr,
        ram_d,
        ram_q
    );

    assign RD_DATA = ram_q;

endmodule
