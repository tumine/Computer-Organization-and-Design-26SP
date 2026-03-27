`timescale 1ns / 1ps

// ========================================================
// 行为级仿真替代模块：替代 blk_mem_gen_1 IP 核
// 用于排查 IP 核配置问题（ena/enb、wea 位宽、初始化等）
// 使用方法：在仿真时将此文件加入 Simulation Sources，
//          Vivado 会优先使用此模块而非 IP 核的仿真模型
// ========================================================
module blk_mem_gen_1 (
    input  wire        clka,
    input  wire        wea,
    input  wire [9:0]  addra,
    input  wire [31:0] dina,
    output reg  [31:0] douta,

    input  wire        clkb,
    input  wire        web,
    input  wire [9:0]  addrb,
    input  wire [31:0] dinb,
    output reg  [31:0] doutb
);

    // 1024 x 32-bit 存储器
    reg [31:0] ram [0:1023];

    // 使用与 Task3 相同的初始化数据
    initial begin
        $readmemh("E:/Computer-Organization-and-Design-26SP/Labs/Lab1/Task3/attachments/data.txt", ram);
    end

    // Write-First 模式，端口 A
    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
            douta <= dina;        // write-first: 输出新写入的数据
        end else begin
            douta <= ram[addra];  // 正常读取
        end
    end

    // Write-First 模式，端口 B
    always @(posedge clkb) begin
        if (web) begin
            ram[addrb] <= dinb;
            doutb <= dinb;        // write-first: 输出新写入的数据
        end else begin
            doutb <= ram[addrb];  // 正常读取
        end
    end

endmodule
