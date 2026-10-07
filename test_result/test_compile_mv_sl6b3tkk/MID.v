module MID (input wire clk,
    output wire [16 -1:0] renamed
);
 SRC U_SRC (.clk(clk),
        .renamed(renamed)
);
endmodule
