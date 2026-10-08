module TOP (input wire clk);
    wire sig;

 MID U_MID (.clk(clk),
        .recv(sig)
);
 DST U_DST (.clk(clk));
 DST U_UNUSED (.clk(clk));
 MID U_SECOND(.clk(clk),
        .recv(1'b0)
);
endmodule
