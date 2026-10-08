//==========================================================================
//  case2_hn_rsp_gen.v
//  HN 响应生成：按请求 opcode 决定 Resp / RespErr / FwdState / DataSource
//
//  Ref: home node 的 response generator，响应码使用 case2_define.v 里
//       唯一的 Resp 表。无例化，叶子单元。
//==========================================================================
`include "case2_define.v"

module case2_hn_rsp_gen (
    input  wire                            CLK,
    input  wire                            RST_N,
    input  wire                            REQ_VALID,
    input  wire [`C2_CHI_OPCODE_W-1:0]     REQ_OPCODE,
    input  wire                            HIT_ANY,
    input  wire                            SNP_DONE,
    input  wire [`C2_CHI_RESPERR_W-1:0]    RESPERR_IN,
    output reg  [`C2_CHI_RESP_W-1:0]       RESP,
    output reg  [`C2_CHI_RESPERR_W-1:0]    RESPERR,
    output reg  [`C2_CHI_FWDSTATE_W-1:0]   FWDSTATE,
    output reg  [`C2_CHI_DATASOURCE_W-1:0] DATASOURCE,
    output reg  [`C2_CHI_OPCODE_W-1:0]     RSP_OPCODE,
    output reg                             RSP_VALID
);

    always @(*) begin
        RESP       = `C2_RESP_ICO;
        RESPERR    = RESPERR_IN;
        FWDSTATE   = `C2_FWDSTATE_I;
        DATASOURCE = {`C2_CHI_DATASOURCE_W{1'b0}};
        RSP_OPCODE = `C2_OP_COMP;
        case (REQ_OPCODE)
            `C2_OP_READ_SHARED: begin
                RESP       = HIT_ANY ? `C2_RESP_SC : `C2_RESP_ICO;
                RSP_OPCODE = `C2_OP_COMP_DATA;
            end
            `C2_OP_READ_UNIQUE: begin
                RESP       = HIT_ANY ? `C2_RESP_UC : `C2_RESP_ICO;
                RSP_OPCODE = `C2_OP_COMP_DATA;
            end
            `C2_OP_READ_ONCE: begin
                RESP       = `C2_RESP_UD_PD;
                RSP_OPCODE = `C2_OP_COMP_DATA;
            end
            `C2_OP_READ_CLEAN: begin
                RESP       = `C2_RESP_UC;
                FWDSTATE   = `C2_FWDSTATE_SC;
                RSP_OPCODE = `C2_OP_COMP_DATA;
            end
            `C2_OP_WRITE_UNIQUE: begin
                RESP       = SNP_DONE ? `C2_RESP_UD : `C2_RESP_SD;
                RSP_OPCODE = SNP_DONE ? `C2_OP_COMP : `C2_OP_COMP_DBID_RESP;
            end
            `C2_OP_WRITE_BACK_FULL: begin
                RESP       = `C2_RESP_UD_PD;
                RSP_OPCODE = `C2_OP_COMP_DBID_RESP;
            end
            `C2_OP_WRITE_EVICT_FULL: begin
                RESP       = `C2_RESP_SD_PD;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_WRITE_CLEAN_FULL: begin
                RESP       = `C2_RESP_SD_PD;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_MAKE_UNIQUE: begin
                RESP       = `C2_RESP_UC;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_CLEAN_UNIQUE: begin
                RESP       = `C2_RESP_UC;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_CLEAN_SHARED: begin
                RESP       = `C2_RESP_SC;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_CLEAN_INVALID: begin
                RESP       = `C2_RESP_I_PD;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_MAKE_INVALID: begin
                RESP       = `C2_RESP_I_PD;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_EVICT: begin
                RESP       = `C2_RESP_I_PD;
                RSP_OPCODE = `C2_OP_COMP;
            end
            `C2_OP_SNP_RESP: begin
                RESP       = `C2_RESP_SD;
                RSP_OPCODE = `C2_OP_SNP_RESP;
            end
            `C2_OP_SNP_RESP_DATA: begin
                RESP       = `C2_RESP_SD;
                DATASOURCE = `C2_CHI_DATASOURCE_W'h1;
                RSP_OPCODE = `C2_OP_SNP_RESP_DATA;
            end
            default: begin
                RESP       = `C2_RESP_ICO;
                RSP_OPCODE = `C2_OP_COMP;
            end
        endcase
    end

    always @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            RSP_VALID <= 1'b0;
        end else begin
            RSP_VALID <= REQ_VALID & (RESPERR != `C2_RESPERR_NDERR);
        end
    end

endmodule
