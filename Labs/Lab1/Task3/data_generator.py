import random

# 生成1024个完全不同的随机整数 (范围可自定义，这里用1到100000)
data = random.sample(range(1, 100000), 1024)

# 1. 生成 .coe 文件 (给 Vivado BRAM IP 核使用)
with open("data.coe", "w") as f_coe:
    f_coe.write("memory_initialization_radix=16;\n")
    f_coe.write("memory_initialization_vector=\n")
    for i, val in enumerate(data):
        if i == 1023:
            f_coe.write(f"{val:08X};\n") # 最后一个数据用分号结尾
        else:
            f_coe.write(f"{val:08X},\n")

# 2. 生成 .txt 文件 (给 Verilog $readmemh 仿真使用)
with open("data.txt", "w") as f_txt:
    for val in data:
        f_txt.write(f"{val:08X}\n")

print("文件 data.coe 和 data.txt 已生成！")
