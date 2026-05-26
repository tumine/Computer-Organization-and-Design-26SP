### Cache 接入 CPU 技术细节
#### CPU 实现的改动
旧有 CPU 实现与 Cache 接入 CPU 存在一定冲突：
- 数据存储器零延迟，访存结果可以在同一个时钟周期得到；在接入 Cache 之后，CPU 需要处理 Cache 的 `miss, ready` 信号，并据此作出停顿/恢复流水线的响应
- `store` 指令的字节对齐位于 CPU 模块内；在接入 Cache 后，更好的做法是将字节对齐下放到 Cache 模块中进行，以简化 CPU 的操作（只向 Cache 暴露出完整的写内存意图），把写访存的实现细节交给 Cache 内部完成

在 **CPU 模块** `cpu.v` 中的更改
- 撤销原有 CPU 与数据存储器的直接交互端口，改为向 Cache 端口发起内存交互请求
- CPU 根据 Cache 传出的 `miss, ready` 信号相应作出停顿、恢复流水响应

在数据内存控制模块 `data_mem_ctrl.v` 中的更改
- 执行 `store` 指令时，不再将写入数据与字中已有数据合并后作为输出 `wdata_out`，而是只向模块外提供**按字节对齐的写入数据** `wdata_out` 和字写入掩码 `we_mask`

#### Cache 实现的改动
- Cache 新增输出端口 `miss, ready`，用于向 CPU 同步访存状态，在 Cache Miss 处理时让 CPU 相应作出**流水线停顿**
- Cache Hit 时的实现逻辑从写回改为**写直达**，相应添加变量 `write_line_buf`，以便 PDU 模块可以在调试时**随时获取主存的理论最新状态**
- 状态机重新划分为 `IDLE, LOOKUP, MISS_READ, REFILL, W_THROUGH` 五个状态
  - `IDLE` 状态，Cache 在接收到 CPU 发出的读/写信号 `r/w_req` 时，缓存同时传入的访存地址 `addr`、写掩码 `w_mask`、待写入数据 `w_data`
  - `LOOKUP` 状态，Cache 利用访存地址 Tag 段判断 Cache Hit
    - 如果是 read hit，则截取目标字节直接反馈给 CPU 并跳转到 `IDLE` 状态
    - 如果是 write hit，则跳转到 `W_THROUGH` 状态
    - 如果 Cache Miss，则跳转到 `MISS_READ` 状态
  - `MISS_READ` 状态，Cache 向主存发出读取请求，在主存就绪后将读出数据锁存，并跳转到 `REFILL` 状态
  - `REFILL` 状态，Cache 将主存读出数据写入由 LRU 替换策略指定的 Way 中，同时**将目标字节前递给 CPU**，跳转到 `IDLE` 状态
  - `W_THROUGH` 状态，Cache 将命中的 Cache Line 使用主存写入数据覆写后**向主存发出写请求**，在主存就绪后跳转到 `IDLE` 状态

#### 接入 Cache 后 CPU 的访存指令执行路径
- **IF 段**：根据 PC 从指令存储器中读取访存指令
- **ID 段**：控制单元对指令进行译码，生成访存控制信号（`mem_read` / `mem_write`），并读取基址寄存器数据、生成立即数偏移量
- **EX 段**：ALU 将基址数据与立即数偏移量相加，计算出目标内存物理地址
- **MEM 段**
  - `data_mem_ctrl` 根据目标地址后两位与指令操作类型（B/H/W），对待写入的 Store 数据进行字节对齐并生成对应的字节屏蔽掩码 `we_mask`
  - CPU 向 Cache 模块单次发出访存请求，并利用 `dcache_req_active` 防止流水线停顿时陷入重复发请求死循环
  - 若 Cache Miss 或未就绪（`miss=1` 或 `ready=0` 为），CPU 内部产生 `dcache_wait = 1` 停顿流水线
  - 当 Cache 命中或从主存 Refill 完成、`ready` 置 1 后，流水线恢复运行。若是 Load 请求，`data_mem_ctrl` 按照指令格式（位宽与是否有符号）完成字节截取与对应的扩展处理，输出结果
- **WB 段**：若是 Load 指令，将读出数据写入对应的通用目标寄存器

### 分支预测模块技术细节
#### 局部预测器的结构与工作流程
- 核心组件包括 BHT(Branch History Table)、PHT(Pattern History Table)
- BHT 以 PC 的部分位 `pred_pc_idx` 作为索引，“低位近期”地存储过去 `N=LOCAL_HIST_W` 次跳转历史
- PHT 以 BHT 过去 N 次跳转历史 `pred_hist` 作为索引，存储预测跳转情况的 2-bits 状态机
  - `pred_hist` 同时传出模块，进入分支预测段间寄存器随流水线向下流动
  - 状态机值的含义：00-强不跳转，01-弱不跳转，10-弱跳转，11-强跳转
  - 取其中高位作为预测输出，**如果高位为 1 则预测当次会跳转**，否则预测当次不跳转
