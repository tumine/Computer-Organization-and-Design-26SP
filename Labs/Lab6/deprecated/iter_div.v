// 低资源迭代除法器
// 用 32 次移位-比较-减法完成 DIV/DIVU/REM/REMU，替代高 LUT 的组合除法器。
module iter_div (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        is_signed,
    input  wire        is_rem,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    output reg         busy,
    output reg         done,
    output reg  [31:0] result
);

    reg [5:0]  bit_cnt;
    reg        sign_q;
    reg        sign_r;
    reg [31:0] divisor_abs;
    reg [31:0] quotient;
    reg [32:0] remainder;
    reg [31:0] dividend_shift;

    wire dividend_neg = is_signed && dividend[31];
    wire divisor_neg  = is_signed && divisor[31];
    wire [31:0] dividend_abs = dividend_neg ? (~dividend + 32'b1) : dividend;
    wire [31:0] divisor_abs_in = divisor_neg ? (~divisor + 32'b1) : divisor;

    wire [32:0] remainder_shift = {remainder[31:0], dividend_shift[31]};
    wire        can_sub = (remainder_shift >= {1'b0, divisor_abs});
    wire [32:0] remainder_next = can_sub ? (remainder_shift - {1'b0, divisor_abs}) : remainder_shift;
    wire [31:0] quotient_next = {quotient[30:0], can_sub};
    wire [31:0] quotient_signed = sign_q ? (~quotient + 32'b1) : quotient;
    wire [31:0] remainder_signed = sign_r ? (~remainder[31:0] + 32'b1) : remainder[31:0];

    always @(posedge clk) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'b0;
            bit_cnt <= 6'b0;
            sign_q <= 1'b0;
            sign_r <= 1'b0;
            divisor_abs <= 32'b0;
            quotient <= 32'b0;
            remainder <= 33'b0;
            dividend_shift <= 32'b0;
        end
        else begin
            done <= 1'b0;

            if (start && !busy) begin
                if (divisor == 32'b0) begin
                    // 中文注释：按 RISC-V M 扩展约定处理除零。
                    result <= is_rem ? dividend : 32'hFFFFFFFF;
                    done <= 1'b1;
                end
                else begin
                    busy <= 1'b1;
                    bit_cnt <= 6'd32;
                    sign_q <= dividend_neg ^ divisor_neg;
                    sign_r <= dividend_neg;
                    divisor_abs <= divisor_abs_in;
                    quotient <= 32'b0;
                    remainder <= 33'b0;
                    dividend_shift <= dividend_abs;
                end
            end
            else if (busy) begin
                remainder <= remainder_next;
                quotient <= quotient_next;
                dividend_shift <= {dividend_shift[30:0], 1'b0};
                bit_cnt <= bit_cnt - 1'b1;

                if (bit_cnt == 6'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    // 中文注释：最后一轮的商/余数来自本周期计算出的 next 值。
                    result <= is_rem
                            ? (sign_r ? (~remainder_next[31:0] + 32'b1) : remainder_next[31:0])
                            : (sign_q ? (~quotient_next + 32'b1) : quotient_next);
                end
            end
        end
    end

endmodule
