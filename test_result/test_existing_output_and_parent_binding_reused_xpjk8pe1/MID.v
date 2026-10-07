module MID(input clk,
    output wire ec_c0001_existing_out
); wire existing; SRC U_SRC(.clk(clk), .sig(existing)); 
    assign ec_c0001_existing_out = existing;
endmodule
