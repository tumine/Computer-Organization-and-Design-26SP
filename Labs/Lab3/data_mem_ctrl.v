module data_mem_ctrl (
    input  wire [31:0] addr,
    input  wire [2:0]  funct3,
    input  wire        mem_write,
    input  wire        mem_read,
    input  wire [31:0] wdata_in,    // 来自寄存器 rdata2
    input  wire [31:0] rdata_in,    // 来自内存返回的值
    output reg  [31:0] wdata_out,   // 处理后的写数据
    output reg  [3:0]  we_mask,     // 给 Data Memory 的位选信号
    output reg  [31:0] rdata_out    // 经符号扩展后的读回数据
);

    wire [1:0] offset = addr[1:0];

    // 处理写操作掩码和数据
    always @(*) begin
        we_mask = 4'b0000;
        wdata_out = wdata_in;
        if (mem_write) begin
            case (funct3)
                3'b000: begin // SB
                    wdata_out = {4{wdata_in[7:0]}}; // 将字节复制到所有通道，靠 mask 控制写入
                    we_mask = 4'b0001 << offset;
                end
                3'b001: begin // SH
                    wdata_out = {2{wdata_in[15:0]}}; 
                    // 要求地址总是半字对齐，如果出现非法 offset 则不做写入操作
                    we_mask = (offset[0]) ? 4'b0000 : ((offset[1]) ? 4'b1100 : 4'b0011);
                end
                3'b010: begin // SW
                    wdata_out = wdata_in;
                    we_mask = 4'b1111;
                end
                default: we_mask = 4'b0000;
            endcase
        end
    end

    // 处理读操作符号扩展
    always @(*) begin
        rdata_out = 32'b0;
        if (mem_read) begin
            case (funct3)
                3'b000: begin // LB
                    case(offset)
                        2'b00: rdata_out = {{24{rdata_in[7]}}, rdata_in[7:0]};
                        2'b01: rdata_out = {{24{rdata_in[15]}}, rdata_in[15:8]};
                        2'b10: rdata_out = {{24{rdata_in[23]}}, rdata_in[23:16]};
                        2'b11: rdata_out = {{24{rdata_in[31]}}, rdata_in[31:24]};
                    endcase
                end
                3'b100: begin // LBU
                    case(offset)
                        2'b00: rdata_out = {24'b0, rdata_in[7:0]};
                        2'b01: rdata_out = {24'b0, rdata_in[15:8]};
                        2'b10: rdata_out = {24'b0, rdata_in[23:16]};
                        2'b11: rdata_out = {24'b0, rdata_in[31:24]};
                    endcase
                end
                3'b001: begin // LH
                    if (offset[0])      rdata_out = 32'b0;  // 排除非法 offset 的读取请求
                    else if (offset[1]) rdata_out = {{16{rdata_in[31]}}, rdata_in[31:16]};
                    else                rdata_out = {{16{rdata_in[15]}}, rdata_in[15:0]};
                end
                3'b101: begin // LHU
                    if (offset[0])      rdata_out = 32'b0;  // 排除非法 offset 的读取请求
                    else if (offset[1]) rdata_out = {16'b0, rdata_in[31:16]};
                    else                rdata_out = {16'b0, rdata_in[15:0]};
                end
                3'b010: begin // LW
                    rdata_out = rdata_in;
                end
                default: rdata_out = 32'b0;
            endcase
        end
    end
endmodule
