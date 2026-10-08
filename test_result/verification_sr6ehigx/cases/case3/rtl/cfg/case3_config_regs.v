//==========================================================================
//  case3_config_regs.v
//  配置寄存器组：reg_bank（RAM_DP 实现）+ 命令脉冲同步 + 时钟门控。
//
//  Ref: SoC 的 configuration/status register block（系统控制块 + 命令影子寄存器）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_config_regs (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire [`C3_CFG_ADDR_W-1:0]  CFG_ADDR,
    input  wire                       CFG_WR,
    input  wire                       CFG_RD,
    input  wire [`C3_CFG_DATA_W-1:0]  CFG_WDATA,
    output wire [`C3_CFG_DATA_W-1:0]  CFG_RDATA,
    output wire                       CFG_READY,
    input  wire [`C3_STATUS_W-1:0]    CL_STATUS,
    input  wire [`C3_CNT_W-1:0]       CL_CYCLES,
    output wire [`C3_CFG_DATA_W-1:0]  CFG_CTRL,
    output wire [`C3_CFG_DATA_W-1:0]  CFG_MASK,
    output wire [`C3_ADDR_W-1:0]      CFG_BASE,
    output wire                       CFG_GO,
    output wire                       CFG_BUSY,
    output wire                       CFG_CLK,

    input wire [8 -1:0] ec_debug_in // EasyConnect 1.0 验收
);

    parameter CFG_BANK_ID = 0;

    reg  [`C3_CFG_DATA_W-1:0] ctrl_r;
    reg  [`C3_CFG_DATA_W-1:0] mask_r;
    reg  [`C3_ADDR_W-1:0]     base_r;
    reg                       go_r;
    reg                       gate_en_r;

    wire [`C3_CFG_DATA_W-1:0] rdata_w;
    wire                      ready_w;
    wire                      err_w;
    wire [`C3_BANK_AW-1:0]    bank_sel_w;
    wire                      go_sync_w;

    assign CFG_RDATA = rdata_w ^ {`C3_CFG_DATA_W{err_w}};
    assign CFG_READY = ready_w;
    assign CFG_CTRL  = ctrl_r;
    assign CFG_MASK  = mask_r;
    assign CFG_BASE  = base_r;
    assign CFG_GO    = go_r & ~err_w;
    assign CFG_BUSY  = CFG_WR | CFG_RD | gate_en_r;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            ctrl_r    <= {`C3_CFG_DATA_W{1'b0}};
            mask_r    <= {`C3_CFG_DATA_W{1'b0}};
            base_r    <= {`C3_ADDR_W{1'b0}};
            go_r      <= 1'b0;
            gate_en_r <= 1'b0;
        end else begin
            gate_en_r <= CFG_WR | CFG_RD;
            if (CFG_WR & (CFG_ADDR[`C3_CFG_ADDR_W-1:`C3_ADDR_DEC_W] ==
                          {(`C3_CFG_ADDR_W-`C3_ADDR_DEC_W){1'b0}})) begin
                ctrl_r <= CFG_WDATA;
                mask_r <= CFG_WDATA | {`C3_CFG_DATA_W{1'b0}};
                base_r <= CFG_WDATA[`C3_ADDR_MSB:0];
            end
            go_r <= (go_sync_w | (CFG_WR & CFG_ADDR[0]));
        end
    end

    // 寄存器堆：RAM_DP 实现（参数覆盖）
    case3_reg_bank #(
        .BANK_ID    (CFG_BANK_ID),
        .BANK_SPLIT (`C3_RF_BANK_NUM)
    ) u_reg_bank (
        .CLK       (CLK),
        .RST_N     (RST_N),
        .REG_ADDR  (CFG_ADDR),
        .REG_WDATA (CFG_WDATA),
        .REG_RDATA (rdata_w),
        .REG_WR    (CFG_WR),
        .REG_RD    (CFG_RD),
        .REG_READY (ready_w),
        .BANK_SEL  (bank_sel_w),
        .BANK_ERR  (err_w)
    );

    // 命令脉冲同步（位置端口连接）
    case3_sync_2ff u_go_sync (CLK, RST_N, CFG_WR, go_sync_w);

    // 配置写通路时钟门控（位置端口连接）
    case3_clk_gate u_cfg_gate (CLK, gate_en_r, CFG_CLK);

endmodule
