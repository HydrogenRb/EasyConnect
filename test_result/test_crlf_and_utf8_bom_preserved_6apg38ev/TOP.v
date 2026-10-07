module TOP (input wire clk);
    wire w_sig;

 MID U_MID (.clk(clk)
        .sig(w_sig)
,);
 DST U_DST (.clk(clk)
        .recv(w_sig)
,);
 DST U_UNUSED (.clk(clk)
        .recv(1'b0)
,);
endmodule
