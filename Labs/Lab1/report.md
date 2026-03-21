## Task 1
### Task 1-1
```Verilog
module Adder_LookAhead8_1_1 (
    input                   [ 7 : 0]            a, b,
    input                   [ 0 : 0]            ci,         // 来自低位的进位
    output                  [ 7 : 0]            s,          // 和
    output                  [ 0 : 0]            co          // 向高位的进位
);

wire    [7:0] C;
wire    [7:0] G;
wire    [7:0] P;

assign  G = a & b;
assign  P = a ^ b;

assign  C[0] = G[0] | ( P[0] & ci );
assign  C[1] = G[1] | ( P[1] & G[0] ) | ( P[1] & P[0] & ci );
assign  C[2] = G[2] | ( P[2] & G[1] ) | ( P[2] & P[1] & G[0] ) | ( P[2] & P[1] & P[0] & ci );
assign  C[3] = G[3] | ( P[3] & G[2] ) | ( P[3] & P[2] & G[1] ) | ( P[3] & P[2] & P[1] & G[0] ) | ( P[3] & P[2] & P[1] & P[0] & ci );
assign  C[4] = G[4] | ( P[4] & G[3] ) | ( P[4] & P[3] & G[2] ) | ( P[4] & P[3] & P[2] & G[1] ) | ( P[4] & P[3] & P[2] & P[1] & G[0] ) | ( P[4] & P[3] & P[2] & P[1] & P[0] & ci );
assign  C[5] = G[5] | ( P[5] & G[4] ) | ( P[5] & P[4] & G[3] ) | ( P[5] & P[4] & P[3] & G[2] ) | ( P[5] & P[4] & P[3] & P[2] & G[1] ) | ( P[5] & P[4] & P[3] & P[2] & P[1] & G[0] ) | ( P[5] & P[4] & P[3] & P[2] & P[1] & P[0] & ci );
assign  C[6] = G[6] | ( P[6] & G[5] ) | ( P[6] & P[5] & G[4] ) | ( P[6] & P[5] & P[4] & G[3] ) | ( P[6] & P[5] & P[4] & P[3] & G[2] ) | ( P[6] & P[5] & P[4] & P[3] & P[2] & G[1] ) | ( P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & G[0] ) | ( P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & P[0] & ci );
assign  C[7] = G[7] | ( P[7] & G[6] ) | ( P[7] & P[6] & G[5] ) | ( P[7] & P[6] & P[5] & G[4] ) | ( P[7] & P[6] & P[5] & P[4] & G[3] ) | ( P[7] & P[6] & P[5] & P[4] & P[3] & G[2] ) | ( P[7] & P[6] & P[5] & P[4] & P[3] & P[2] & G[1] ) | ( P[7] & P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & G[0] ) | ( P[7] & P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & P[0] & ci );

assign  s[0] = P[0] ^ ci;
assign  s[1] = P[1] ^ C[0];
assign  s[2] = P[2] ^ C[1];
assign  s[3] = P[3] ^ C[2];
assign  s[4] = P[4] ^ C[3];
assign  s[5] = P[5] ^ C[4];
assign  s[6] = P[6] ^ C[5];
assign  s[7] = P[7] ^ C[6];
assign  co   = C[7];

endmodule

module Adder32_1_1 (
    input                   [31 : 0]        a, b,
    input                   [ 0 : 0]        ci,
    output                  [31 : 0]        s,
    output                  [ 0 : 0]        co
);
wire    [2:0] cmid;
Adder_LookAhead8_1_1 adder8_0(
    .a(a[7:0]),
    .b(b[7:0]),
    .ci(ci),
    .s(s[7:0]),
    .co(cmid[0])
);
Adder_LookAhead8_1_1 adder8_1(
    .a(a[15:8]),
    .b(b[15:8]),
    .ci(cmid[0]),
    .s(s[15:8]),
    .co(cmid[1])
);
Adder_LookAhead8_1_1 adder8_2(
    .a(a[23:16]),
    .b(b[23:16]),
    .ci(cmid[1]),
    .s(s[23:16]),
    .co(cmid[2])
);
Adder_LookAhead8_1_1 adder8_3(
    .a(a[31:24]),
    .b(b[31:24]),
    .ci(cmid[2]),
    .s(s[31:24]),
    .co(co)
);

endmodule

module AddSub_1_1 (
    input                   [31 : 0]        a, b,
    output                  [31 : 0]        out,
    output                  [ 0 : 0]        co
);
Adder32_1_1 addsub(
    .a(a),
    .b(~b),
    .ci(1'b1),
    .s(out),
    .co(co)
);

endmodule

module Comp_1_1 (
    input                   [31 : 0]        a, b,
    output                  [ 0 : 0]        ul, // 无符号数比较
    output                  [ 0 : 0]        sl  // 有符号数比较
);

wire [31 : 0]   diff;
wire            sub_co;
AddSub_1_1 comp_sub(
    .a(a),
    .b(b),
    .out(diff),
    .co(sub_co)
);
assign sl = (a[31] ^ b[31]) ? (a[31] ? 1 : 0) : (diff[31] ? 1 : 0);
assign ul = ~sub_co;

endmodule

// 选择器
module Src1_1_1 (
    input                   [31 : 0]        a, b,
    output                  [31 : 0]        out
);

assign out = a;
endmodule

module ALU_1_1(
    input                   [31 : 0]        src0,
    input                   [31 : 0]        src1,
    input                   [3  : 0]        op,
    output                  [31 : 0]        res
);

wire        [12:0] sel = 13'b1 << op;

wire signed [31:0] signed_src0 = src0;

wire        [31:0] add_out;
wire        [31:0] sub_out;
wire        [0 :0] slt_out;
wire        [0 :0] sltu_out;
wire        [31:0] src1_out;

Adder32_1_1 alu_add(
    .a(src0),
    .b(src1),
    .ci(1'B0),
    .s(add_out),
    .co()
);

AddSub_1_1 alu_sub(
    .a(src0),
    .b(src1),
    .out(sub_out),
    .co()
);

Comp_1_1 alu_comp(
    .a(src0),
    .b(src1),
    .ul(sltu_out),
    .sl(slt_out)
);

Src1_1_1 alu_src1(
    .a(src0),
    .b(src1),
    .out(src1_out)
);

wire [31:0] and_out = src0 & src1;
wire [31:0] or_out  = src0 | src1;
wire [31:0] nor_out = ~(src0 | src1);
wire [31:0] xor_out = src0 ^ src1;
wire [31:0] sll_out = src0 << src1[4:0];
wire [31:0] srl_out = src0 >> src1[4:0];
wire [31:0] sra_out = signed_src0 >>> src1[4:0];

assign res = ({32{sel[ 0]}} & add_out          ) | 
             ({32{sel[ 1]}} & sub_out          ) |
             ({32{sel[ 2]}} & {31'b0, slt_out} ) |
             ({32{sel[ 3]}} & {31'b0, sltu_out}) |
             ({32{sel[ 4]}} & and_out          ) |
             ({32{sel[ 5]}} & or_out           ) |
             ({32{sel[ 6]}} & nor_out          ) |
             ({32{sel[ 7]}} & xor_out          ) |
             ({32{sel[ 8]}} & sll_out          ) |
             ({32{sel[ 9]}} & srl_out          ) |
             ({32{sel[10]}} & sra_out          ) |
             ({32{sel[11]}} & src1_out         );

endmodule
```