- 在 `EX` 段更新 BHT、PHT 的值
  - 从 `train_hist_snapshot` 中获取同一条指令在预测时的 BHT 状态（即 `pred_hist`）
  - 使用传入的 `train_pc_idx, train_taken` 在 BHT 中更新该指令的跳转历史
  - 如果执行当次指令时实际发生跳转 `taken=1`，则**将状态机的值加 1**直到达到 11；如果实际未发生跳转，则**将状态机的值减 1**直到达到 00

#### 全局预测器的结构与工作流程
- 核心组件包括 GHR(Global History Register)、PHT
- GHR “低位近期”地记录整个程序过去 `GHR_W` 次执行分支指令的跳转情况
- PHT 以 `ghr^pred_pc_idx` 作为索引存储预测跳转情况的 2-bits 状态机
  - `pred_ghr=ghr` 同时传出模块，进入分支预测段间寄存器随流水线向下流动
  - 通过异或操作实现**对全局跳转历史、指令位置信息的哈希映射**，从而让索引能在一定程度上同时反映二者的信息，在不大幅度扩大存储需求的情况下，**对相同全局历史不同指令、相同指令不同执行路径两种情况都可以做出差异化的预测**
- 在 `EX` 段更新 GHR、PHT 的值
  - 从 `train_ghr_snapshot` 中获取分支指令在 `IF` 段执行时的 GHR 状态（即 `pred_ghr`）
  - 使用传入的 `train_pc_idx, train_taken` 在 GHR 中更新该指令的跳转历史
  - 如果执行当次指令时实际发生跳转 `taken=1`，则**将状态机的值加 1**直到达到 11；如果实际未发生跳转，则**将状态机的值减 1**直到达到 00

#### 竞争预测器工作流程
- PHT 以 `pred_pc_idx` 作为索引，存储预测器选用倾向
  - 00-强局部，01-弱局部，10-弱全局，11-强全局，取其中高位作为预测输出
  - 在局部预测器与全局预测器预测结果不同时，**将状态机向预测正确的预测器方向转移**，例如全局预测器正确、局部预测器错误时，状态机值加 1

#### 分支预测系统整体工作流
- 核心组件包括 BTB(Branch Target Buffer)、RAS(Return Address Stack)
- 获得 `IF` 段的指令地址 `if_pc` 后，根据截取出的 `if_pc_idx, if_pc_tag` 段到 BTB 中查找指令
- 若未命中，预测系统不工作，`if_pred_valid` 置 0；若命中，BTB 返回指令类型 `if_btb_kind` 和指令跳转地址 `if_btb_target`
- 根据**指令类型**分三条路径进一步处理
  - 若属于条件分支指令 `KIND_BRANCH`，则根据竞争预测器当前状态选择采用局部预测器/全局预测器的跳转预测结果；若预测跳转，则采用 BTB 缓存的跳转地址 `if_btb_target`
  - 若属于直接跳转 `KIND_JAL`，则采用 BTB 缓存的跳转地址 `if_btb_target` 作为目标地址
  - 若属于间接跳转 `KIND_JALR`，则在 RAS 非空情形下取 RAS 栈顶地址，若 RAS 为空则取 BTB 缓存的跳转地址 `if_btb_target`
- 在 `EX` 段，根据随段间寄存器下传的 `IF` 段预测结果等信息 `if_pred_meta`，**确定是否发生预测错误**
  - 类型错误 `ex_kind_mismatch`：自修改跳转指令在执行一次后改为非跳转指令，或混淆 `if_pc_idx` 相同的两条指令
  - 预测错误 `ex_direction_mismatch`：预测结果与实际跳转情况不同
  - 目标地址错误 `ex_target_mismatch`：预测的跳转地址与实际跳转地址不符
- 若发生预测错误，则将 `redirect_valid` 信号置 1，清除处于 `IF, ID` 段的指令
- 基于实际指令执行情况，修改 BTB
  - 若实际执行的确实是分支指令 `btb_update_fire=1`，则将跳转地址覆盖到对应的 BTB 单元 `btb_tag/kind/target[ex_pc_idx]` 上
  - 若实际执行的是普通指令但命中 BTB `btb_invalidate_fire=1`，则将对应 BTB 单元置为无效 `btb_valid[ex_pc_idx] <= 0`
  - 若实际执行的是普通指令且未命中 BTB，则不对 BTB 进行任何修改
- RAS 的**双栈机制**
  - RAS 分为架构栈（稳定）与投机栈（激进）
  - 在 `IF` 段，若预测当前指令是 `JAL` 指令，就直接将 `if_pc+32'd4` 压入投机 RAS；若预测当前指令是 `JALR` 指令，就直接弹出栈顶地址作为预测地址
  - 在 `EX` 段，**架构 RAS** 根据实际执行的指令进行压栈/出栈操作；若指令预测错误，投机 RAS 利用架构 RAS 的当前状态进行覆写以**排除所有错误栈操作**
