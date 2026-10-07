module MID (input wire clk
    output wire sig // debug bridge
,);
 SRC U_SRC (.clk(clk)
        .sig(sig) // debug bridge
,);
endmodule
