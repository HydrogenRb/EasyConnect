module TOP (input wire clk);
    assign recv = sig;

    wire recv;

    wire sig;

 MID U_MID (.clk(clk));
 DST U_DST (.clk(clk));
 DST U_UNUSED (.clk(clk));
endmodule
