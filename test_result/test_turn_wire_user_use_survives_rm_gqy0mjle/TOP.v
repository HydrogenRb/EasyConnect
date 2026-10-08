module TOP (input wire clk);
    wire w_sig;

 MID U_MID (.clk(clk));
 DST U_DST (.clk(clk));
 DST U_UNUSED (.clk(clk));
wire tap; assign tap = w_sig;
endmodule
