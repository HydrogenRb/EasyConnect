//==========================================================================
//  case2_hn_req_pipe.v
//  HN 请求流水级：锁存 REQ 关键字段并查 snoop filter
//
//  Ref: home node 的 request pipeline（地址译码 + 目录查找前级）。
//       无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_hn_req_pipe (
    input  wire                        CLK,
    input  wire                        RST_N,
    input  wire [`C2_REQ_FLIT_W-1:0]   REQ_IN,
    input  wire                        REQ_IN_VALID,
    output wire                        REQ_IN_READY,
    output reg  [`C2_CHI_ADDR_W-1:0]   ADDR,
    output reg  [`C2_CHI_OPCODE_W-1:0] OPCODE,
    output reg  [`C2_CHI_TXNID_W-1:0]  TXNID,
    output reg  [`C2_CHI_NODEID_W-1:0] SRCID,
    output reg                         REQ_VALID,
    output reg  [`C2_SNP_FILTER_W-1:0] HIT_VEC,
    output reg                         HIT_ANY,

    output wire [8 -1:0] ec_debug // EasyConnect 1.0 验收
);

    assign REQ_IN_READY = ~REQ_VALID;

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            ADDR      <= {`C2_CHI_ADDR_W{1'b0}};
            OPCODE    <= {`C2_CHI_OPCODE_W{1'b0}};
            TXNID     <= {`C2_CHI_TXNID_W{1'b0}};
            SRCID     <= {`C2_CHI_NODEID_W{1'b0}};
            HIT_VEC   <= {`C2_SNP_FILTER_W{1'b0}};
            HIT_ANY   <= 1'b0;
            REQ_VALID <= 1'b0;
        end else if (REQ_IN_VALID) begin
            ADDR      <= REQ_IN[`C2_REQ_FIELD_ADDR_MSB:`C2_REQ_FIELD_ADDR_LSB];
            OPCODE    <= REQ_IN[`C2_REQ_FIELD_OPCODE_MSB:`C2_REQ_FIELD_OPCODE_LSB];
            TXNID     <= REQ_IN[`C2_REQ_FIELD_TXNID_MSB:`C2_REQ_FIELD_TXNID_LSB];
            SRCID     <= REQ_IN[`C2_REQ_FIELD_SRCID_MSB:`C2_REQ_FIELD_SRCID_LSB];
            HIT_VEC   <= HIT_VEC |
                         {{(`C2_SNP_FILTER_W-`C2_CHI_NODEID_W){1'b0}}, SRCID};
            HIT_ANY   <= 1'b1;
            REQ_VALID <= 1'b1;
        end else begin
            REQ_VALID <= 1'b0;
        end
    end

endmodule
