`include "defs.vh"
module MID (input wire clk,
    output wire [`WIDTH -1:0] sig
);
 SRC U_SRC (.clk(clk),
        .sig(sig)
);
endmodule
