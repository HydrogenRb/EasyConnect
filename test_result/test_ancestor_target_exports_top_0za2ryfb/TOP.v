module TOP (input wire clk,
    output wire recv
);
 MID U_MID (.clk(clk),
        .sig(recv)
);
 DST U_DST (.clk(clk));
 DST U_UNUSED (.clk(clk));
endmodule
