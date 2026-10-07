module TOP (input wire clk);
    wire w_sig;

 MID U_MID (.clk(clk),
        .sig(w_sig)
);
 DST U_DST (.clk(clk),
        .recv(w_sig),

        .other(1'b0)
);
 DST U_UNUSED (.clk(clk),
        .other(w_sig),

        .recv(1'b0)
);
endmodule
