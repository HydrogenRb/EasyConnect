//==========================================================================
//  case1_ahb_slave.v
//  AHB-Lite 从机 FSM（IDLE / WAIT / RESP）
//
//  产生 HREADYOUT / HRESP，并在事务完成时给出 CR_RETURN 单拍脉冲，
//  供 credit 归还通路使用；内部含一个用于响应延迟建模的小存储体。
//
//  Ref: ARM AHB-Lite slave 响应时序（IHI0033 §3.5 slave response）+
//       SRAM controller / 默认从机（default slave）实现。
//==========================================================================
`include "case1_define.v"

module case1_ahb_slave (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire                          HSEL,
    input  wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    input  wire [`C1_AHB_HTRANS_W-1:0]   HTRANS,
    input  wire [`C1_AHB_HSIZE_W-1:0]    HSIZE,
    input  wire [`C1_AHB_HBURST_W-1:0]   HBURST,
    input  wire [`C1_AHB_HPROT_W-1:0]    HPROT,
    input  wire                          HWRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     HWDATA,
    input  wire [`C1_AHB_STRB_W-1:0]     HWSTRB,
    output reg                           HREADYOUT,
    output reg  [`C1_AHB_HRESP_W-1:0]    HRESP,
    output reg  [`C1_AHB_DATA_W-1:0]     HRDATA,
    output reg                           CR_RETURN,
    output reg  [`C1_MON_CNT_W-1:0]      LATENCY_CNT
);

    // 从机编号 / 等待周期数（由 wrapper 用参数覆盖）
    parameter SLAVE_ID   = 0;
    parameter WAIT_CYCLES = 2;
    parameter BASE_ADDR  = `C1_SLV0_BASE;

    reg  [`C1_AHB_STATE_W-1:0]        state;
    reg  [`C1_CR_TIMEOUT_W-1:0]       wait_cnt;
    reg  [`C1_MON_CNT_W-1:0]          latency_r;
    reg  [`C1_AHB_DATA_W-1:0]         mem [0:`C1_REG_NUM-1];
    reg  [`C1_REG_AW-1:0]             mem_idx;
    wire                              select_phase;
    wire                              wait_done;
    integer                           i;

    assign select_phase = (HTRANS == `C1_AHB_HTRANS_NONSEQ) ||
                          (HTRANS == `C1_AHB_HTRANS_SEQ);
    assign wait_done    = (wait_cnt >= WAIT_CYCLES);

    initial begin
        for (i = 0; i < `C1_REG_NUM; i = i + 1) begin
            mem[i] = {`C1_AHB_DATA_W{1'b0}};
        end
    end

    //------------------------------------------------------------------
    // 从机主状态机：IDLE → WAIT → RESP
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state       <= `C1_AHB_ST_IDLE;
            wait_cnt    <= {`C1_CR_TIMEOUT_W{1'b0}};
            latency_r   <= {`C1_MON_CNT_W{1'b0}};
            HRESP       <= `C1_AHB_HRESP_OKAY;
            HRDATA      <= {`C1_AHB_DATA_W{1'b0}};
            HREADYOUT   <= 1'b1;
            CR_RETURN   <= 1'b0;
            LATENCY_CNT <= {`C1_MON_CNT_W{1'b0}};
            mem_idx     <= {`C1_REG_AW{1'b0}};
        end else begin
            CR_RETURN <= 1'b0;
            case (state)
                `C1_AHB_ST_IDLE: begin
                    HREADYOUT <= 1'b1;
                    HRESP     <= `C1_AHB_HRESP_OKAY;
                    if (HSEL && select_phase) begin
                        mem_idx <= HADDR[`C1_REG_IDX_MSB:0];
                        if (HWRITE) begin
                            case (HSIZE)
                                `C1_AHB_HSIZE_BYTE: begin
                                    if (HWSTRB[0]) mem[mem_idx][7:0] <= HWDATA[7:0];
                                end
                                `C1_AHB_HSIZE_HALF: begin
                                    if (HWSTRB[0]) mem[mem_idx][15:8] <= HWDATA[15:8];
                                    if (HWSTRB[1]) mem[mem_idx][7:0]  <= HWDATA[7:0];
                                end
                                default: begin
                                    if (HWSTRB[0]) mem[mem_idx][7:0]   <= HWDATA[7:0];
                                    if (HWSTRB[1]) mem[mem_idx][15:8]  <= HWDATA[15:8];
                                    if (HWSTRB[2]) mem[mem_idx][23:16] <= HWDATA[23:16];
                                    if (HWSTRB[3]) mem[mem_idx][31:24] <= HWDATA[31:24];
                                end
                            endcase
                        end
                        wait_cnt <= {`C1_CR_TIMEOUT_W{1'b0}};
                        state    <= `C1_AHB_ST_ADDR;
                    end
                end
                `C1_AHB_ST_ADDR: begin
                    // wait-state 注入：模拟慢速从机
                    HREADYOUT <= 1'b0;
                    if (wait_done) begin
                        HREADYOUT <= 1'b1;
                        HRESP     <= `C1_AHB_HRESP_OKAY;
                        HRDATA    <= mem[mem_idx];
                        state     <= `C1_AHB_ST_DATA;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end
                `C1_AHB_ST_DATA: begin
                    // 响应相位结束：归还一个 credit
                    HREADYOUT   <= 1'b1;
                    HRESP       <= `C1_AHB_HRESP_OKAY;
                    CR_RETURN   <= 1'b1;
                    latency_r   <= latency_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                    LATENCY_CNT <= latency_r;
                    state       <= `C1_AHB_ST_IDLE;
                end
                `C1_AHB_ST_RESP: begin
                    HRESP     <= `C1_AHB_HRESP_ERROR;
                    HREADYOUT <= 1'b1;
                    state     <= `C1_AHB_ST_IDLE;
                end
                default: begin
                    state <= `C1_AHB_ST_IDLE;
                end
            endcase
        end
    end

endmodule
