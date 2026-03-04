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
/*
实现思想：
    对于有符号小于比较，如果 a, b 的符号位不同，则符号位为 1 的那个数更小；若符号位相同，则根据 diff=a-b 的符号位进行判断，如果 diff 的符号位为 1，则 a 更小
    对于无符号小于比较，直接根据 a-b 的结果进位 co 进行判断，如果 co 为 1，说明 a >= b；否则则有 a < b。
        具体原理：-b 在本问题中等同于 2^32 - b，a - b 等同于 a + 2^32 - b（33 位下的结果）。
        如果 a >= b，说明第 33 位保持为 1（2^32 不会被拆散）；否则第 33 位为 0（a - b 不够减，向 2^32 位借位，2^32 被拆散）
        所以 co 在这里实际上表示了借位情况，如果 a >= b，则 co = 1；否则 co = 0
*/

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
