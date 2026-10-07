//==========================================================================
//  case1_ahb_decoder.v
//  AHB 地址译码器：产生 one-hot HSEL / SLV_IDX / DECODE_ERR
//
//  纯组合逻辑，按地址高 4 位（`C1_SLV_DECODE_MSB:`C1_SLV_DECODE_LSB）比较
//  每个从机窗口的基址；无命中时置 DECODE_ERR 并由默认从机返回 ERROR。
//
//  Ref: AHB-Lite 地址译码 + default slave（IHI0033 §3.6 address decoding）。
//==========================================================================
`include "case1_define.v"

module case1_ahb_decoder (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    input  wire                          HSEL_DEFAULT,
    output reg  [`C1_AHB_SLAVE_NUM-1:0]  HSEL,
    output reg  [`C1_AHB_SLAVE_AW-1:0]   SLV_IDX,
    output reg  [`C1_SLV_DECODE_W-1:0]   DECODE_VAL,
    output reg                           DECODE_ERR
);

    // 译码流水级数（0 = 纯组合，1 = 打一拍）
    parameter DECODE_LATENCY = 0;

    reg [`C1_SLV_DECODE_W-1:0] decode_nibble;

    always @(*) begin
        decode_nibble = HADDR[`C1_SLV_DECODE_MSB:`C1_SLV_DECODE_LSB];
        HSEL          = `C1_HSEL_NONE;
        SLV_IDX       = `C1_SLV0_IDX;
        DECODE_ERR    = 1'b0;
        DECODE_VAL    = decode_nibble;
        casez (decode_nibble)
            `C1_SLV0_DECODE: begin
                HSEL    = `C1_HSEL_SLV0;
                SLV_IDX = `C1_SLV0_IDX;
            end
            `C1_SLV1_DECODE: begin
                HSEL    = `C1_HSEL_SLV1;
                SLV_IDX = `C1_SLV1_IDX;
            end
            `C1_SLV2_DECODE: begin
                HSEL    = `C1_HSEL_SLV2;
                SLV_IDX = `C1_SLV2_IDX;
            end
            `C1_SLV3_DECODE: begin
                HSEL    = `C1_HSEL_SLV3;
                SLV_IDX = `C1_SLV3_IDX;
            end
            default: begin
                HSEL       = HSEL_DEFAULT ? `C1_HSEL_SLV0 : `C1_HSEL_NONE;
                SLV_IDX    = HSEL_DEFAULT ? `C1_SLV0_IDX : `C1_SLV3_IDX;
                DECODE_ERR = ~HSEL_DEFAULT;
            end
        endcase
    end

endmodule
