//==========================================================================
//  case2_noc_route.v
//  维序（dimension-order）路由计算：由 TgtID 低比特解出目标坐标，
//  再与本路由器坐标比较，给出输出端口与路由模式。
//
//  Ref: mesh NoC 的 XY routing unit。X_IDX / Y_IDX 由例化处的
//       #( .X_IDX(v), .Y_IDX(v) ) 注入。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_noc_route (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_CHI_ADDR_W-1:0]   ADDR,
    input  wire [`C2_CHI_NODEID_W-1:0] TGTID,
    input  wire [`C2_ROUTE_W-1:0]      ROUTE_MODE,
    input  wire                        ROUTE_REQ,
    input  wire [`C2_PORT_AW-1:0]      PORT_IDX,
    output reg  [`C2_PORT_AW-1:0]      ROUTE_PORT,
    output reg  [`C2_ROUTE_W-1:0]      ROUTE_SEL,
    output reg  [`C2_NOC_X_W-1:0]      DST_X,
    output reg  [`C2_NOC_Y_W-1:0]      DST_Y,
    output reg                         ROUTE_VALID
);

    parameter X_IDX = 0;
    parameter Y_IDX = 0;

    always @(*) begin
        DST_X      = TGTID[`C2_NOC_X_W-1:0];
        DST_Y      = TGTID[`C2_NOC_X_W+`C2_NOC_Y_W-1:`C2_NOC_X_W];
        ROUTE_PORT = PORT_IDX;
        ROUTE_SEL  = ROUTE_MODE;
        if (TGTID[`C2_NOC_X_W-1:0] != X_IDX) begin
            ROUTE_PORT = `C2_PORT_E;
            ROUTE_SEL  = `C2_ROUTE_X_FIRST;
        end else if (TGTID[`C2_NOC_X_W+`C2_NOC_Y_W-1:`C2_NOC_X_W] != Y_IDX) begin
            ROUTE_PORT = `C2_PORT_S;
            ROUTE_SEL  = `C2_ROUTE_Y_FIRST;
        end else begin
            ROUTE_PORT = `C2_PORT_LOCAL;
            ROUTE_SEL  = `C2_ROUTE_LOCAL;
        end
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            ROUTE_VALID <= 1'b0;
        end else begin
            ROUTE_VALID <= ROUTE_REQ & (|ADDR[`C2_CHI_ADDR_MSB:`C2_CHI_ADDR_MSB-3]);
        end
    end

endmodule
