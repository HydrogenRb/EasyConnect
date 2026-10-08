//==========================================================================
//  case2_noc_buf_ram_wrap.v
//  宽 flit 缓冲区：库宏单元 RAM_SP_BE（32bit 字）+ flit 高位寄存器组
//
//  一个 320bit flit 用 32bit 宏单元存低位字，高位 288bit 存触发器，
//  读出时拼接成完整 flit —— 真实项目里"窄宏单元拼宽 flit"的常见做法。
//
//  Ref: NoC buffer RAM wrapper / memory compiler 宏单元位宽适配层。
//==========================================================================
`include "case2_define.v"

module case2_noc_buf_ram_wrap (
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire                      FLIT_WR,
    input  wire [`C2_FLIT_W-1:0]     FLIT_IN,
    input  wire [`C2_BUF_PTR_W-1:0]  WR_PTR,
    input  wire [`C2_BUF_PTR_W-1:0]  RD_PTR,
    output wire [`C2_FLIT_W-1:0]     FLIT_OUT,
    output wire                      RAM_READY,
    output wire [`C2_CREDIT_W-1:0]   RAM_CREDIT,
    output wire [`C2_BUF_RAM_DW-1:0] RAM_Q_WORD
);

    wire [`C2_BUF_RAM_AW-1:0] ram_addr;
    wire [`C2_BUF_RAM_DW-1:0] ram_d;
    wire [`C2_BUF_RAM_DW-1:0] ram_q;
    wire                      ram_cen;
    wire                      ram_wen;
    wire [`C2_RAM_BEN_W-1:0]  ram_ben;

    reg [`C2_FLIT_W-`C2_BUF_RAM_DW-1:0] flit_tail_r;
    reg [`C2_CREDIT_W-1:0]              credit_r;

    assign ram_cen  = ~FLIT_WR;
    assign ram_wen  = ~FLIT_WR;
    assign ram_ben  = {`C2_RAM_BEN_W{1'b0}};
    assign ram_d    = FLIT_IN[`C2_BUF_RAM_DW-1:0];
    assign ram_addr = {{(`C2_BUF_RAM_AW-`C2_BUF_PTR_W){1'b0}}, WR_PTR};

    assign FLIT_OUT    = {flit_tail_r, ram_q};
    assign RAM_Q_WORD  = ram_q;
    assign RAM_READY   = ~ram_cen;
    assign RAM_CREDIT  = credit_r;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            flit_tail_r <= {(`C2_FLIT_W-`C2_BUF_RAM_DW){1'b0}};
            credit_r    <= {`C2_CREDIT_W{1'b0}};
        end else begin
            if (FLIT_WR) begin
                flit_tail_r <= FLIT_IN[`C2_FLIT_W-1:`C2_BUF_RAM_DW];
            end
            if (RD_PTR == WR_PTR) begin
                credit_r <= {`C2_CREDIT_W{1'b0}};
            end else begin
                credit_r <= {{(`C2_CREDIT_W-`C2_BUF_PTR_W){1'b0}}, WR_PTR - RD_PTR};
            end
        end
    end

    //------------------------------------------------------------------
    // 库宏单元：RAM_SP_BE（字节使能单口 RAM），位置连接
    //------------------------------------------------------------------
    RAM_SP_BE #(.AW(`C2_BUF_RAM_AW), .DW(`C2_BUF_RAM_DW), .DEPTH(`C2_BUF_RAM_DEPTH)) u_buf_ram (
        CLK,
        ram_cen,
        ram_wen,
        ram_ben,
        ram_addr,
        ram_d,
        ram_q
    );

endmodule
