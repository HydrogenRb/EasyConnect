//==========================================================================
//  case2_noc_output_buf.v
//  router port 的输出缓冲：跨 link 前的最后一级寄存 + 时钟门控
//
//  Ref: NoC output buffer（OB），u_out_cg 用 ICG 给空闲端口关时钟。
//==========================================================================
`include "case2_define.v"

module case2_noc_output_buf (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C2_FLIT_W-1:0]    FLIT_IN,
    input  wire                     FLIT_IN_VALID,
    input  wire [`C2_VC_NUM-1:0]    VC_SEL,
    output wire [`C2_FLIT_W-1:0]    FLIT_OUT,
    output wire                     FLIT_OUT_VALID,
    input  wire                     FLIT_OUT_READY,
    output wire [`C2_BUF_PTR_W-1:0] RD_PTR,
    output wire                     OUT_EMPTY,
    output wire                     OUT_ACTIVE
);

    reg  [`C2_FLIT_W-1:0]    flit_r;
    reg                      link_active_r;
    wire                     valid_sync;
    wire                     out_gclk;
    wire [`C2_BUF_PTR_W-1:0] rd_ptr_next;
    wire [`C2_BUF_DEPTH-1:0] rd_vec;
    wire                     rd_full;
    wire                     rd_empty;
    wire                     out_pop;

    assign OUT_ACTIVE     = |VC_SEL;
    assign OUT_EMPTY      = ~valid_sync;
    assign FLIT_OUT       = flit_r;
    assign FLIT_OUT_VALID = valid_sync & link_active_r;
    assign out_pop        = valid_sync & FLIT_OUT_READY & link_active_r;

    always @(posedge out_gclk or negedge RST_N) begin
        if (!RST_N) begin
            flit_r        <= {`C2_FLIT_W{1'b0}};
            link_active_r <= 1'b0;
        end else begin
            if (FLIT_IN_VALID) begin
                flit_r <= FLIT_IN;
            end
            link_active_r <= OUT_ACTIVE;
        end
    end

    //------------------------------------------------------------------
    // valid 同步级（位置连接风格）
    //------------------------------------------------------------------
    case2_sync_2ff u_valid_sync (CLK, RST_N, FLIT_IN_VALID, valid_sync);

    //------------------------------------------------------------------
    // 时钟门控（位置连接风格）
    //------------------------------------------------------------------
    case2_clk_gate u_out_cg (CLK, RST_N, OUT_ACTIVE, out_gclk);

    //------------------------------------------------------------------
    // 读指针
    //------------------------------------------------------------------
    case2_alloc_ptr u_out_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (out_pop),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (RD_PTR),
        .WR_PTR    (rd_ptr_next),
        .PTR_VEC   (rd_vec),
        .FULL      (rd_full),
        .EMPTY     (rd_empty)
    );

endmodule
