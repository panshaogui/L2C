-- @l2c_import: std/dsp.tl

print("==== 🔬 阶段 1：定点数 Q15 DSP 绝对数学精度验证 ====")

local CHUNK_SIZE = 256
-- 🪨 申请极其纯净的 0-GC 栈数组
local adc_buf = L2C_IntegerArray(256)

-- 1. 模拟生成 800Hz 纯整数方波 (采样率 8000Hz)
-- 在 8000Hz 下，800Hz 的波长正好是 10 个采样点 (5个正，5个负)
for i = 1, CHUNK_SIZE do
    local period_pos = (i - 1) % 10
    if period_pos < 5 then
        adc_buf[i] = 1000   -- 高电平
    else
        adc_buf[i] = -1000  -- 低电平
    end
end

-- 2. Q15 系数预编译 (精确计算值)
local COEFF_800HZ_Q15 = 53020   -- 对应 800Hz
local COEFF_3000HZ_Q15 = -46341 -- 对应 3000Hz

-- 3. 发射纯整数数组进 DSP！
local ptr_int = L2C_PtrAsInt(L2C_Ref(adc_buf))
local power_800 = dsp_goertzel_mag_q15(ptr_int, COEFF_800HZ_Q15, 256)
local power_3000 = dsp_goertzel_mag_q15(ptr_int, COEFF_3000HZ_Q15, 256)

print("🎯 800Hz (波形注入频率) 目标能量: ", power_800)
print("🔴 3000Hz (空白频率)     噪底能量: ", power_3000)

if power_800 > power_3000 * 100 then
    print("\n✅ Q15 定点数 Goertzel 算法物理精度验证通过！无溢出，信噪比完美！")
else
    print("\n❌ 精度丢失或溢出！算力阵列崩溃！")
end