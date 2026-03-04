module  RF (
    input       [0 : 0]         clk     ,       // 时钟
    input       [4 : 0]         ra0, ra1,       // 读地址
    output  reg [31: 0]         rd0, rd1,       // 读数据
    input       [4 : 0]         wa      ,       // 写地址
    input       [31: 0]         wd      ,       // 写数据
    input       [0 : 0]         we              // 写使能
);
reg [31:0] r[0:31];     // 寄存器堆

// 初始化所有寄存器为 0
integer i;
initial begin
    for (i = 0; i < 32; i = i + 1) begin
        r[i] = 0;
    end
end

// 读寄存器；写优先，异步
always @(*) begin
    if (we && ra0 != 0 && ra0 == wa) // 写优先：如果读写同一地址且非 0 号寄存器
        rd0 = wd;
    else
        rd0 = r[ra0];
    
    if (we && ra1 != 0 && ra1 == wa)
        rd1 = wd;
    else
        rd1 = r[ra1];
end

// TODO: 检查参考仿真结果发现 rd1 可能属于同步读取（rd0 仍为异步读取），需要进一步确认

// 写寄存器（同步）
always  @(posedge clk)
    if (we && wa != 0)  // 只有写使能有效且地址非 0 时才写入
        r[wa] <= wd;
endmodule