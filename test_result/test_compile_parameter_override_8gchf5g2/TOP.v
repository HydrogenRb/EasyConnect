module TOP (input wire clk);
    wire [4 -1:0] w_sig;

 MID U_MID (.clk(clk),
        .sig(w_sig)
);
 DST U_DST (.clk(clk),
        .recv(w_sig)
);
 DST U_UNUSED (.clk(clk),
        .recv({((4)){1'b0}})
);
endmodule
