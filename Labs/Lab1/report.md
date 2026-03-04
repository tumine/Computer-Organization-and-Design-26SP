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

### BRAM写优先模式下为什么在第二个上升沿才能读出新值

在FPGA设计中，Block RAM (BRAM) 设置为**写优先 (Write First)** 时，通常在第二个上升沿才能读出新值，主要是由**同步数字电路的采样机制**以及**BRAM的固有结构延迟**决定的：

1. **同步电路的跨拍采样特性**：
   - **第1个上升沿**：BRAM 捕获有效的地址、写使能和写数据，写操作被触发。此时因为配置为“写优先”，写入的数据被内部逻辑直接更新到输出数据端口 (DOUT)。DOUT 的电平在第1个上升沿之后的一小段延迟时间内发生翻转并保持稳定。
   - **第2个上升沿**：尽管 DOUT 端在第1个周期内已准备好新数据，但下游连接的寄存器（如 Testbench 中的采样逻辑）是同步器件，必须等到下一个时钟边沿到来时，才能将 DOUT 上的新电平正式**锁存**。因此从外部观测，成功采到新值是以第2个沿为标志的。

2. **BRAM 的输出寄存器延迟**：
   - 现代 FPGA 的 BRAM 内部通常带有可选的**一级输出寄存器 (Output Register)** 以改善时序。如果开启了输出寄存器，读操作的潜伏期会增加 1 个时钟周期。
   - 在这种情况下，第1个上升沿将数据传送到内部只读节点，第2个上升沿时 BRAM 内置的输出寄存器才将数据真正打出到输出管脚 DOUT。

**总结**：“写优先”解决了同一节拍内读写同一地址时的读旧数据问题，但是因为一切更新都发生在该时钟节拍内，外部同步逻辑去采集这个新输出的信号，在物理时序上必然需要依靠下一个系统时钟边沿（即第二个上升沿）来完成锁存采样。

### 补充：为什么配置为读优先或写优先，都不影响读出数据的时机？

BRAM 的“写优先 (Write First)”、“读优先 (Read First)”以及“保持 (No Change)”这几种模式，**仅决定了在发生写操作的那个时钟周期内，BRAM 输出端口 (DOUT) 被放置什么数据**，而**绝不会改变 BRAM 宏块固有的时序结构与潜伏期 (Latency)**：

1. **时序路径固定**：无论是哪种模式，数据从输入端、经过存储阵列、再到输出端 DOUT 的物理路径延迟和寄存器级数是完全相同的。
2. **读优先的表现**：在发生写操作的第1个上升沿，BRAM 将旧数据输出到 DOUT，新数据写入存储阵列。此时如果要读出刚写入的**新值**，必须发起一次针对同一地址的普通读操作（由于没有命中写连通路径，通常是在第2个周期的上升沿发起地址提取），导致新值其实要在这之后的边沿（第3个边沿）才能被外部采到。
3. **写优先的表现**：在第1个上升沿更新写入的同时，立刻将新值 Bypass 到 DOUT 端。但正如前文所述，外部同步逻辑能切实且稳定地采样到并加以利用这一新值，仍然需要等待第2个上升沿。

也就是说，**模式的切换只改变“输出端在写周期短接给谁”，不改变同步系统跨拍采样的物理必然性与 BRAM 的级数延迟。**
