module TOP (input wire clk);
    wire recv;

    wire sig;

 MID U_MID (.clk(clk));
 DST U_DST (.clk(clk));
 DST U_UNUSED (.clk(clk));

    assign recv = sig;
endmodule
