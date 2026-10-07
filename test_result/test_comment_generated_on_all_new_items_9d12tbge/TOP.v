module TOP (input wire clk);
    wire w_sig; // debug bridge

 MID U_MID (.clk(clk)
        .sig(w_sig) // debug bridge
,);
 DST U_DST (.clk(clk)
        .recv(w_sig) // debug bridge
,);
 DST U_UNUSED (.clk(clk)
        .recv(1'b0) // debug bridge
,);
endmodule
