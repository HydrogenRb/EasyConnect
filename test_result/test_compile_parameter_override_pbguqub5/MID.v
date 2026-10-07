module MID(input clk,
    output wire [4 -1:0] sig
); SRC #(.W(4)) U_SRC(.clk(clk),
        .ec_c0001_sig_out(sig)
); endmodule
