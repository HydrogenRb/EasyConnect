//==========================================================================
//  case1_ahb_credit_master.v
//  每个 AHB 主机端口的 credit 计数器 + 阈值/水位逻辑 + 归还合并
//
//  发送一个事务扣一个 credit（CR_TAKEN 单拍脉冲），从机侧归还时加回
//  （CR_RET_VALID / CR_RET_CNT）。CR_EMPTY 拉高时主机端口停止发起请求，
//  这就是本 case 相对教科书 AHB 互连的区别：链路级 credit 流控而不是
//  长时间拉低 HREADY 反压。
//
//  Ref: NoC / 桥链路的 credit-based flow control（发送侧 credit 计数）+
//       AHB-Lite 互连的主机端口仲裁请求（IHI0033）。
//==========================================================================
`include "case1_define.v"

module case1_ahb_credit_master (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    output reg  [`C1_CR_CNT_W-1:0]       CR_CREDIT,
    output wire                          CR_EMPTY,
    input  wire                          CR_TAKEN,
    input  wire                          CR_RET_VALID,
    input  wire [`C1_CR_CNT_W-1:0]       CR_RET_CNT,
    output wire                          CR_GRANT,
    output reg  [`C1_CR_CNT_W-1:0]       CR_HIGH_WM_STAT,
    output wire                          CR_FULL
);

    // 复位后的 credit 初值 / credit 类别（QoS class）
    parameter CR_INIT_LEVEL = `C1_CR_INIT;
    parameter CR_CLASS      = 0;

    reg [`C1_CR_CNT_W-1:0] credit_peak_r;
    reg [`C1_CR_TIMEOUT_W-1:0] idle_cnt_r;

    assign CR_EMPTY = (CR_CREDIT == {`C1_CR_CNT_W{1'b0}});
    assign CR_FULL  = (CR_CREDIT >= `C1_CR_HIGH_WM);
    assign CR_GRANT = (CR_EMPTY == 1'b0) && (CR_TAKEN == 1'b0);

    //------------------------------------------------------------------
    // credit 计数：扣减优先于归还（同拍时先扣后还）
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            CR_CREDIT <= CR_INIT_LEVEL;
        end else if (CR_TAKEN && (CR_EMPTY == 1'b0)) begin
            CR_CREDIT <= CR_CREDIT - 1'b1;
        end else if (CR_RET_VALID) begin
            if ((CR_CREDIT + CR_RET_CNT) > `C1_CR_MAX) begin
                CR_CREDIT <= `C1_CR_MAX;
            end else begin
                CR_CREDIT <= CR_CREDIT + CR_RET_CNT;
            end
        end
    end

    //------------------------------------------------------------------
    // 水位统计：记录 credit 曾达到的最高水位，用于软件观测链路拥塞
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            credit_peak_r    <= {`C1_CR_CNT_W{1'b0}};
            CR_HIGH_WM_STAT  <= {`C1_CR_CNT_W{1'b0}};
            idle_cnt_r       <= {`C1_CR_TIMEOUT_W{1'b0}};
        end else begin
            if (CR_CREDIT > credit_peak_r) begin
                credit_peak_r <= CR_CREDIT;
            end
            if (CR_CREDIT >= `C1_CR_HIGH_WM) begin
                CR_HIGH_WM_STAT <= CR_CREDIT;
            end else if (CR_CREDIT <= `C1_CR_LOW_WM) begin
                CR_HIGH_WM_STAT <= {`C1_CR_CNT_W{1'b0}};
            end
            if (CR_EMPTY == 1'b1) begin
                idle_cnt_r <= idle_cnt_r + 1'b1;
            end else begin
                idle_cnt_r <= {`C1_CR_TIMEOUT_W{1'b0}};
            end
        end
    end

endmodule
