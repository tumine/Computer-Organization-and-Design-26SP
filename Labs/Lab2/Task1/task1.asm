# 求解斐波那契数列程序

.text                       # 代码段开始标记
.globl main                 # 声明 main 标签为全局可见，可以被链接器找到

main:
    beqz a0, end_fib        # 若 a0 = 0，直接返回结果为 0 = a0

    li t1, 1                # F(1) = 1，同时用于 n = 1 的条件判定
    la s0, fib_array        # s0 -> 存储基地址（每次存储后加 4）
    sw t1, 0(s0)            # 存储 F(1)
    addi s0, s0, 4          # 指向下一个存储位置
    beq a0, t1, end_fib     # 若 a0 = 1，直接返回结果为 1 = a1

    blt a0, zero, err_proc  # 若 a0 < 0，进入错误处理程序

    # 赋予初值
    # 在循环结束时 t0 表示 F(t2-1)，t1 表示 F(t2)
    # t2 作为计数器
    li t0, 0
    li t2, 1

loop:
    beq t2, a0, end_loop    # 若 t2 == n，则退出循环

    add t3, t0, t1          # 计算 F(i+1) = F(i-1) + F(i)
    mv t0, t1               # t0 = t1
    mv t1, t3               # t1 = t3

    addi t2, t2, 1
    sw t1, 0(s0)            # 存储当前 F(t2)
    addi s0, s0, 4          # 指向下一个存储位置
    j loop

err_proc:
    li a0, -1               # 令 a0 = -1 作为报错状态
    j end_fib

end_loop:
    mv a0, t1               # 循环结束时，t2 = n，t1 寄存器的值即为 F(n)

end_fib:
    li a7, 10               # 结束求解程序
    ecall

.data
.align 2
fib_array:                 # 预留内存区域以便导出 COE 文件（1024 bytes = 256 words）
    .space 1024
