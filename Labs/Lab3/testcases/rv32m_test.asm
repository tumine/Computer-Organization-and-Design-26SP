L0: # 随机初始化各个寄存器
    lui         x0, 0xEEBB4
    addi        x0, x0, 0xFFFFFEE5
    lui         x1, 0x977F6
    addi        x1, x1, 0x37A
    lui         x2, 0xC8D8A
    addi        x2, x2, 0xFFFFFAF9
    lui         x3, 0xC398E
    addi        x3, x3, 0xFFFFF9E4
    lui         x4, 0x798A9
    addi        x4, x4, 0xFFFFFEEC
    lui         x5, 0xAC694
    addi        x5, x5, 0x6
    lui         x6, 0x7280F
    addi        x6, x6, 0xFFFFFF73
    lui         x7, 0x62F6A
    addi        x7, x7, 0x1FF
    lui         x8, 0xCEA25
    addi        x8, x8, 0x745
    lui         x9, 0x8F813
    addi        x9, x9, 0x59A
    lui         x10, 0xBA4A8
    addi        x10, x10, 0x57
    lui         x11, 0x5ED7F
    addi        x11, x11, 0xFFFFFF88
    lui         x12, 0xEB442
    addi        x12, x12, 0xFFFFFC19
    lui         x13, 0x616C7
    addi        x13, x13, 0x25D
    lui         x14, 0x9A601
    addi        x14, x14, 0xFFFFF9FA
    lui         x15, 0xB26D8
    addi        x15, x15, 0xFFFFFDFA
    lui         x16, 0x9E696
    addi        x16, x16, 0x69F
    lui         x17, 0x87A7E
    addi        x17, x17, 0x567
    lui         x18, 0xE3CDF
    addi        x18, x18, 0xFFFFFB56
    lui         x19, 0xCD5FB
    addi        x19, x19, 0x291
    lui         x20, 0x61244
    addi        x20, x20, 0xC7
    lui         x21, 0xE46F0
    addi        x21, x21, 0x487
    lui         x22, 0x94C81
    addi        x22, x22, 0x595
    lui         x23, 0xF72E5
    addi        x23, x23, 0xFFFFFBBC
    lui         x24, 0xE8EA9
    addi        x24, x24, 0xFFFFF87E
    lui         x25, 0x848A1
    addi        x25, x25, 0xFFFFF91E
    lui         x26, 0x1AE41
    addi        x26, x26, 0xBF
    lui         x27, 0x83E75
    addi        x27, x27, 0xFFFFFBE0
    lui         x28, 0xCC1B0
    addi        x28, x28, 0x1C
    lui         x29, 0x12039
    addi        x29, x29, 0x386
    lui         x30, 0x827A7
    addi        x30, x30, 0xFFFFFE2D
    lui         x31, 0xED00F
    addi        x31, x31, 0xFFFFFFB8

L1: # Test 1: mul (3 * -4 = -12)
    addi        x1, x0, 3
    addi        x2, x0, -4
    mul         x3, x1, x2
    addi        x4, x0, -12
    bne         x3, x4, fail

L2: # Test 2: mulh (Signed High, 0x7FFFFFFF * 0x7FFFFFFF)
    # 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF00000001
    lui         x1, 0x80000
    addi        x1, x1, -1      # x1 = 0x7FFFFFFF
    mulh        x3, x1, x1
    lui         x4, 0x40000
    addi        x4, x4, -1      # x4 = 0x3FFFFFFF
    bne         x3, x4, fail

L3: # Test 3: mulhu (Unsigned High, 0xFFFFFFFF * 0xFFFFFFFF)
    # 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001
    addi        x1, x0, -1      # x1 = 0xFFFFFFFF
    mulhu       x3, x1, x1
    addi        x4, x0, -2      # x4 = 0xFFFFFFFE
    bne         x3, x4, fail

L4: # Test 4: div (-13 / 4 = -3) 向零取整
    addi        x1, x0, -13
    addi        x2, x0, 4
    div         x3, x1, x2
    addi        x4, x0, -3
    bne         x3, x4, fail

L5: # Test 5: divu (0xFFFFFFF3 / 4 = 1073741820)
    # 0xFFFFFFF3 = 4294967283
    # 4294967283 / 4 = 1073741820 = 0x3FFFFFFC
    addi        x1, x0, -13     # x1 = 0xFFFFFFF3
    addi        x2, x0, 4
    divu        x3, x1, x2
    lui         x4, 0x40000
    addi        x4, x4, -4      # x4 = 0x3FFFFFFC
    bne         x3, x4, fail

L6: # Test 6: rem (-13 % 4 = -1)
    addi        x1, x0, -13
    addi        x2, x0, 4
    rem         x3, x1, x2
    addi        x4, x0, -1
    bne         x3, x4, fail

L7: # Test 7: remu (0xFFFFFFF3 % 4 = 3)
    addi        x1, x0, -13
    addi        x2, x0, 4
    remu        x3, x1, x2
    addi        x4, x0, 3
    bne         x3, x4, fail

L8: # Test 8: div 各种除0异常测试（要求等于 -1）
    addi        x1, x0, 10
    addi        x2, x0, 0
    div         x3, x1, x2
    addi        x4, x0, -1
    bne         x3, x4, fail

L9: # Test 9: divu 除0异常测试（要求等于 0xFFFFFFFF）
    addi        x1, x0, 10
    addi        x2, x0, 0
    divu        x3, x1, x2
    addi        x4, x0, -1      # -1 = 0xFFFFFFFF
    bne         x3, x4, fail

L10: # Test 10: rem 除 0 异常测试（要求等于被除数）
    addi        x1, x0, 10
    addi        x2, x0, 0
    rem         x3, x1, x2
    addi        x4, x0, 10
    bne         x3, x4, fail

L11: # Test 11: remu 除 0 异常测试（要求等于被除数）
    addi        x1, x0, 10
    addi        x2, x0, 0
    remu        x3, x1, x2
    addi        x4, x0, 10
    bne         x3, x4, fail

L12: # Test 12: div 溢出异常测试 (-2^31 / -1 要求等于 -2^31)
    lui         x1, 0x80000     # x1 = 0x80000000 (-2^31)
    addi        x2, x0, -1
    div         x3, x1, x2
    lui         x4, 0x80000
    bne         x3, x4, fail

L13: # Test 13: rem 溢出异常测试 (-2^31 % -1 要求等于 0)
    lui         x1, 0x80000     # x1 = 0x80000000
    addi        x2, x0, -1
    rem         x3, x1, x2
    addi        x4, x0, 0
    bne         x3, x4, fail

win: # Win label
    lui         x4, 0x0
    addi        x4, x4, 0x0
    j           end

fail: # Fail label
    lui         x4, 0x0
    addi        x4, x4, 0xFFFFFFFF
    j           end

end:
    ebreak