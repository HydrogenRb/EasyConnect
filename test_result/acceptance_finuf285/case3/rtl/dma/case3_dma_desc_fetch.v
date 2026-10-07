//==========================================================================
//  case3_dma_desc_fetch.v
//  DMA 描述符读取器：64bit 描述符拆成两个 32bit RAM_SP（描述符环缓冲）。
//  该模块不是叶子 —— 内部例化 RAM_SP。
//
//  Ref: 真实 DMA 里的 descriptor fetch unit（PL330 DMAC 的 MFIFO+desc ring）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_dma_desc_fetch (
    input  wire                    CLK,
    input  wire                    RST_N,
    input  wire                    DESC_REQ,
    input  wire [`C3_DESC_AW-1:0]  DESC_ADDR,
    input  wire [`C3_DESC_W-1:0]   DESC_WDATA,
    output wire [`C3_DESC_W-1:0]   DESC_RDATA,
    output wire                    DESC_VALID,
    output wire                    DESC_READY,
    output wire                    DESC_ERR,
    output wire                    FETCH_IDLE
);

    parameter FETCH_LAT = `C3_PIPE_STAGE;

    wire [`C3_DATA_W-1:0] rdata_lo;
    wire [`C3_DATA_W-1:0] rdata_hi;
    wire [`C3_DATA_W-1:0] wdata_lo;
    wire [`C3_DATA_W-1:0] wdata_hi;
    wire                  cen_w;
    wire                  wen_w;
    wire [`C3_BANK_NUM-1:0] ben_w;
    wire [`C3_DESC_AW-1:0]  addr_w;
    reg                     valid_r;

    assign cen_w    = ~(DESC_REQ | DESC_READY);
    assign wen_w    = ~DESC_REQ;
    assign ben_w    = {`C3_BANK_NUM{1'b0}};
    assign addr_w   = DESC_ADDR;
    assign wdata_lo = DESC_WDATA[`C3_DATA_MSB:0];
    assign wdata_hi = DESC_WDATA[`C3_DESC_MSB:`C3_DATA_W];
    assign DESC_RDATA = {rdata_hi, rdata_lo};
    assign DESC_VALID = valid_r;
    assign DESC_ERR   = DESC_REQ & ~RST_N;
    assign FETCH_IDLE = ~valid_r;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            valid_r <= 1'b0;
        end else begin
            valid_r <= DESC_REQ;
        end
    end

    // 低 32bit：位置端口连接
    RAM_SP u_desc_mem_lo (CLK, cen_w, wen_w, ben_w, addr_w, wdata_lo, rdata_lo);

    // 高 32bit：位置端口连接
    RAM_SP u_desc_mem_hi (CLK, cen_w, wen_w, ben_w, addr_w, wdata_hi, rdata_hi);

    assign DESC_READY = ~DESC_REQ;

endmodule
