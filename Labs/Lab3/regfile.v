// 寄存器堆（三端口双读单写）
module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] wdata,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);

    reg [31:0] regs [0:31];
    
    // 同步写
    always @(posedge clk) begin
        if (we && rd != 5'b0) begin
            regs[rd] <= wdata;
        end
    end
    
    // 异步读
    // 读优先：不关心 rd 是否与 rs1/rs2 冲突
    assign rdata1 = (rs1 == 5'b0) ? 32'b0 : regs[rs1];
    assign rdata2 = (rs2 == 5'b0) ? 32'b0 : regs[rs2];

endmodule
