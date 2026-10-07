module TOP (input wire clk);
    wire [16 -1:0] w_renamed;

 MID U_MID (.clk(clk),
        .renamed(w_renamed)
);
 DST U_DST (.clk(clk),
        .recv(w_renamed)
);
 DST U_UNUSED (.clk(clk),
        .recv({((16)){1'b0}})
);
endmodule
