//==========================================================================
//  case1_ahb_master.v
//  AHB-Lite 主机 FSM（IDLE / ADDR / DATA / RESP）
//
//  每个被从机接受的地址相位消耗一个 credit（CR_TAKEN 脉冲），credit 为 0
//  时不再发起新事务。地址/写数据/字节选通从 REQ_* 请求侧锁存。
//
//  Ref: ARM AHB-Lite master 时序（IHI0033 §3.3 address/data phase）+
//       credit-based link flow control 的"发送侧扣减"实现。
//==========================================================================
`include "case1_define.v"

module case1_ahb_master (
    input  wire                          HCLK,
    input  wire                          HRESETn,
    input  wire [`C1_CR_CNT_W-1:0]       CR_CREDIT,
    input  wire                          CR_EMPTY,
    output reg                           CR_TAKEN,
    input  wire                          REQ_VALID,
    input  wire [`C1_AHB_ADDR_W-1:0]     REQ_ADDR,
    input  wire                          REQ_WRITE,
    input  wire [`C1_AHB_DATA_W-1:0]     REQ_WDATA,
    input  wire [`C1_AHB_STRB_W-1:0]     REQ_STRB,
    output wire [`C1_AHB_ADDR_W-1:0]     HADDR,
    output wire [`C1_AHB_HTRANS_W-1:0]   HTRANS,
    output wire [`C1_AHB_HSIZE_W-1:0]    HSIZE,
    output wire [`C1_AHB_HBURST_W-1:0]   HBURST,
    output wire [`C1_AHB_HPROT_W-1:0]    HPROT,
    output wire                          HWRITE,
    output wire [`C1_AHB_DATA_W-1:0]     HWDATA,
    output wire                          HMASTLOCK,
    output wire [`C1_AHB_STRB_W-1:0]     HWSTRB,
    input  wire                          HREADY,
    input  wire [`C1_AHB_HRESP_W-1:0]    HRESP,
    input  wire [`C1_AHB_DATA_W-1:0]     HRDATA,
    output wire [`C1_MON_CNT_W-1:0]      TXN_CNT,
    output wire                          BUSY
);

    // 主机类别 / 固定属性（复位后由 wrapper 或固件配置）
    parameter CR_CLASS    = 0;
    parameter HPROT_VALUE = `C1_AHB_HPROT_DATA;
    parameter HMASTLOCK_V = 1'b0;

    reg  [`C1_AHB_STATE_W-1:0]  state;
    reg  [`C1_AHB_ADDR_W-1:0]   addr_r;
    reg  [`C1_AHB_DATA_W-1:0]   wdata_r;
    reg  [`C1_AHB_DATA_W-1:0]   rdata_r;
    reg  [`C1_AHB_STRB_W-1:0]   strb_r;
    reg  [`C1_AHB_HSIZE_W-1:0]  size_r;
    reg                         write_r;
    reg  [`C1_AHB_HTRANS_W-1:0] htrans_r;
    reg  [`C1_MON_CNT_W-1:0]    txn_cnt_r;
    reg  [`C1_CR_CNT_W-1:0]     burst_len_r;
    reg  [`C1_AHB_STRB_W-1:0]   byte_en;
    wire                        credit_ok;
    wire                        addr_accept;
    integer                     b;

    // credit 检查：空标志 + 计数器双重判断
    assign credit_ok   = (CR_EMPTY == 1'b0) && (CR_CREDIT != {`C1_CR_CNT_W{1'b0}});
    assign addr_accept = (state == `C1_AHB_ST_ADDR) && HREADY && credit_ok;

    assign HADDR     = addr_r;
    assign HTRANS    = htrans_r;
    assign HSIZE     = size_r;
    assign HBURST    = `C1_AHB_HBURST_INCR;
    assign HPROT     = HPROT_VALUE;
    assign HWRITE    = write_r;
    assign HWDATA    = wdata_r;
    assign HMASTLOCK = HMASTLOCK_V;
    assign HWSTRB    = strb_r;
    assign TXN_CNT   = txn_cnt_r;
    assign BUSY      = (state != `C1_AHB_ST_IDLE);

    // 字节通道使能展开（写数据的 byte lane 视图）
    always @(*) begin
        for (b = 0; b < `C1_AHB_STRB_W; b = b + 1) begin
            byte_en[b] = strb_r[b];
        end
    end

    //------------------------------------------------------------------
    // 主机主状态机
    //------------------------------------------------------------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state       <= `C1_AHB_ST_IDLE;
            addr_r      <= {`C1_AHB_ADDR_W{1'b0}};
            wdata_r     <= {`C1_AHB_DATA_W{1'b0}};
            rdata_r     <= {`C1_AHB_DATA_W{1'b0}};
            strb_r      <= {`C1_AHB_STRB_W{1'b0}};
            size_r      <= `C1_AHB_HSIZE_WORD;
            write_r     <= 1'b0;
            htrans_r    <= `C1_AHB_HTRANS_IDLE;
            txn_cnt_r   <= {`C1_MON_CNT_W{1'b0}};
            burst_len_r <= {`C1_CR_CNT_W{1'b0}};
            CR_TAKEN    <= 1'b0;
        end else begin
            CR_TAKEN <= 1'b0;
            case (state)
                `C1_AHB_ST_IDLE: begin
                    htrans_r <= `C1_AHB_HTRANS_IDLE;
                    if (REQ_VALID && credit_ok) begin
                        addr_r      <= REQ_ADDR;
                        write_r     <= REQ_WRITE;
                        wdata_r     <= REQ_WDATA;
                        strb_r      <= REQ_STRB;
                        size_r      <= `C1_AHB_HSIZE_WORD;
                        burst_len_r <= burst_len_r + 1'b1;
                        htrans_r    <= `C1_AHB_HTRANS_NONSEQ;
                        state       <= `C1_AHB_ST_ADDR;
                    end
                end
                `C1_AHB_ST_ADDR: begin
                    if (addr_accept) begin
                        // 地址相位被接受：扣一个 credit
                        CR_TAKEN  <= 1'b1;
                        txn_cnt_r <= txn_cnt_r + {{(`C1_MON_CNT_W-1){1'b0}}, 1'b1};
                        htrans_r  <= `C1_AHB_HTRANS_IDLE;
                        state     <= `C1_AHB_ST_DATA;
                    end else if (CR_EMPTY == 1'b1) begin
                        // credit 用尽：撤销请求但保留地址
                        htrans_r <= `C1_AHB_HTRANS_IDLE;
                        state    <= `C1_AHB_ST_IDLE;
                    end
                end
                `C1_AHB_ST_DATA: begin
                    if (HREADY) begin
                        rdata_r <= HRDATA;
                        case (HRESP)
                            `C1_AHB_HRESP_OKAY:  state <= `C1_AHB_ST_IDLE;
                            `C1_AHB_HRESP_ERROR: state <= `C1_AHB_ST_IDLE;
                            `C1_AHB_HRESP_RETRY: state <= `C1_AHB_ST_ADDR;
                            `C1_AHB_HRESP_SPLIT: state <= `C1_AHB_ST_RESP;
                            default:             state <= `C1_AHB_ST_IDLE;
                        endcase
                    end
                end
                `C1_AHB_ST_RESP: begin
                    htrans_r <= `C1_AHB_HTRANS_IDLE;
                    state    <= `C1_AHB_ST_IDLE;
                end
                default: begin
                    state <= `C1_AHB_ST_IDLE;
                end
            endcase
        end
    end

endmodule
