//==========================================================================
//  case2_noc_vc.v
//  一个 router port 的一个 virtual channel：
//    u_vc_buf   : flit 存储（内部例化 RAM_SP_BE）
//    u_vc_credit: VC 级 credit 记账
//    u_vc_ptr   : 读写指针
//
//  层次路径形如 u_router[0][0].u_port[4].u_vc[1].u_vc_buf。
//==========================================================================
`include "case2_define.v"

module case2_noc_vc (
    input  wire                     CLK,
    input  wire                     RST_N,
    input  wire [`C2_FLIT_W-1:0]    FLIT_IN,
    input  wire                     FLIT_IN_VALID,
    output wire                     FLIT_IN_READY,
    output wire [`C2_FLIT_W-1:0]    FLIT_OUT,
    output wire                     FLIT_OUT_VALID,
    input  wire                     FLIT_OUT_READY,
    input  wire [`C2_ROUTE_W-1:0]   ROUTE_SEL,
    input  wire [`C2_CREDIT_W-1:0]  CREDIT_RET,
    output wire [`C2_CREDIT_W-1:0]  CREDIT_ON,
    input  wire                     VC_ALLOC,
    output wire                     VC_BUSY,
    output wire                     VC_EMPTY,
    output wire [`C2_BUF_PTR_W-1:0] VC_LEVEL
);

    parameter VC_IDX  = 0;
    parameter LINK_ID = 0;

    wire [`C2_BUF_PTR_W-1:0] wr_ptr;
    wire [`C2_BUF_PTR_W-1:0] rd_ptr;
    wire [`C2_BUF_PTR_W-1:0] wr_ptr_next;
    wire [`C2_BUF_PTR_W-1:0] rd_ptr_next;
    wire [`C2_BUF_DEPTH-1:0] wr_vec;
    wire [`C2_BUF_DEPTH-1:0] rd_vec;
    wire                     buf_full;
    wire                     buf_empty;
    wire                     rd_full;
    wire                     rd_empty;
    wire [`C2_CREDIT_W-1:0]  credit_cnt;
    wire [`C2_CREDIT_W-1:0]  vc_credit_level;
    wire                     credit_ok;
    wire                     vc_buf_full;
    wire                     vc_wr_en;
    wire                     vc_rd_en;

    reg [`C2_STATE_W-1:0] vc_state;

    assign vc_wr_en     = FLIT_IN_VALID & (~buf_full);
    assign vc_rd_en     = FLIT_OUT_READY & (~VC_EMPTY);
    assign FLIT_IN_READY = ~buf_full;
    assign FLIT_OUT_VALID = ~VC_EMPTY;
    assign VC_EMPTY     = (wr_ptr == rd_ptr);
    assign VC_BUSY      = VC_ALLOC | (~VC_EMPTY);
    assign VC_LEVEL     = wr_ptr - rd_ptr;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            vc_state <= {`C2_STATE_W{1'b0}};
        end else begin
            case (vc_state)
                {`C2_STATE_W{1'b0}}: begin
                    if (VC_ALLOC) begin
                        vc_state <= {{(`C2_STATE_W-2){1'b0}}, 2'b01};
                    end
                end
                4'b0001: begin
                    if (vc_wr_en) begin
                        vc_state <= {{(`C2_STATE_W-2){1'b0}}, 2'b10};
                    end
                end
                4'b0010: begin
                    if (vc_rd_en & (ROUTE_SEL == `C2_ROUTE_LOCAL)) begin
                        vc_state <= {{(`C2_STATE_W-2){1'b0}}, 2'b11};
                    end
                end
                default: begin
                    if (VC_EMPTY) begin
                        vc_state <= {`C2_STATE_W{1'b0}};
                    end
                end
            endcase
        end
    end

    //------------------------------------------------------------------
    // VC 缓冲（内部例化 RAM_SP_BE）
    //------------------------------------------------------------------
    case2_noc_vc_buf u_vc_buf (
        .CLK          (CLK),
        .RST_N        (RST_N),
        .FLIT_IN      (FLIT_IN),
        .FLIT_WR      (vc_wr_en),
        .WR_PTR       (wr_ptr),
        .RD_PTR       (rd_ptr),
        .FLIT_OUT     (FLIT_OUT),
        .BUF_FULL     (vc_buf_full),
        .CREDIT_LEVEL (vc_credit_level)
    );

    //------------------------------------------------------------------
    // VC 级 credit 记账
    //------------------------------------------------------------------
    case2_noc_credit_ctrl u_vc_credit (
        .CLK        (CLK),
        .RST_N      (RST_N),
        .INIT       (~RST_N | (vc_state == {`C2_STATE_W{1'b0}})),
        .SEND       (vc_wr_en),
        .RET        (|CREDIT_RET),
        .RET_NUM    (CREDIT_RET),
        .CREDIT_CNT (credit_cnt),
        .CREDIT_OK  (credit_ok),
        .CREDIT_ON  (CREDIT_ON)
    );

    //------------------------------------------------------------------
    // 指针
    //------------------------------------------------------------------
    case2_alloc_ptr u_vc_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (vc_wr_en),
        .FREE_REQ  (vc_rd_en),
        .FREE_PTR  (rd_ptr_next),
        .ALLOC_PTR (wr_ptr),
        .WR_PTR    (wr_ptr_next),
        .PTR_VEC   (wr_vec),
        .FULL      (buf_full),
        .EMPTY     (buf_empty)
    );

    //------------------------------------------------------------------
    // 读指针
    //------------------------------------------------------------------
    case2_alloc_ptr u_rd_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (vc_rd_en),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (rd_ptr),
        .WR_PTR    (rd_ptr_next),
        .PTR_VEC   (rd_vec),
        .FULL      (rd_full),
        .EMPTY     (rd_empty)
    );

endmodule
