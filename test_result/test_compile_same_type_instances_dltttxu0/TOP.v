module TOP (input wire clk);
    wire w_sig;

 MID U_MID (.clk(clk));
 DST U_DST (.clk(clk),
        .sig(w_sig),

        .recv(1'b0)
);
 DST U_UNUSED (.clk(clk),
        .recv(w_sig),

        .sig()
);
endmodule
