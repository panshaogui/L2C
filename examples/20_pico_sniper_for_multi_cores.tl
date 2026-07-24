-- ==============================================================================
-- examples/20_pico_sniper_for_multi_cores.tl
-- L2C 双核硅片雷达：Core 0 (ADC硬件泵) -> 无锁流水线 -> Core 1 (DSP 大脑)
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_import: std/dsp.tl

local function delay_ms(ms: integer)
    C_PICO.sleep_us(ms * 1000)
end

local function Get_SharedQueue(): SPSC_Queue
    return SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
end

-- ============================================================================
-- 🧠 副核 (Core 1) 任务：DSP 大脑与继电器控制
-- ============================================================================
local function sniper_brain_task()
    local q = Get_SharedQueue()
    
    -- 🔥 修复核心：彻底抛弃隐式数组，拥抱 0-GC 物理 Arena 强类型装箱！
    local out = IntBox._new() 

    -- 1. 硬件引脚初始化
    C_PICO.gpio_init(14) C_PICO.gpio_set_dir(14, PICO_GPIO_OUT) C_PICO.gpio_put(14, 1) -- 收竿
    C_PICO.gpio_init(15) C_PICO.gpio_set_dir(15, PICO_GPIO_OUT) C_PICO.gpio_put(15, 1) -- 抛竿

    local CHUNK_SIZE = 256
    local raw_signal = L2C_NumberArray(256)
    
    local COEFF_800HZ = 1.605473
    local COEFF_3000HZ = -1.414213

    local STATE_COOLDOWN   = 0
    local STATE_CASTING    = 1
    local STATE_VERIFYING  = 2
    local STATE_WAIT_FISH  = 3
    local STATE_CATCHING   = 4

    local current_state = STATE_COOLDOWN
    local state_timer_ms = 0
    local cast_timer_ms = 0
    local cooldown_duration_ms = 2000

    print("🚀 [Core 1 大脑] DSP 狙击手已就位，开启状态机...")
    
    while true do
        if current_state == STATE_COOLDOWN then
            delay_ms(10)
            state_timer_ms = state_timer_ms + 10
            if state_timer_ms >= cooldown_duration_ms then
                print("\n========================================")
                print("✅ 冷却完毕，开启新一轮循环！")
                current_state = STATE_CASTING
            end

        elseif current_state == STATE_CASTING then
            print("🎣 [动作] 电磁铁重击 3 号键 (抛竿/空竿重开)!")
            C_PICO.gpio_put(15, 0) delay_ms(120) C_PICO.gpio_put(15, 1)
            
            state_timer_ms = 0
            cast_timer_ms = 0
            
            -- 瞬间排空残余队列
            local draining = true
            while draining do
                if not SPSC_Pop(q, out) then draining = false end
            end
            
            current_state = STATE_VERIFYING
            print("🔍 进入 1.5 秒过筛区，监听 WA 退货警告 (800Hz)...")

        elseif current_state == STATE_VERIFYING or current_state == STATE_WAIT_FISH then
            
            -- 🟢 从无锁队列里精准汲取 256 个最新 ADC 采样点
            local sample_count = 0
            while sample_count < CHUNK_SIZE do
                if SPSC_Pop(q, out) then
                    sample_count = sample_count + 1
                    raw_signal[sample_count] = out.val -- 🔥 修复：通过强类型解包获取数据
                end
            end
            
            -- 绝对时钟物理推演 (256 * 125us = 32ms)
            state_timer_ms = state_timer_ms + 32
            cast_timer_ms = cast_timer_ms + 32
            
            if current_state == STATE_VERIFYING and state_timer_ms >= 1500 then
                print("🟢 1.5秒验货通过，未听到退货音！进入安稳等鱼状态...")
                current_state = STATE_WAIT_FISH
            end
            
            if current_state == STATE_WAIT_FISH and cast_timer_ms >= 23000 then
                print("⚠️ [熔断保护] 23秒死等超时！执行重抛...")
                cooldown_duration_ms = 1500
                state_timer_ms = 0
                current_state = STATE_COOLDOWN
            else
                -- 🧮 DSP 运算
                local sum = 0.0
                for i = 1, CHUNK_SIZE do sum = sum + raw_signal[i] end
                local v_mean = sum / 256.0
                
                local variance_sum = 0.0
                for i = 1, CHUNK_SIZE do
                    raw_signal[i] = raw_signal[i] - v_mean
                    variance_sum = variance_sum + (raw_signal[i] * raw_signal[i])
                end
                local v_std = variance_sum / 256.0 
                
                if v_std > 9000000.0 then
                    local power_cast = dsp_goertzel_mag(raw_signal, COEFF_800HZ, 256)
                    local power_fish = 0.0
                    
                    if v_std > 25000000.0 then
                        power_fish = dsp_goertzel_mag(raw_signal, COEFF_3000HZ, 256)
                    end
                    
                    local total_energy = power_cast + power_fish + 1.0
                    local ratio_fish = power_fish / total_energy
                    local ratio_cast = power_cast / total_energy
                    
                    if current_state == STATE_VERIFYING and ratio_cast > 0.6 and ratio_cast > ratio_fish then
                        print("🔴 [退货警告] 抓到 800Hz 纯音！抛远了！强制切断，立刻重抛！")
                        current_state = STATE_CASTING
                    elseif current_state == STATE_WAIT_FISH and ratio_fish > 0.6 and ratio_fish > ratio_cast then
                        print("🎯 [完美中鱼] 抓到 3000Hz 纯音！能量暴涨，收网！")
                        current_state = STATE_CATCHING
                    end
                end
            end

        elseif current_state == STATE_CATCHING then
            print("💥 [动作] 电磁铁重击 F 键 (收网)!")
            C_PICO.gpio_put(14, 0) delay_ms(120) C_PICO.gpio_put(14, 1)
            
            print("⏳ 鱼已入包！进入 5 秒整理防抖期...")
            cooldown_duration_ms = 5000
            state_timer_ms = 0
            current_state = STATE_COOLDOWN
        end
    end
end

-- ============================================================================
-- 🫀 主核 (Core 0) 任务：125us 硬件 ADC 采样泵
-- ============================================================================
C_PICO.stdio_init_all()
print("🛰️ [系统] L2C 边缘架构启动，挂载 ADC 与双核流水线...")

C_PICO.adc_init()
C_PICO.adc_gpio_init(26)
C_PICO.adc_select_input(0)

-- 初始化 1024 容量的 SPSC 无锁跑道
local q = Get_SharedQueue()
local buf_ptr = L2C_Static("[1024]integer")
SPSC_Init(q, 1024, L2C_PtrAsInt(buf_ptr))

-- 🚀 把大脑任务物理发射到 Core 1
Multicore_Launch(L2C_FuncPtr(sniper_brain_task))

print("🫀 [Core 0 心脏] 锁定 8000Hz 采样时钟，开始疯狂投喂 ADC 数据！")

while true do
    local val = C_PICO.adc_read()
    SPSC_Push(q, val)
    C_PICO.sleep_us(125) 
end