module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [4:0]  op,
    output reg  [31:0] out
);
    // ALU 操作码定义
    localparam ADD  = 5'd0;
    localparam SUB  = 5'd1;
    localparam SLL  = 5'd2;
    localparam SRL  = 5'd3;
    localparam SRA  = 5'd4;
    localparam AND  = 5'd5;
    localparam OR   = 5'd6;
    localparam XOR  = 5'd7;
    localparam SLT  = 5'd8;
    localparam SLTU = 5'd9;
    localparam B_OUT= 5'd10; // 直接输出 B（用于 LUI 指令）
    // RV32M 扩展
    localparam MUL  = 5'd11;
    localparam MULH = 5'd12;
    localparam MULHU= 5'd13;
    localparam DIV  = 5'd14;
    localparam DIVU = 5'd15;
    localparam REM  = 5'd16;
    localparam REMU = 5'd17;

    wire signed [31:0] signed_a = a;
    wire signed [31:0] signed_b = b;
    wire signed [63:0] signed_mul_res = signed_a * signed_b;
    wire [63:0]        unsigned_mul_res = a * b;

    always @(*) begin
        case (op)
            ADD:  out = a + b;
            SUB:  out = a - b;
            SLL:  out = a << b[4:0];
            SRL:  out = a >> b[4:0];
            SRA:  out = signed_a >>> b[4:0];
            AND:  out = a & b;
            OR:   out = a | b;
            XOR:  out = a ^ b;
            SLT:  out = (signed_a < signed_b) ? 32'd1 : 32'd0;
            SLTU: out = (a < b) ? 32'd1 : 32'd0;
            B_OUT:out = b;
            
            MUL:  out = unsigned_mul_res[31:0];
            MULH: out = signed_mul_res[63:32];
            MULHU:out = unsigned_mul_res[63:32];
            DIV:  out = (b == 0) ? -1 : (signed_a / signed_b);
            DIVU: out = (b == 0) ? -1 : (a / b);
            REM:  out = (b == 0) ? a : (signed_a % signed_b);
            REMU: out = (b == 0) ? a : (a % b);
            
            default: out = 32'b0;
        endcase
    end
endmodule
