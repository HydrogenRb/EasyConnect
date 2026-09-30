`include "defs.vh"
module top(input wire clk);
    ArrayBridge U_B (.clk(clk));
    ArraySink U_D (.clk(clk));
endmodule

module ArrayBridge(input wire clk);
    ArrayProducer U_C (.clk(clk));
endmodule

module ArrayProducer(input wire clk);
    wire signed [`EC_DATA_W-1:0][1:0] payload [0:`EC_ROWS-1][0:`EC_COLS-1];
endmodule

module ArraySink(input wire clk);
    wire signed [`EC_DATA_W-1:0][1:0] received [0:`EC_ROWS-1][0:`EC_COLS-1];
endmodule
