module TOP (input wire clk);
    wire [8 -1:0] w_sig;

 MID U_MID (.clk(clk),
        .sig(w_sig)
);
 DST U_DST (.clk(clk),
        .ec_c0001_recv_in(w_sig)
);
 DST U_UNUSED (.clk(clk),
        .ec_c0001_recv_in({((8)){1'b0}})
);
endmodule
