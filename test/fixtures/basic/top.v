module top(input wire clk);
    Bridge U_B (.clk(clk));
    Consumer U_D (.clk(clk));
endmodule
