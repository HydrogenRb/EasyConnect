module Consumer(input wire clk);
    wire [7:0] fifo_rd_in;
    wire [7:0] observed;
    assign observed = fifo_rd_in;
endmodule