## Task 2
本任务使用的 testbench 文件如下：
```Veriog
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

    // 实例化 Block RAM（写优先）
    blk_mem_gen_0 blk_mem_wfirst (
        .clka(clk), .wea(we), .addra(addr), .dina(din), .douta(dout_block_wfirst)
    );

    // 实例化 Block RAM（读优先）
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
```
在仿真波形中看到，在一个时钟上升沿尝试写入的同时读数据时，Distributed RAM 在下一个上升沿读出新值，写优先的 BRAM 在下两个上升沿读出新值，读优先的 BRAM 在下三个上升沿读出新值；当只做读取数据的操作时，Distributed RAM 立即读出新值，BRAM 在下两个上升沿读出新值。
- 当 BRAM 端口设置中的 `Primitives Output Register` 开关被关闭时，两种 BRAM 的时序均**提前一个时钟周期**，即：同时读写时写优先的 BRAM 在下一个上升沿读出新值，读优先的 BRAM 在下两个上升沿读出新值；仅读取时，BRAM 在下一个上升沿读出新值。

Distributed RAM 的读取基于纯粹的组合逻辑，因此可以即时响应任何时候的仅读取请求。对于同时读写的请求，由于 Distributed RAM 采用异步读取、同步写入，因此在当前上升沿新数据即被写入，并通过一个时钟周期的稳定过程后被读出。

打开 `Primitives Output Register` 开关时，BRAM 为了保证在高工作频率下仍能满足建立/保持时间要求，在时序上表现出多周期的潜伏期（具体来说，在本实验的仿真中体现为 2 个时钟周期）。在第一个时钟上升沿，BRAM 主要完成**完成输入信号的采样与同步**，当系统时钟的上升沿到来时，块式存储器的输入端寄存器会将外部总线上的地址、写使能信号以及待写入的数据同步捕获到内部逻辑中。第二个时钟上升沿 BRAM 仍未读出，与 BRAM 为了隔离关键路径而设置数据输出流水线有关。内部核心阵列在第一个时钟周期内完成数据访问后，该数据会被送至输出端，并在第二个时钟上升沿被**输出寄存器**稳定锁存，随后才真正呈现在外部数据总线上。因此，在仅读取请求中，两种 BRAM 都在第二个上升沿处读出新值，而在同时读写请求中，写优先 BRAM 在第二个上升沿处读出新值，读优先 BRAM 在第三个上升沿处读出新值（还需要经过一个时钟周期才能读取新写入该地址的值）。
