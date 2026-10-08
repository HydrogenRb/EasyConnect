module MID (input wire clk,
    output wire [8 -1:0] sig
);
 SRC U_SRC (.clk(clk),
        .sig(sig[3:0])
);
endmodule
