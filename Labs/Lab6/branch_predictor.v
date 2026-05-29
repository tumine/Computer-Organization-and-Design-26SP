// Tournament branch predictor with BTB and RAS.
// 锦标赛分支预测器，包含 BTB (分支目标缓冲) 和 RAS (返回地址栈)。
// 条件分支方向仍由局部/全局/选择器预测；BTB 统一缓存控制流类型与目标；
// RAS 专门为 JAL/JALR 的调用/返回关系提供预测目标。

// ============================================================================
// 局部预测器 (Local Predictor)
// 采用两级预测结构：第一级为 BHT（分支历史表），第二级为 PHT（模式历史表）
// ============================================================================
module local_predictor #(
    parameter PC_IDX_W = 8,       // PC Index 段位宽，BHT 共 2^PC_IDX_W 项
    parameter LOCAL_HIST_W = 6    // 局部历史位宽，PHT 共 2^LOCAL_HIST_W 项
)(
    input  wire                    clk,                 // 时钟信号
    input  wire                    rst,                 // 复位信号
    input  wire                    en,                  // 使能信号

    input  wire [PC_IDX_W-1:0]     pred_pc_idx,         // 预测阶段（IF 段）指令的 pc_idx
    output wire [LOCAL_HIST_W-1:0] pred_hist,           // IF 段预测时的 bht[pc_idx] 快照
    output wire                    pred_taken,          // 局部预测器预测的跳转方向（1-跳转, 0-不跳转）

    input  wire                    train_valid,         // 训练阶段（EX 段）的有效信号，valid 为 1 时才更新 BHT 和 PHT
    input  wire [PC_IDX_W-1:0]     train_pc_idx,        // EX 段指令的 pc_idx
    input  wire [LOCAL_HIST_W-1:0] train_hist_snapshot, // EX 段指令在预测阶段的 bht[pc_idx] 快照（在 IF 段传出，随段间寄存器下传）
    input  wire                    train_taken          // EX 段指令实际跳转情况
);
    localparam integer BHT_ENTRIES = (1 << PC_IDX_W);   // BHT 容量
    localparam integer PHT_ENTRIES = (1 << LOCAL_HIST_W); // PHT 容量

    reg [LOCAL_HIST_W-1:0] bht [0:BHT_ENTRIES-1];       // 分支历史表，以 pc_idx 为索引，存储对应指令的局部跳转历史
    // 模式历史表，以 BHT 对 pc_idx 的映射结果为索引，存储 2-bit 状态机（跳转倾向）
    // 00-强不跳转，01-弱不跳转，10-弱跳转，11-强跳转
    reg [1:0] pht [0:PHT_ENTRIES-1];

    integer i;

    // 2-bit 状态机更新函数
    function [1:0] sat_update;
        input [1:0] cur;    // 当前状态
        input       taken;  // 当前实际跳转情况
        begin
            sat_update = cur;
            if (taken) begin
                if (cur != 2'b11) begin
                    sat_update = cur + 2'b01; // 实际发生跳转，计数器加 1（2'b11 封顶）
                end
            end
            else begin
                if (cur != 2'b00) begin
                    sat_update = cur - 2'b01; // 实际未发生跳转，计数器减 1（2'b00 封底）
                end
            end
        end
    endfunction

    // 跳转预测结果
    assign pred_hist = bht[pred_pc_idx];      // 根据当前 pc_idx 读出跳转局部历史
    assign pred_taken = pht[pred_hist][1];    // 使用读出的局部历史查找 PHT，取计数器高位作为预测方向

    always @(posedge clk) begin
        if (rst) begin
            // 复位时，清空 BHT
            for (i = 0; i < BHT_ENTRIES; i = i + 1) begin
                bht[i] <= {LOCAL_HIST_W{1'b0}};
            end
            // 复位时，PHT 初始化为弱不跳转
            for (i = 0; i < PHT_ENTRIES; i = i + 1) begin
                pht[i] <= 2'b01;
            end
        end
        else if (en && train_valid) begin
            // 指令执行到 EX 段时，pred_pc_idx 可能变化，不能取出当前指令对应的 bht 条目
            // 因此，使用 IF 段预测时外传的 bht[pc_idx] 快照更新 PHT
            pht[train_hist_snapshot] <= sat_update(pht[train_hist_snapshot], train_taken);
            // 更新 BHT：左移并将当前的实际跳转结果存入历史最低位
            bht[train_pc_idx] <= {bht[train_pc_idx][LOCAL_HIST_W-2:0], train_taken};
        end
    end
endmodule

// ============================================================================
// 全局预测器 (Global Predictor)
// 采用 GShare 结构：将全局历史 (GHR) 和 PC 异或后索引 PHT
// ============================================================================
module global_predictor #(
    parameter PC_IDX_W = 8,       // PC 索引位宽
    parameter GHR_W = 8           // 全局历史寄存器位宽
)(
    input  wire                    clk,                 // 时钟信号
    input  wire                    rst,                 // 复位信号
    input  wire                    en,                  // 使能信号

    input  wire [PC_IDX_W-1:0]     pred_pc_idx,         // 预测阶段（IF 段）指令的 pc_idx
    output wire [GHR_W-1:0]        pred_ghr,            // IF 段预测时的 ghr 快照
    output wire                    pred_taken,          // 局部预测器预测的跳转方向（1-跳转, 0-不跳转）

    input  wire                    train_valid,         // 训练阶段（EX 段）的有效信号，valid 为 1 时才更新 BHT 和 PHT
    input  wire [PC_IDX_W-1:0]     train_pc_idx,        // EX 段指令的 pc_idx
    input  wire [GHR_W-1:0]        train_ghr_snapshot,  // EX 段指令在预测阶段的 ghr 快照
    input  wire                    train_taken          // EX 段指令实际跳转情况
);
    localparam integer PHT_ENTRIES = (1 << PC_IDX_W);   // PHT 容量

    reg [GHR_W-1:0] ghr;                                // 全局历史寄存器 (Global History Register)
    reg [1:0] pht [0:PHT_ENTRIES-1];                    // 模式历史表（2-bit 状态机）

    integer i;

    // 2-bit 状态机更新函数
    function [1:0] sat_update;
        input [1:0] cur;    // 当前状态
        input       taken;  // 当前实际跳转情况
        begin
            sat_update = cur;
            if (taken) begin
                if (cur != 2'b11) begin
                    sat_update = cur + 2'b01; // 实际发生跳转，计数器加 1（2'b11 封顶）
                end
            end
            else begin
                if (cur != 2'b00) begin
                    sat_update = cur - 2'b01; // 实际未发生跳转，计数器减 1（2'b00 封底）
                end
            end
        end
    endfunction

    // IF 段的索引：pc_idx 与 GHR 按位异或，以同时包括双方信息
    wire [PC_IDX_W-1:0] pred_idx = pred_pc_idx ^ ghr[PC_IDX_W-1:0];
    // EX 段的索引
    wire [PC_IDX_W-1:0] train_idx = train_pc_idx ^ train_ghr_snapshot[PC_IDX_W-1:0];

    // 组合逻辑输出预测快照和预测结果
    assign pred_ghr = ghr;
    assign pred_taken = pht[pred_idx][1]; // 取对应 PHT 表项计数器的高位作为预测方向

    always @(posedge clk) begin
        if (rst) begin
            ghr <= {GHR_W{1'b0}};         // 复位时清零全局历史
            for (i = 0; i < PHT_ENTRIES; i = i + 1) begin
                pht[i] <= 2'b01;          // PHT 初始化为弱不跳转
            end
        end
        else if (en && train_valid) begin
            // 指令执行到 EX 段时，pred_pc_idx 可能变化，不能取出当前指令对应的 bht 条目
            // 因此，使用 IF 段预测时外传的 ghr 快照和 pc_idx 快照更新 PHT
            pht[train_idx] <= sat_update(pht[train_idx], train_taken);
            // 更新 GHR：左移并将当前的实际跳转结果存入历史最低位
            ghr <= {ghr[GHR_W-2:0], train_taken};
        end
    end
endmodule

// ============================================================================
// 竞争/选择预测器 (Choice Predictor / Tournament Predictor)
// 决定最终使用局部预测结果还是全局预测结果
// ============================================================================
module choice_predictor #(
    parameter PC_IDX_W = 8        // PC 索引位宽
)(
    input  wire                    clk,                 // 时钟信号
    input  wire                    rst,                 // 复位信号
    input  wire                    en,                  // 使能信号

    input  wire [PC_IDX_W-1:0]     pred_pc_idx,         // 预测阶段读出的 PC 索引
    output wire                    pred_use_global,     // 预测输出：1-全局，0-局部

    input  wire                    train_valid,         // 训练阶段（EX 段）有效信号
    input  wire [PC_IDX_W-1:0]     train_pc_idx,        // EX 段 pc_idx
    input  wire                    train_local_pred,    // 局部预测器作出预测情况快照
    input  wire                    train_global_pred,   // 全局预测器作出预测情况快照
    input  wire                    train_actual_taken   // EX 段实际跳转方向
);
    localparam integer CHOICE_ENTRIES = (1 << PC_IDX_W); // 竞争表项数

    reg [1:0] choice_pht [0:CHOICE_ENTRIES-1];          // 竞争表，包含 2-bit 状态机
    integer i;

    // 竞争表 2-bit 状态机更新函数
    function [1:0] sat_update;
        input [1:0] cur;      // 当前计数值
        input       move_up;  // 1-加深全局倾向，0-加深局部倾向
        begin
            sat_update = cur;
            if (move_up) begin
                if (cur != 2'b11) begin
                    sat_update = cur + 2'b01; 
                end
            end
            else begin
                if (cur != 2'b00) begin
                    sat_update = cur - 2'b01; 
                end
            end
        end
    endfunction

    // 高位为 1 表示使用全局预测结果，高位为 0 表示使用局部预测结果
    assign pred_use_global = choice_pht[pred_pc_idx][1];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < CHOICE_ENTRIES; i = i + 1) begin
                choice_pht[i] <= 2'b01; // 初始化为弱局部
            end
        end
        else if (en && train_valid) begin
            if (train_local_pred != train_global_pred) begin
                // 只在局部/全局预测结果不同时更新选择倾向
                if (train_global_pred == train_actual_taken) begin
                    // 全局对而局部错，增加全局倾向
                    choice_pht[train_pc_idx] <= sat_update(choice_pht[train_pc_idx], 1'b1);
                end
                else if (train_local_pred == train_actual_taken) begin
                    // 局部对而全局错，增加局部倾向
                    choice_pht[train_pc_idx] <= sat_update(choice_pht[train_pc_idx], 1'b0);
                end
            end
        end
    end
endmodule

// ============================================================================
// 顶层分支预测器 (Branch Predictor Top)
// 结合 BTB, RAS 和多级方向预测器，完成包括目标地址和跳转方向的综合预测
// ============================================================================
module branch_predictor #(
    parameter PC_IDX_W = 8,       // BTB 及预测器索引位宽
    parameter LOCAL_HIST_W = 6,   // 局部预测历史位宽
    parameter GHR_W = 8,          // 全局预测历史位宽
    parameter META_W = 64         // 随流水下传的元数据位宽
)(
    input  wire                    clk,                 // 当前时钟
    input  wire                    rst,                 // 同步复位
    input  wire                    en,                  // CPU 全局运行使能，来自 PDU 的 run/step 控制
    input  wire                    predictor_disable,   // PDU 统一预测禁用开关，单独进入预测器避免和 global_en 语义混淆
    input  wire                    stall,               // 流水线暂停状态，用于冻结 IF 段的推进

    // ---- 预测接口（提供给 IF 段）----
    input  wire [31:0]             if_pc,               // 正在取指的当前 PC
    input  wire [31:0]             if_inst,             // 当前取得的指令
    output wire                    if_pred_valid,       // 预测器是否给出有效预测
    output wire                    if_pred_taken,       // 预测出的跳转方向
    output wire [31:0]             if_pred_target,      // 预测出的目标地址
    output wire [META_W-1:0]       if_pred_meta,        // 产生预测时的所有状态快照（随流水下传至 EX 段）

    // ---- 训练/修正接口（来自 EX 段）----
    input  wire                    ex_valid,            // 当前 EX 段是否有一条指令，不是气泡
    input  wire [31:0]             ex_pc,               // EX 段分支指令的自身 PC
    input  wire [31:0]             ex_pc_plus4,         // EX 段分支指令的下一个顺序 PC
    input  wire [31:0]             ex_target_actual,    // 实际应跳转到的目标地址
    input  wire                    ex_taken_actual,     // 实际跳转方向
    input  wire                    ex_is_branch,        // EX 段确认指令是条件分支指令
    input  wire                    ex_is_jal,           // EX 段确认指令是 JAL
    input  wire                    ex_is_jalr,          // EX 段确认指令是 JALR
    input  wire [META_W-1:0]       ex_meta,             // 由该指令带来的状态快照
    input  wire                    ex_bp_used,          // EX 段发出的信号预测是否被使用过

    // ---- 流水线重定向接口 ----
    output wire                    redirect_valid,      // 指示流水线是否需要重定向
    output wire [31:0]             redirect_pc          // 指示正确的跳转目标地址
);
    // 定义控制流类别
    localparam [1:0] KIND_BRANCH  = 2'b00; // 条件分支
    localparam [1:0] KIND_JAL     = 2'b01; // JAL 无条件跳转
    localparam [1:0] KIND_JALR    = 2'b10; // JALR 间接跳转
    localparam [1:0] KIND_INVALID = 2'b11; // 无效项

    // BTB 与 RAS 配置
    localparam integer BTB_ENTRIES = (1 << PC_IDX_W);    // BTB 表项数
    localparam integer BTB_TAG_W = 32 - PC_IDX_W - 2;    // BTB Tag 段位宽（去掉 byte offset 2 位及 idx）
    localparam integer RAS_DEPTH = 8;                    // RAS 最大深度
    localparam integer RAS_PTR_W = 3;                    // RAS 指针宽度（log2(RAS_DEPTH)）
    localparam integer RAS_CNT_W = 4;                    // RAS 计数器宽度（保存栈内计数）
    localparam [RAS_CNT_W-1:0] RAS_DEPTH_COUNT = RAS_DEPTH; // 用于深度满或空的判别界限

    // 状态快照各字段的位置索引（需与 assign if_pred_meta 逻辑一致）
    localparam integer META_PC_LO          = 0;   // [7:0] IF 段指令在预测时所用的 PC 索引 (pc_idx) 快照
    localparam integer META_PC_HI          = 7;
    localparam integer META_LOCAL_HIST_LO  = 8;   // [13:8] IF 段进行预测时的 BHT 局部历史快照
    localparam integer META_LOCAL_HIST_HI  = 13;
    localparam integer META_GHR_LO         = 14;  // [21:14] IF段进行预测时的 GHR 全局历史快照
    localparam integer META_GHR_HI         = 21;
    localparam integer META_LOCAL_PRED     = 22;  // [22] 局部预测器单独给出的方向预测（1-跳转，0-不跳转）
    localparam integer META_GLOBAL_PRED    = 23;  // [23] 全局预测器单独给出的方向预测
    localparam integer META_CHOICE_GLOBAL  = 24;  // [24] 竞争预测器的选择倾向结果（1-全局，0-局部）
    localparam integer META_PRED_TAKEN     = 25;  // [25] 综合得出的最终跳转方向预测结果
    localparam integer META_PRED_VALID     = 26;  // [26] 预测器是否对该指令给出了有效的预测判定
    localparam integer META_KIND_LO        = 27;  // [28:27] 从 BTB 中识别出的控制流分类（Branch/JAL/JALR）
    localparam integer META_KIND_HI        = 28;
    localparam integer META_BTB_HIT        = 29;  // [29] BTB Hit 状态
    localparam integer META_LOOKUP_ACTIVE  = 30;  // [30] 取指时预测器是否处于活跃检索状态（未停顿且未禁用）
    localparam integer META_RAS_OP_VALID   = 31;  // [31] 本次分支预测是否触发了引发了投机 RAS 栈的出入栈修改
    localparam integer META_PRED_TARGET_LO = 32;  // [63:32] 由预测器预估出的跳转目标 PC 地址
    localparam integer META_PRED_TARGET_HI = 63;

    // BTB 配置
    reg                    btb_valid  [0:BTB_ENTRIES-1]; // BTB 有效位
    reg [BTB_TAG_W-1:0]    btb_tag    [0:BTB_ENTRIES-1]; // BTB 匹配标签
    reg [1:0]              btb_kind   [0:BTB_ENTRIES-1]; // 控制流类型（Branch, JAL, JALR）
    reg [31:0]             btb_target [0:BTB_ENTRIES-1]; // 目标 PC 地址

    // RAS 栈，分为架构栈和投机栈
    // 架构栈在 EX 段更新，分支预测出错时覆写投机栈；投机栈在 IF 段更新，用于直接提供预测结果对应的下一条指令地址
    reg [31:0]             ras_arch_stack [0:RAS_DEPTH-1]; // 架构栈
    reg [31:0]             ras_spec_stack [0:RAS_DEPTH-1]; // 投机栈
    reg [RAS_PTR_W-1:0]    ras_arch_sp;                    // 架构栈指针
    reg [RAS_PTR_W-1:0]    ras_spec_sp;                    // 投机栈指针
    reg [RAS_CNT_W-1:0]    ras_arch_count;                 // 架构栈元素数量
    reg [RAS_CNT_W-1:0]    ras_spec_count;                 // 投机栈元素数量

    // 判断预测器是否整体生效（未被 PDU 禁用）
    wire                    predictor_active = en && !predictor_disable;
    // 从 IF PC 分离索引和标签（位 [1:0] 移位补 0 强制字对齐）
    wire [PC_IDX_W-1:0]     if_pc_idx = if_pc[PC_IDX_W+1:2];
    wire [BTB_TAG_W-1:0]    if_pc_tag = if_pc[31:PC_IDX_W+2];
    // 从 EX PC 分离索引和标签，用于后期的实际评估与 BTB 维护
    wire [PC_IDX_W-1:0]     ex_pc_idx = ex_pc[PC_IDX_W+1:2];
    wire [BTB_TAG_W-1:0]    ex_pc_tag = ex_pc[31:PC_IDX_W+2];

    // 从各子预测器提取预测结果和状态快照
    wire [LOCAL_HIST_W-1:0] if_local_hist_snapshot;
    wire [GHR_W-1:0]        if_ghr_snapshot;
    wire                    if_local_pred;
    wire                    if_global_pred;
    wire                    if_choice_use_global;
    // 基础分支预判：由 choice 倾向决定用 global 还是 local
    wire                    if_branch_dir_pred = if_choice_use_global ? if_global_pred : if_local_pred;

    // IF 阶段预测是否允许（要求未被预测器禁用或无流水暂停）
    wire                    if_lookup_active = predictor_active && !stall;
    // BTB 判断命中原则
    wire                    if_btb_raw_hit = btb_valid[if_pc_idx] && (btb_tag[if_pc_idx] == if_pc_tag);
    wire                    if_btb_hit = if_lookup_active && if_btb_raw_hit;
    wire [1:0]              if_btb_kind = btb_kind[if_pc_idx];
    wire [31:0]             if_btb_target = btb_target[if_pc_idx];

    // RAS 判断预测与数值导出
    wire [RAS_PTR_W-1:0]    if_ras_top_idx = ras_spec_sp - {{(RAS_PTR_W-1){1'b0}}, 1'b1};
    wire [31:0]             if_ras_top = ras_spec_stack[if_ras_top_idx];
    wire                    if_ras_not_empty = (ras_spec_count != {RAS_CNT_W{1'b0}});

    // 分流预测控制类别判断
    wire                    if_kind_branch = if_btb_hit && (if_btb_kind == KIND_BRANCH);
    wire                    if_kind_jal    = if_btb_hit && (if_btb_kind == KIND_JAL);
    wire                    if_kind_jalr   = if_btb_hit && (if_btb_kind == KIND_JALR);
    // 判断 JALR 是否具有预测价值（命中 BTB 得知该指令是 JALR，且 RAS 非空）
    wire                    if_jalr_predictable = if_kind_jalr && if_ras_not_empty;
    // JAL 或 JALR 指令会引起投机栈的变动
    wire                    if_ras_op_valid = if_kind_jal || if_jalr_predictable;

    // 提取 EX 流经带来的各种信息快照（用于和实际验证做对比与训练使用）
    wire [LOCAL_HIST_W-1:0] ex_local_hist_snapshot = ex_meta[META_LOCAL_HIST_HI:META_LOCAL_HIST_LO];
    wire [GHR_W-1:0]        ex_ghr_snapshot = ex_meta[META_GHR_HI:META_GHR_LO];
    wire                    ex_local_pred = ex_meta[META_LOCAL_PRED];
    wire                    ex_global_pred = ex_meta[META_GLOBAL_PRED];
    wire                    ex_pred_taken = ex_meta[META_PRED_TAKEN];
    wire                    ex_pred_valid = ex_meta[META_PRED_VALID];
    wire [1:0]              ex_pred_kind = ex_meta[META_KIND_HI:META_KIND_LO];
    wire                    ex_lookup_active = ex_meta[META_LOOKUP_ACTIVE];
    wire [31:0]             ex_pred_target = ex_meta[META_PRED_TARGET_HI:META_PRED_TARGET_LO];
    wire                    ex_is_control = ex_is_branch || ex_is_jal || ex_is_jalr;
    wire [1:0]              ex_actual_kind = ex_is_branch ? KIND_BRANCH :
                                             ex_is_jal    ? KIND_JAL    :
                                             ex_is_jalr   ? KIND_JALR   :
                                                           KIND_INVALID;

    // ----- 各类训练信号 ------
    // BHT/PHT 选择器训练基于判定是 Branch
    wire                    train_fire = predictor_active && !stall && ex_valid && ex_is_branch && ex_lookup_active;
    // Choice 当二者预判不同时才触发更新
    wire                    train_choice_fire = train_fire && (ex_local_pred != ex_global_pred);
    // BTB 只由 EX 段实际执行过的合法控制流修改
    wire                    btb_update_fire = predictor_active && !stall && ex_valid && ex_lookup_active && ex_is_control;
    // 非分支跳转指令意外命中 BTB 中的某一项，则需要将该项从 BTB 中抹去避免再次误命中
    wire                    btb_invalidate_fire = predictor_active && !stall && ex_valid && ex_bp_used && !ex_is_control;

    // 三种预测错误：类型错误、预测错误、目标地址错误
    // 类型错误指非分支跳转指令被误识别为跳转指令
    // 预测错误指分支预测结果与实际跳转情况不符
    // 目标地址错误指分支预测跳转地址与实际跳转地址不符
    wire                    ex_kind_mismatch = ex_bp_used && ex_pred_valid && (ex_pred_kind != ex_actual_kind);
    wire                    ex_direction_mismatch = ex_bp_used && ex_pred_valid && (ex_pred_taken != ex_taken_actual);
    wire                    ex_target_mismatch = ex_bp_used && ex_pred_valid && ex_pred_taken && ex_taken_actual
                                                && (ex_pred_target != ex_target_actual);
    // 出现预测错误，流水线指令执行路径需要改变（重新取指）
    wire                    predicted_path_redirect = ex_kind_mismatch || ex_direction_mismatch || ex_target_mismatch;
    // 从未建立过预判的初见指令发生了跳转，也需重定向
    wire                    baseline_path_redirect = (!ex_bp_used) && ex_valid && ex_is_control && ex_taken_actual;
    // 如果 EX 段判断发生执行路径改变，IF 段指令的投机 RAS 栈修改一定出错，需要利用架构栈覆写
    wire                    ras_repair_fire = ex_valid && (predicted_path_redirect || baseline_path_redirect);

    // ======== 建立并连接各个子预测模块 =========
    local_predictor #(
        .PC_IDX_W(PC_IDX_W),
        .LOCAL_HIST_W(LOCAL_HIST_W)
    ) u_local_predictor (
        .clk            (clk),
        .rst            (rst),
        .en             (en),
        .pred_pc_idx    (if_pc_idx),
        .pred_hist      (if_local_hist_snapshot),
        .pred_taken     (if_local_pred),
        .train_valid    (train_fire),
        .train_pc_idx   (ex_pc_idx),
        .train_hist_snapshot(ex_local_hist_snapshot),
        .train_taken    (ex_taken_actual)
    );

    global_predictor #(
        .PC_IDX_W(PC_IDX_W),
        .GHR_W(GHR_W)
    ) u_global_predictor (
        .clk            (clk),
        .rst            (rst),
        .en             (en),
        .pred_pc_idx    (if_pc_idx),
        .pred_ghr       (if_ghr_snapshot),
        .pred_taken     (if_global_pred),
        .train_valid    (train_fire),
        .train_pc_idx   (ex_pc_idx),
        .train_ghr_snapshot(ex_ghr_snapshot),
        .train_taken    (ex_taken_actual)
    );

    choice_predictor #(
        .PC_IDX_W(PC_IDX_W)
    ) u_choice_predictor (
        .clk            (clk),
        .rst            (rst),
        .en             (en),
        .pred_pc_idx    (if_pc_idx),
        .pred_use_global(if_choice_use_global),
        .train_valid    (train_choice_fire),
        .train_pc_idx   (ex_pc_idx),
        .train_local_pred(ex_local_pred),
        .train_global_pred(ex_global_pred),
        .train_actual_taken(ex_taken_actual)
    );

    // IF 多路目标选择
    // BRANCH 使用 BTB 目标和 tournament 方向
    // JAL 固定 taken 使用 BTB 目标
    // JALR 只有在 BTB 命中且 RAS 非空时才预测，目标取 RAS 栈顶
    assign if_pred_valid  = if_kind_branch || if_kind_jal || if_jalr_predictable;
    assign if_pred_taken  = if_kind_branch ? if_branch_dir_pred :
                            (if_kind_jal || if_jalr_predictable);
    assign if_pred_target = if_jalr_predictable ? if_ras_top : if_btb_target;

    // 64 位预测元数据随 IF/ID 和 ID/EX 段间寄存器下传，在 EX 段据此验证分支跳转类型、方向和目标是否正确
    assign if_pred_meta = {
        if_pred_target,
        if_ras_op_valid,
        if_lookup_active,
        if_btb_hit,
        if_btb_hit ? if_btb_kind : KIND_INVALID,
        if_pred_valid,
        if_pred_taken,
        if_choice_use_global,
        if_global_pred,
        if_local_pred,
        if_ghr_snapshot,
        if_local_hist_snapshot,
        if_pc_idx
    };

    assign redirect_valid = predicted_path_redirect;
    assign redirect_pc = ex_taken_actual ? ex_target_actual : ex_pc_plus4;

    integer i;

    // ======== 主时序同步控制 ========
    always @(posedge clk) begin
        if (rst) begin
            // 完整清空 BTB 状态
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb_valid[i] <= 1'b0;
                btb_tag[i] <= {BTB_TAG_W{1'b0}};
                btb_kind[i] <= KIND_INVALID;
                btb_target[i] <= 32'b0;
            end
            // 初始化 RAS 各计数内容和栈内存
            for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                ras_arch_stack[i] <= 32'b0;
                ras_spec_stack[i] <= 32'b0;
            end
            ras_arch_sp <= {RAS_PTR_W{1'b0}};
            ras_spec_sp <= {RAS_PTR_W{1'b0}};
            ras_arch_count <= {RAS_CNT_W{1'b0}};
            ras_spec_count <= {RAS_CNT_W{1'b0}};
        end
        else if (en) begin
            if (btb_update_fire) begin
                // EX 段用真实 opcode 和真实跳转目标更新 BTB，IF 段只读取 BTB 条目
                btb_valid[ex_pc_idx] <= 1'b1;
                btb_tag[ex_pc_idx] <= ex_pc_tag;
                btb_kind[ex_pc_idx] <= ex_actual_kind;
                btb_target[ex_pc_idx] <= ex_target_actual;
            end
            else if (btb_invalidate_fire) begin
                // 某个 BTB 条目命中了普通指令，需要清除该项并在 EX 段重定向回 PC+4
                btb_valid[ex_pc_idx] <= 1'b0;
            end

            if (predictor_active && !stall && ex_valid && ex_lookup_active) begin
                // 架构 RAS 栈只由 EX 段的真实 JAL/JALR 更新
                if (ex_is_jal && (ras_arch_count != RAS_DEPTH_COUNT)) begin
                    // JAL 指令，将 PC+4 压入架构栈
                    ras_arch_stack[ras_arch_sp] <= ex_pc_plus4;
                    ras_arch_sp <= ras_arch_sp + {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                    ras_arch_count <= ras_arch_count + {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                end
                else if (ex_is_jalr && (ras_arch_count != {RAS_CNT_W{1'b0}})) begin
                    // JALR 指令，架构栈弹出栈顶元素
                    ras_arch_sp <= ras_arch_sp - {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                    ras_arch_count <= ras_arch_count - {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                end
            end

            if (!predictor_active) begin
                // PDU 禁用期间 BTB/RAS/BHT/PHT/Choice 都不训练；这里只清掉推测过远的废弃投机状态并重回真实锚点
                for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                    ras_spec_stack[i] <= ras_arch_stack[i];
                end
                ras_spec_sp <= ras_arch_sp;
                ras_spec_count <= ras_arch_count;
            end
            else if (!stall) begin
                if (ras_repair_fire) begin
                    // 一旦 EX 触发重定向，年轻指令被冲刷出流水线；投机 RAS 栈使用架构栈覆写
                    for (i = 0; i < RAS_DEPTH; i = i + 1) begin
                        ras_spec_stack[i] <= ras_arch_stack[i];
                    end

                    // 在覆写时，需要计入当前 EX 段指令对架构栈的修改
                    if (ex_is_jal && ex_lookup_active && (ras_arch_count != RAS_DEPTH_COUNT)) begin
                        ras_spec_stack[ras_arch_sp] <= ex_pc_plus4;
                        ras_spec_sp <= ras_arch_sp + {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                        ras_spec_count <= ras_arch_count + {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                    end
                    else if (ex_is_jalr && ex_lookup_active && (ras_arch_count != {RAS_CNT_W{1'b0}})) begin
                        ras_spec_sp <= ras_arch_sp - {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                        ras_spec_count <= ras_arch_count - {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                    end
                    else begin
                        ras_spec_sp <= ras_arch_sp;
                        ras_spec_count <= ras_arch_count;
                    end
                end
                else begin
                    // IF 段更新投机栈：预测为 JAL 时压栈，预测为 JALR 指令时出栈
                    if (if_kind_jal && if_pred_valid && (ras_spec_count != RAS_DEPTH_COUNT)) begin
                        ras_spec_stack[ras_spec_sp] <= if_pc + 32'd4;
                        ras_spec_sp <= ras_spec_sp + {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                        ras_spec_count <= ras_spec_count + {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                    end
                    else if (if_jalr_predictable && if_pred_valid) begin
                        ras_spec_sp <= ras_spec_sp - {{(RAS_PTR_W-1){1'b0}}, 1'b1};
                        ras_spec_count <= ras_spec_count - {{(RAS_CNT_W-1){1'b0}}, 1'b1};
                    end
                end
            end
        end
    end
endmodule
