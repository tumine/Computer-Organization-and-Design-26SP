// 条件跳转的分支判断
module cmp (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op,
    output reg         res
);

    // 比较操作类型，对应指令的 funct3 字段
    localparam BEQ  = 3'b000;
    localparam BNE  = 3'b001;
    localparam BLT  = 3'b100;
    localparam BGE  = 3'b101;
    localparam BLTU = 3'b110;
    localparam BGEU = 3'b111;

    always @(*) begin
        case (op)
            BEQ:  res = (a == b);
            BNE:  res = (a != b);
            BLT:  res = ($signed(a) < $signed(b));
            BGE:  res = ($signed(a) >= $signed(b));
            BLTU: res = (a < b);
            BGEU: res = (a >= b);
            default: res = 1'b0;
        endcase
    end

endmodule
