module top(clk);
    input clk;
    Bridge U_B(.clk(clk));
    Consumer U_D(.clk(clk));
endmodule

module Bridge(clk);
    input clk;
    Producer U_C(.clk(clk));
endmodule

module Producer(clk);
    input clk;
    wire [7:0] fifo_rd;
    assign fifo_rd = 8'h3C;
endmodule

module Consumer(clk);
    input clk;
    wire [7:0] fifo_rd_in;
endmodule
