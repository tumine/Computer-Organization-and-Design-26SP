.text
main:
    # 备份输入参数 n 到 s2，防止被获取时间的 ecall 覆盖
    mv s2, a0

    # 获取开始时间
    li a7, 30
    ecall
    mv s0, a0        # 将开始时间的低 32 位存入 s0

    beqz s2, end_fib        # 若 s2 = 0，直接返回结果为 0 = a0
    li t1, 1                # F(1) = 1，同时用于 n = 1 的条件判定
    beq s2, t1, end_fib     # 若 s2 = 1，直接返回结果为 1 = a0
    blt s2, zero, err_proc  # 若 s2 < 0，进入错误处理程序

    # 赋予初值
    # 在循环结束时 t0 表示 F(t2-1)，t1 表示 F(t2)
    # t2 作为计数器
    li t0, 0
    li t2, 1

loop:
    beq t2, s2, end_loop    # 若 t2 == n，则退出循环

    add t3, t0, t1          # 计算 F(i+1) = F(i-1) + F(i)
    mv t0, t1               # t0 = t1
    mv t1, t3               # t1 = t3

    addi t2, t2, 1
    j loop

err_proc:
    li a0, -1               # 令 a0 = -1 作为报错状态
    j end_fib

end_loop:
    mv s3, t1               # 循环结束时，t1 寄存器的值即为 F(n)，备份到 s3

    # 获取结束时间
    li a7, 30
    ecall
    
    # 计算时间差 (结束时间 - 开始时间)
    sub s1, a0, s0          # s1 中保存的就是执行耗时（单位：毫秒）

    # 恢复 F(n) 的结果到 a0 以供程序后续使用或输出
    mv a0, s3

end_fib:
    li a7, 10
    ecall

