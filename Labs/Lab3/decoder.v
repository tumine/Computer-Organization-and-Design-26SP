module decoder(
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    input  wire       cmp_res,

    // 译码器输出控制信号
    output reg        pc_sel,       // PCMUX
    output reg        rf_we,        // 寄存器堆的写使能
    output reg  [1:0] wb_sel,       // 向寄存器堆中写入的数据 MUX
    output reg        alu_src_a,    // ALU-A 操作数 MUX（0-sr1; 1-PC）
    output reg        alu_src_b,    // ALU-B 操作数 MUX（0-sr2; 1-imm）
    output reg  [4:0] alu_op,       // 运算操作码，注意需要与 alu.v 中的操作码对应保持一致
    output reg  [2:0] cmp_op,       // 比较操作类型
    output reg        mem_write,    // 内存写使能
    output reg        mem_read,     // 内存读使能
    output reg        halt          // 停机
);

    // Opcodes
    localparam R_TYPE = 7'b0110011;
    localparam I_TYPE = 7'b0010011;
    localparam LOAD   = 7'b0000011;
    localparam STORE  = 7'b0100011;
    localparam BRANCH = 7'b1100011;
    localparam JAL    = 7'b1101111;
    localparam JALR   = 7'b1100111;
    localparam LUI    = 7'b0110111;
    localparam AUIPC  = 7'b0010111;
    localparam SYSTEM = 7'b1110011; // 包含 ebreak

    // 以下部分如有修改，建议从 alu.v 中直接复制
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
    localparam MUL      = 5'd11;
    localparam MULH     = 5'd12;
    localparam MULHSU   = 5'd13;
    localparam MULHU    = 5'd14;
    localparam DIV      = 5'd15;
    localparam DIVU     = 5'd16;
    localparam REM      = 5'd17;
    localparam REMU     = 5'd18;
    // ---------------------

    always @(*) begin
        // 各个控制信号默认值
        pc_sel    = 0;
        rf_we     = 0;
        wb_sel    = 2'b00;
        alu_src_a = 0;
        alu_src_b = 0;
        alu_op    = 5'd0; 
        cmp_op    = funct3; // 通常直接对应 funct3
        mem_write = 0;
        mem_read  = 0;
        halt      = 0;

        case (opcode)
            R_TYPE: begin
                rf_we = 1;      // R 型指令需要写入寄存器
                wb_sel = 2'b00; // 选通 ALU 计算结果
                alu_src_a = 0;  // 选通寄存器读出 rs1
                alu_src_b = 0;  // 选通寄存器读出 rs2

                // 根据 funct7 决定是否是 M 扩展指令
                // 可参考：https://blog.csdn.net/zyhse/article/details/136300574
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: alu_op = MUL;
                        3'b001: alu_op = MULH;
                        3'b010: alu_op = MULHSU;
                        3'b011: alu_op = MULHU;
                        3'b100: alu_op = DIV;
                        3'b101: alu_op = DIVU;
                        3'b110: alu_op = REM;
                        3'b111: alu_op = REMU;
                    endcase
                end
                else begin
                    case (funct3)
                        3'b000: alu_op = funct7[5] ? SUB : ADD;   // add(funct7[5] == 0) / sub(funct7[5] == 1)
                        3'b001: alu_op = SLL;
                        3'b010: alu_op = SLT;
                        3'b011: alu_op = SLTU;
                        3'b100: alu_op = XOR;
                        3'b101: alu_op = funct7[5] ? SRA : SRL;   // srl(funct7[5] == 0) / sra(funct7[5] == 1)
                        3'b110: alu_op = OR;
                        3'b111: alu_op = AND;
                    endcase
                end
            end

            I_TYPE: begin
                rf_we = 1;      // I 型指令需要写入寄存器
                wb_sel = 2'b00; // 选通 ALU 计算结果
                alu_src_a = 0;  // 选通寄存器读出 rs1
                alu_src_b = 1;  // 选通立即数 imm

                case (funct3)
                    3'b000: alu_op = ADD;   // addi
                    3'b001: alu_op = SLL;   // slli
                    3'b010: alu_op = SLT;   // slti
                    3'b011: alu_op = SLTU;  // sltiu
                    3'b100: alu_op = XOR;   // xori
                    3'b101: alu_op = funct7[5] ? SRA : SRL;     // srli(funct7[5] == 0) / srai(funct7[5] == 1)
                    3'b110: alu_op = OR;    // ori
                    3'b111: alu_op = AND;   // andi
                endcase
            end

            LOAD: begin         // LOAD 属于 I 型指令
                rf_we = 1;      // LOAD 指令需要写入寄存器
                wb_sel = 2'b01; // 选通内存读出数据
                alu_src_a = 0;  // 选通寄存器读出 rs1
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = ADD;   // 计算内存地址
                mem_read = 1;   // 内存读使能
            end

            STORE: begin        // sb, sh, sw 属于 S 型指令
                alu_src_a = 0;  // 选通寄存器读出 rs1
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = ADD;   // 计算内存地址
                mem_write = 1;  // 内存写使能
            end
            
            BRANCH: begin       // SB 型指令
                alu_src_a = 1;  // 选通 PC
                alu_src_b = 1;  // 选通立即数 imm
                alu_op    = ADD;
                pc_sel    = cmp_res;          // 如果比较成立，PC 跳转到 ALU 结果
            end

            JAL: begin          // JAL 指令属于 UJ 型指令
                rf_we = 1;      // JAL 指令需要写入寄存器 (保存返回地址)
                wb_sel = 2'b10; // 选通 PC + 4 (作为返回地址写入)
                alu_src_a = 1;  // 选通 PC
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = ADD;   // 计算跳转目标地址 (PC + imm)
                pc_sel = 1;     // 无条件跳转
            end

            JALR: begin         // JALR 指令属于 I 型指令
                rf_we = 1;      // JALR 指令需要写入寄存器 (保存返回地址)
                wb_sel = 2'b10; // 选通 PC + 4 (作为返回地址写入)
                alu_src_a = 0;  // 选通寄存器读出 rs1
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = ADD;   // 计算跳转目标地址 (rs1 + imm)
                pc_sel = 1;     // 无条件跳转
            end

            LUI: begin          // LUI 指令属于 U 型指令
                rf_we = 1;      // LUI 指令需要写入寄存器
                wb_sel = 2'b00; // 选通 ALU 计算结果
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = B_OUT; // 直接输出 B (即立即数)
            end

            AUIPC: begin        // AUIPC 指令属于 U 型指令
                rf_we = 1;      // AUIPC 指令需要写入寄存器
                wb_sel = 2'b00; // 选通 ALU 计算结果
                alu_src_a = 1;  // 选通 PC
                alu_src_b = 1;  // 选通立即数 imm
                alu_op = ADD;   // 计算 PC + imm
            end
            
            SYSTEM: begin
                if (funct3 == 3'b000 && funct7 == 7'b0000000) begin
                    // 遇到 ebreak (000000000001_00000_000_00000_1110011) 停机
                    halt = 1; 
                end
            end

            default: begin
                rf_we     = 0;
                mem_write = 0;
                mem_read  = 0;
                halt      = 0;
            end
        endcase
    end
endmodule
