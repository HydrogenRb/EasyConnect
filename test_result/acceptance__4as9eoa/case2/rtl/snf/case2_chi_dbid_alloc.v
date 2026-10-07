//==========================================================================
//  case2_chi_dbid_alloc.v
//  DBID（data buffer ID）分配：SN 侧写数据缓冲的编号管理
//
//  Ref: CHI 里 DBIDResp 的 DBID 分配逻辑。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_chi_dbid_alloc (
    input  wire                       CLK,
    input  wire                       RST_N,
    input  wire                       DBID_REQ,
    input  wire                       DBID_FREE,
    input  wire [`C2_CHI_DBID_W-1:0]  DBID_IN,
    output reg  [`C2_CHI_DBID_W-1:0]  DBID,
    output wire [`C2_CHI_DBID_W-1:0]  DBID_CNT,
    output wire                       DBID_VALID,
    output wire [`C2_CHI_CBUSY_W-1:0] DBID_CBUSY
);

    reg [`C2_CHI_DBID_W-1:0] dbid_cnt;

    assign DBID_CNT   = dbid_cnt;
    assign DBID_VALID = DBID_REQ & (dbid_cnt != {`C2_CHI_DBID_W{1'b1}});
    assign DBID_CBUSY = dbid_cnt[`C2_CHI_CBUSY_W-1:0];

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            DBID     <= {`C2_CHI_DBID_W{1'b0}};
            dbid_cnt <= {`C2_CHI_DBID_W{1'b0}};
        end else if (DBID_REQ & DBID_VALID) begin
            DBID     <= DBID + {{(`C2_CHI_DBID_W-1){1'b0}}, 1'b1};
            dbid_cnt <= dbid_cnt + {{(`C2_CHI_DBID_W-1){1'b0}}, 1'b1};
        end else if (DBID_FREE) begin
            DBID     <= DBID_IN;
            dbid_cnt <= dbid_cnt - {{(`C2_CHI_DBID_W-1){1'b0}}, 1'b1};
        end
    end

endmodule
