module MID (input wire clk,
    input wire recv
);
 SRC U_SRC (.clk(clk),
        .recv(recv)
);
 SRC U_EXTRA(.clk(clk),
        .recv(1'b0)
);
endmodule
