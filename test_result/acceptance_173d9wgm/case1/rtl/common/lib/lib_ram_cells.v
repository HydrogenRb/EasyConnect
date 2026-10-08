//==========================================================================
//  lib_ram_cells.v
//  工艺库 RAM 宏单元（黑盒式行为模型）
//
//  Ref: 模仿 memory compiler 生成的 SP / DP / 2P 宏单元接口，
//       例如 SPSRAM1024X32、SPHD、RAMB18E1 wrapper、altsyncram 等
//       在真实项目里被直接实例化的那一层。
//
//  本文件只提供"库单元"，不含任何层次例化 —— 它们是层次树的叶子。
//  信号极性约定（与多数商用库一致）：
//     CEN  : active-low  chip enable
//     WEN  : active-low  write enable
//     BEN  : active-low  byte write enable（每位对应一个字节通道）
//     A_CEN/A_WEN/A_BEN, B_CEN/B_WEN : 双口版本同义
//  所有端口都是 ANSI 声明，位宽全部来自 lib_define.v 的宏。
//==========================================================================
`include "lib_define.v"

//------------------------------------------------------------------
// RAM_SP : 单口同步 RAM（写同步、读同步）
//
// 宏单元几何默认为 lib_define.v 中的值，例化时可以用 #( .AW(..), .DW(..) )
// 覆盖；端口位宽仍然是固定 32/10 的宏单元引脚，这是真实库单元的写法。
//------------------------------------------------------------------
module RAM_SP (
    input  wire                       CLK,
    input  wire                       CEN,
    input  wire                       WEN,
    input  wire [`LIB_RAM_BEN_W-1:0]  BEN,
    input  wire [`LIB_RAM_ADDR_W-1:0] ADDR,
    input  wire [`LIB_RAM_DATA_W-1:0] D,
    output reg  [`LIB_RAM_DATA_W-1:0] Q
);

    parameter AW = `LIB_RAM_ADDR_W;
    parameter DW = `LIB_RAM_DATA_W;
    parameter DEPTH = `LIB_RAM_DEPTH;

    reg [`LIB_RAM_DATA_W-1:0] mem [0:DEPTH-1];
    integer                   i;

    initial begin
        for (i = 0; i < `LIB_RAM_DEPTH; i = i + 1) begin
            mem[i] = {`LIB_RAM_DATA_W{1'b0}};
        end
    end

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!WEN) begin
                if (!BEN[0]) mem[ADDR][7:0]   <= D[7:0];
                if (!BEN[1]) mem[ADDR][15:8]  <= D[15:8];
                if (!BEN[2]) mem[ADDR][23:16] <= D[23:16];
                if (!BEN[3]) mem[ADDR][31:24] <= D[31:24];
            end
            Q <= mem[ADDR];
        end
    end

endmodule

//------------------------------------------------------------------
// RAM_SP_BE : 单口同步 RAM，字节使能版本（读优先）
//------------------------------------------------------------------
module RAM_SP_BE (
    input  wire                       CLK,
    input  wire                       CEN,
    input  wire                       WEN,
    input  wire [`LIB_RAM_BEN_W-1:0]  BEN,
    input  wire [`LIB_RAM_ADDR_W-1:0] ADDR,
    input  wire [`LIB_RAM_DATA_W-1:0] D,
    output reg  [`LIB_RAM_DATA_W-1:0] Q
);

    parameter AW = `LIB_RAM_ADDR_W;
    parameter DW = `LIB_RAM_DATA_W;
    parameter DEPTH = `LIB_RAM_DEPTH;

    reg [`LIB_RAM_DATA_W-1:0] mem [0:DEPTH-1];
    integer                   i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {`LIB_RAM_DATA_W{1'b0}};
        end
    end

    always @(posedge CLK) begin
        if (!CEN) begin
            Q <= mem[ADDR];
            if (!WEN) begin
                if (!BEN[0]) mem[ADDR][7:0]   <= D[7:0];
                if (!BEN[1]) mem[ADDR][15:8]  <= D[15:8];
                if (!BEN[2]) mem[ADDR][23:16] <= D[23:16];
                if (!BEN[3]) mem[ADDR][31:24] <= D[31:24];
            end
        end
    end

endmodule

//------------------------------------------------------------------
// RAM_DP : 真双口 RAM（A/B 两口对称，各自读写）
//------------------------------------------------------------------
module RAM_DP (
    input  wire                         CLK,
    input  wire                         A_CEN,
    input  wire                         A_WEN,
    input  wire [`LIB_RAM_A_ADDR_W-1:0] A_ADDR,
    input  wire [`LIB_RAM_A_DATA_W-1:0] A_D,
    output reg  [`LIB_RAM_A_DATA_W-1:0] A_Q,
    input  wire                         B_CEN,
    input  wire                         B_WEN,
    input  wire [`LIB_RAM_B_ADDR_W-1:0] B_ADDR,
    input  wire [`LIB_RAM_B_DATA_W-1:0] B_D,
    output reg  [`LIB_RAM_B_DATA_W-1:0] B_Q
);

    parameter AW = `LIB_RAM_A_ADDR_W;
    parameter DW = `LIB_RAM_DATA_W;
    parameter DEPTH = `LIB_RAM_DEPTH;

    reg [`LIB_RAM_DATA_W-1:0] mem [0:DEPTH-1];
    integer                   i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {`LIB_RAM_DATA_W{1'b0}};
        end
    end

    always @(posedge CLK) begin
        if (!A_CEN) begin
            A_Q <= mem[A_ADDR];
            if (!A_WEN) begin
                mem[A_ADDR] <= A_D;
            end
        end
    end

    always @(posedge CLK) begin
        if (!B_CEN) begin
            B_Q <= mem[B_ADDR];
            if (!B_WEN) begin
                mem[B_ADDR] <= B_D;
            end
        end
    end

endmodule

//------------------------------------------------------------------
// RAM_2P : 简单双口 RAM（A 口只写、B 口只读）
//------------------------------------------------------------------
module RAM_2P (
    input  wire                         CLK,
    input  wire                         A_CEN,
    input  wire                         A_WEN,
    input  wire [`LIB_RAM_A_ADDR_W-1:0] A_ADDR,
    input  wire [`LIB_RAM_A_DATA_W-1:0] A_D,
    input  wire                         B_CEN,
    input  wire [`LIB_RAM_B_ADDR_W-1:0] B_ADDR,
    output reg  [`LIB_RAM_B_DATA_W-1:0] B_Q
);

    parameter AW = `LIB_RAM_A_ADDR_W;
    parameter DW = `LIB_RAM_DATA_W;
    parameter DEPTH = `LIB_RAM_DEPTH;

    reg [`LIB_RAM_DATA_W-1:0] mem [0:DEPTH-1];
    integer                   i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = {`LIB_RAM_DATA_W{1'b0}};
        end
    end

    always @(posedge CLK) begin
        if (!A_CEN) begin
            if (!A_WEN) begin
                mem[A_ADDR] <= A_D;
            end
        end
    end

    always @(posedge CLK) begin
        if (!B_CEN) begin
            B_Q <= mem[B_ADDR];
        end
    end

endmodule
