//==========================================================================
//  case3_sync_2ff.v
//  两级同步器：无复位打拍结构，用于跨域握手 / 选通信号的同步化。
//  叶子模块（内部没有任何例化）。
//
//  Ref: 标准 2-FF synchronizer，CDC 工具白名单里的那一层
//       （Xilinx XPM_CDC_SINGLE / 各家 cdc_sync_2ff 的等价物）。
//==========================================================================
`include "case3_define.v"

module case3_sync_2ff (
    input  wire                  CLK,
    input  wire                  RST_N,
    input  wire                  D,
    output wire                  Q
);

    reg sync_ff0;
    reg sync_ff1;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            sync_ff0 <= 1'b0;
            sync_ff1 <= 1'b0;
        end else begin
            sync_ff0 <= D;
            sync_ff1 <= sync_ff0;
        end
    end

    assign Q = sync_ff1;

endmodule
