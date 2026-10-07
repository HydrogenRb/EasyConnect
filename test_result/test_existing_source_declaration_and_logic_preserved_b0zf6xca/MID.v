module MID (input wire clk
    output wire [8 -1:0] sig
,);
 SRC U_SRC (.clk(clk)
        .ec_c0001_sig_out(sig)
,);
endmodule
