`timescale 1ns / 1ps

module memory_compare_tb();
    reg clk;
    reg we;
    reg [9:0] addr;
    reg [31:0] din;
    wire [31:0] dout_dist;          // Distributed RAM 的输出
    wire [31:0] dout_block_wfirst;  // 写优先 BRAM 的输出
    wire [31:0] dout_block_rfirst;  // 读优先 BRAM 的输出    

    // 实例化 Distributed RAM
    dist_mem_gen_0 dist_mem (
        .a(addr), .d(din), .clk(clk), .we(we), .spo(dout_dist)
    );

    // 实例化 Block RAM（写优先，ENA Pin 始终启用）
    blk_mem_gen_0 blk_mem_wfirst (
        .clka(clk), .wea(we), .addra(addr), .dina(din), .douta(dout_block_wfirst)
    );

    // 实例化 Block RAM（读优先，ENA Pin 始终启用）
    blk_mem_gen_1 blk_mem_rfirst (
        .clka(clk), .wea(we), .addra(addr), .dina(din), .douta(dout_block_rfirst)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; we = 0; addr = 0; din = 0;
        #20;

        // 向目标地址 10 写入数据 0xABCD1234（同步）
        @(posedge clk); // 等待时钟上升沿（对齐）
        addr = 10'd10; din = 32'hABCD1234; we = 1;
        @(posedge clk); // 该上升沿 Distributed RAM 写入新值并立即读出新值
        @(posedge clk); // 该上升沿 BRAM 写入新值，写优先 BRAM 读出新值
        @(posedge clk); // 该上升沿读优先 BRAM 读出新值
        #5;
        we = 0;

        #10;
        // 在目标地址不变的情况下，写入新数据
        @(posedge clk);
        din = 32'h1234ABCD; we = 1;
        @(posedge clk); // 该上升沿 Distributed RAM 写入新值并立即读出新值
        @(posedge clk); // 该上升沿 BRAM 写入新值，写优先 BRAM 读出新值
        @(posedge clk); // 该上升沿读优先 BRAM 读出新值
        #5;
        we = 0;

        // 改变目标地址到 0
        @(posedge clk);
        #5;
        addr = 10'd0; // distributed RAM 立即读出新值
        @(posedge clk); // 该上升沿两种 BRAM 仍未读出新值
        @(posedge clk); // 该上升沿两种 BRAM 同时读出新值
        
        
        #20 $finish;
    end
endmodule
