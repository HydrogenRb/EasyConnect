module MID(input clk
    output wire ec_c0001_existing_out
,);
    assign ec_c0001_existing_out = existing;
 wire existing; SRC U_SRC(.clk(clk), .sig(existing)); endmodule
