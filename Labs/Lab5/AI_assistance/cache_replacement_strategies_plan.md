# Cache替换策略实现方案

## 1. 结构设计
推荐采用在 `n_way_cache.v` 中引入 `REPLACE_POLICY` 参数进行策略选择。

```verilog
parameter REPLACE_POLICY = 0;  // 0:LRU, 1:FIFO, 2:Random, 3:LFU
```

**原因分析：**
* **代码复用度高**：Cache的核心逻辑（状态机、命中判断、与主存的交互、Tag和Data的BRAM读写）是完全一致的，如果创建 `fifo_cache.v`、`rand_cache.v` 等文件会产生大量的重复代码，后续修改极易遗漏。
* **便于测试**：在 `generate_tb.py` 中，我们只需在例化 `cache_inst` 时改变传入的参数 `REPLACE_POLICY`，即可直接生成不同策略下的 testbench，非常方便横向对比Hit Rate和错漏。

## 2. 三种新增替换策略的实现方案

### (1) 伪随机替换策略 (Pseudo-Random, 对应参数 2)
* **方案**：维护一个全局的位宽为 `WAY_NUM_WIDTH` 的计数器 `rand_ptr`。每次发生 Cache Line 替换自动加 1。
* **替换逻辑**：发生缺失时，直接使用 `replace_way = rand_ptr`。无需额外维护每个块的信息，实现成本最低。

### (2) FIFO 替换策略 (先进先出法, 对应参数 1)
* **方案**：为每个 Cache Set 维护一个换出指针 `fifo_ptr [0:SET_NUM-1]`。
* **替换逻辑**：初始化时指针均指向 0。每当发生 Refill（新块被装入到某个 Set 中）时，该组对应的指针向前移动一位（溢出自动回零）。替换时，`replace_way = fifo_ptr[w_index]`。

### (3) LFU 替换策略 (最不经常使用策略, 对应参数 3)
* **方案**：采用饱和计数器实现。为每个 Cache Set 的每个 Way 维护一个 8 位的计数器数组 `lfu_cnt [0:SET_NUM-1][0:WAY_NUM-1]`。
* **替换逻辑**：
    * 发生 Cache Hit 时：命中对应的 `lfu_cnt` 加 1（达到最大值 8'hFF 后不再增加，防止溢出归零）。
    * 发生 Refill 替换时：通过组合逻辑比较出当前 `lfu_cnt` 最小的 Way 作为 `replace_way`。然后将新的 Cache Line 的 `lfu_cnt` 置为 1。
