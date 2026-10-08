//==========================================================================
//  case2_hn_snoop_filter.v
//  HN 目录 / snoop filter：tag RAM（RAM_DP）+ 命中向量 + 转发状态
//
//  Ref: CHI home node 的 snoop filter / directory（每 cache line 记录 sharer）。
//==========================================================================
`include "case2_define.v"

module case2_hn_snoop_filter (
    input  wire                            CLK,
    input  wire                            RST_N,
    input  wire                            LOOKUP_REQ,
    input  wire [`C2_CHI_ADDR_W-1:0]       ADDR,
    input  wire [`C2_CHI_NODEID_W-1:0]     SRCID,
    input  wire                            UPDATE_REQ,
    input  wire [`C2_CHI_BE_W-1:0]         BE,
    output wire [`C2_SNP_FILTER_W-1:0]     SNP_VEC,
    output wire                            HIT_ANY,
    output wire [`C2_CHI_FWDSTATE_W-1:0]   FWDSTATE,
    output wire [`C2_CHI_DATASOURCE_W-1:0] DATASOURCE,
    output wire [`C2_TAG_RAM_DW-1:0]       TAG_DATA,
    output wire                            TAG_FULL
);

    wire [`C2_TAG_RAM_AW-1:0]  tag_addr;
    wire [`C2_TAG_RAM_DW-1:0]  tag_d;
    wire [`C2_TAG_RAM_DW-1:0]  tag_q;
    wire                       tag_a_cen;
    wire                       tag_a_wen;
    wire                       tag_b_cen;
    wire                       tag_b_wen;
    wire [`C2_TAG_RAM_DW-1:0]  tag_b_d;
    wire [`C2_TAG_RAM_DW-1:0]  tag_gray;
    wire [`C2_BUF_PTR_W-1:0]   alloc_ptr;
    wire [`C2_BUF_PTR_W-1:0]   wr_ptr;
    wire [`C2_BUF_DEPTH-1:0]   ptr_vec;
    wire                       tag_empty;

    assign tag_a_cen    = ~UPDATE_REQ;
    assign tag_a_wen    = ~UPDATE_REQ;
    assign tag_b_cen    = ~LOOKUP_REQ;
    assign tag_b_wen    = 1'b1;
    assign tag_b_d      = {`C2_TAG_RAM_DW{1'b0}};
    assign tag_addr     = ADDR[`C2_CHI_ADDR_MSB-3 -: `C2_TAG_RAM_AW];
    assign tag_d        = {{(`C2_TAG_RAM_DW-`C2_CHI_NODEID_W){1'b0}}, SRCID};
    assign TAG_DATA     = tag_q;
    assign SNP_VEC      = tag_q;
    assign HIT_ANY      = |tag_q;
    assign FWDSTATE     = HIT_ANY ? `C2_FWDSTATE_SC : `C2_FWDSTATE_I;
    assign DATASOURCE   = {`C2_CHI_DATASOURCE_W{1'b0}};
    assign TAG_FULL     = ~tag_empty;

    //------------------------------------------------------------------
    // 目录 RAM：库宏单元 RAM_DP（位置连接）
    //------------------------------------------------------------------
    RAM_DP #(.AW(`C2_TAG_RAM_AW), .DW(`C2_TAG_RAM_DW), .DEPTH(`C2_TAG_RAM_DEPTH)) u_tag_ram (
        CLK,
        tag_a_cen,
        tag_a_wen,
        tag_addr,
        tag_d,
        tag_q,
        tag_b_cen,
        tag_b_wen,
        tag_addr,
        tag_b_d,
        tag_q
    );

    //------------------------------------------------------------------
    // 目录指针（分配 / 溢出保护）
    //------------------------------------------------------------------
    case2_alloc_ptr u_tag_ptr (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .ALLOC_REQ (UPDATE_REQ),
        .FREE_REQ  (1'b0),
        .FREE_PTR  ({`C2_BUF_PTR_W{1'b0}}),
        .ALLOC_PTR (alloc_ptr),
        .WR_PTR    (wr_ptr),
        .PTR_VEC   (ptr_vec),
        .FULL      (),
        .EMPTY     (tag_empty)
    );

    //------------------------------------------------------------------
    // 目录指针跨域采样
    //------------------------------------------------------------------
    case2_gray_sync u_tag_sync (
        .CLK     (CLK),
        .RST_N   (RST_N),
        .PTR_IN  (alloc_ptr),
        .PTR_OUT (tag_gray[`C2_BUF_PTR_W-1:0])
    );

endmodule
