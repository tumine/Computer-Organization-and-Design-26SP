module imm_gen (
    input  wire [31:0] inst,
    output reg  [31:0] imm
);

    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case (opcode)
            // I 型指令
            7'b0000011, // LOAD
            7'b0010011, // 普通算术逻辑运算
            7'b1100111: // JALR
                imm = {{20{inst[31]}}, inst[31:20]};
            
            // S 型指令
            7'b0100011: // STORE
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
                
            // SB 型指令
            7'b1100011: // 跳转指令
                imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
                
            // U 型指令
            7'b0110111, // LUI
            7'b0010111: // AUIPC
                imm = {inst[31:12], 12'b0};
                
            // UJ 型指令
            7'b1101111: // JAL
                imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
                
            default: // R 型指令，无立即数域
                imm = 32'b0;
        endcase
    end

endmodule
