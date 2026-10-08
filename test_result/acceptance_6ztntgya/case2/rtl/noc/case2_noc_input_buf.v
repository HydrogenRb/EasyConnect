//==========================================================================
//  case2_noc_input_buf.v
//  router port 的输入缓冲：flit 头 FIFO（描述符）+ 宽 payload RAM
//
//  Ref: NoC input buffer（IB）；flit 先落到 IB，再由 VC 分配器取走。
//==========================================================================
`include "case2_define.v"

module case2_noc_input_buf (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C2_FLIT_W-1:0]      FLIT_IN,
    input  wire                       FLIT_IN_VALID,
    output wire                       FLIT_IN_READY,
    input  wire [`C2_VC_NUM-1:0]      VC_SEL,
    input  wire                       VC_ALLOC_REQ,
    output wire [`C2_FLIT_W-1:0]      FLIT_OUT,
    output wire                       FLIT_OUT_VALID,
    output wire [`C2_FLIT_KIND_W-1:0] FLIT_KIND,
    output wire                       BUF_FULL,
    output wire [`C2_BUF_PTR_W-1:0]   WR_PTR
);

    wire [`C2_BUF_PTR_W-1:0]   rd_ptr;
    wire [`C2_BUF_PTR_W-1:0]   rd_ptr_next;
    wire [`C2_BUF_DEPTH-1:0]   rd_vec;
    wire                       rd_full;
    wire                       rd_empty;
    wire                       fifo_empty;
    wire                       hdr_valid;
    wire [`C2_BUF_RAM_DW-1:0]  hdr_q;
    wire [`C2_BUF_RAM_DW-1:0]  payload_word;
    wire                       payload_ready;
    wire [`C2_CREDIT_W-1:0]    payload_credit;
    wire                       flit_pop;

    assign flit_pop = hdr_valid & VC_ALLOC_REQ;

    assign FLIT_OUT_VALID = hdr_valid;
    assign FLIT_KIND      = hdr_q[`C2_FLIT_KIND_MSB:0];

    always @(*) begin
        if (fifo_empty) begin
            rd_ptr_next = rd_ptr;
        end else begin
            rd_ptr_next = rd_ptr + {{(`C2_BUF_PTR_W-1){1'b0}}, 1'b1};
        end
    end

    //------------------------------------------------------------------
    // flit 头 / 描述符 FIFO
    //------------------------------------------------------------------
    case2_sync_fifo u_hdr_fifo (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .WR_DATA    (FLIT_IN[`C2_BUF_RAM_DW-1:0]),
        .WR_EN      (FLIT_IN_VALID),
        .WR_READY   (FLIT_IN_READY),
        .RD_DATA    (hdr_q),
        .RD_EN      (flit_pop),
        .RD_VALID   (hdr_valid),
        .FIFO_LEVEL (WR_PTR),
        .FIFO_FULL  (BUF_FULL),
        .FIFO_EMPTY (fifo_empty)
    );

    //------------------------------------------------------------------
    // 宽 flit payload 缓冲（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    case2_noc_buf_ram_wrap u_payload_ram (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .FLIT_WR    (FLIT_IN_VALID),
        .FLIT_IN    (FLIT_IN),
        .WR_PTR     (WR_PTR),
        .RD_PTR     (rd_ptr),
        .FLIT_OUT   (FLIT_OUT),
        .RAM_READY  (payload_ready),
        .RAM_CREDIT (payload_credit),
        .RAM_Q_WORD (payload_word)
    );

    //------------------------------------------------------------------
    // 读指针
    //------------------------------------------------------------------
    case2_alloc_ptr u_rd_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (flit_pop),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (rd_ptr),
        .WR_PTR    (rd_ptr_next),
        .PTR_VEC   (rd_vec),
        .FULL      (rd_full),
        .EMPTY     (rd_empty)
    );

endmodule
