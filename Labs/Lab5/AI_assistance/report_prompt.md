阅读 n_way_cache.v，梳理其中定义的各个模块内变量的作用，再在 report5.md 中详细分析 Cache 正常工作过程中可能的各种典型工作流，并通过行间代码块从 n_way_cache.v 中截取相应代码附在详细解释内容后
1. 读访存，分为 Cache Hit 与 Cache Miss 情形
2. 写访存，分为 Cache Hit 与 Cache Miss 情形，又详细分为
3. Cache Miss 时需要执行的换入工作
4. Cache Miss 且需要被覆盖的 Cache Line 处于 dirty 状态时需要执行的换出工作
（使用 Codebuddy-GLM 5.1 完成）

参考 Lab 3 的实验报告，以状态机为核心，在 report.md 中描述 Cache 的主要工作过程。要求：
1. 详细描述各个状态下 Cache 主要完成的工作，包括利用什么信号线、寄存器
2. 详细描述 Cache 在各个状态之间通过什么条件判断转换到什么状态，利用到什么信号线和寄存器参与状态转移的判定
（使用 Copilot-Gemini 3.1 Pro 完成）
