module SRC(input clk,
    output wire [8 -1:0] ec_c0001_sig_out
);
    assign ec_c0001_sig_out = sig;
 reg [7:0] sig; always @(posedge clk) sig<=8'h55; endmodule
