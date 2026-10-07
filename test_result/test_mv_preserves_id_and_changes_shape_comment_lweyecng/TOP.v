module TOP (input wire clk);
    wire [8 -1:0] w_renamed; // new

 MID U_MID (.clk(clk),
        .renamed(w_renamed) // new
);
 DST U_DST (.clk(clk),
        .new_recv(w_renamed) // new
);
 DST U_UNUSED (.clk(clk),
        .new_recv({((8)){1'b0}}) // new
);
endmodule
