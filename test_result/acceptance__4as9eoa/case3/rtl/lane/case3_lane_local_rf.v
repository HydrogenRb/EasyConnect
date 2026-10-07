//==========================================================================
//  case3_lane_local_rf.v
//  slice 级本地寄存器堆 wrapper：小容量、单读单写，用 RAM_2P 实现。
//  该模块不是叶子 —— 内部只例化 RAM_2P。
//
//  Ref: 向量机里的 slice-local scratch RF（Vision P6 的 VMEM 简化版）。
//==========================================================================
`include "case3_define.v"
`include "lib_define.v"

module case3_lane_local_rf (
    input  wire                      CLK,
    input  wire                      RST_N,
    input  wire [`C3_REG_ADDR_W-1:0] LOCAL_ADDR,
    input  wire [`C3_DATA_W-1:0]     LOCAL_WDATA,
    output wire [`C3_DATA_W-1:0]     LOCAL_RDATA,
    input  wire                      LOCAL_WE,
    input  wire                      LOCAL_RE,
    output wire                      LOCAL_BUSY,
    output wire [`C3_FLAG_W-1:0]     RF_ERR
);

    parameter LOCAL_DEPTH = `C3_REG_NUM;

    reg  busy_r;
    reg  err_r;
    wire cen_w;
    wire wen_w;

    assign cen_w      = ~(LOCAL_WE | LOCAL_RE);
    assign wen_w      = ~LOCAL_WE;
    assign LOCAL_BUSY = busy_r;
    assign RF_ERR     = {`C3_FLAG_W{err_r}};

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            busy_r <= 1'b0;
            err_r  <= 1'b0;
        end else begin
            busy_r <= LOCAL_WE | LOCAL_RE;
            err_r  <= LOCAL_WE & LOCAL_RE;
        end
    end

    // 库单元位置端口连接：CLK, A_CEN, A_WEN, A_ADDR, A_D, B_CEN, B_ADDR, B_Q
    RAM_2P u_local_rf_ram (CLK, cen_w, wen_w, LOCAL_ADDR, LOCAL_WDATA,
                           cen_w, LOCAL_ADDR, LOCAL_RDATA);

endmodule
