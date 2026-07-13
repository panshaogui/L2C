-- examples/20_pico_sniper.tl
-- @l2c_import: std/pico.tl
-- @l2c_import: std/freertos.tl
-- @l2c_import: std/dsp.tl

local function sniper_task(_param: any)
    -- 1. 硬件引脚初始化
    C_PICO.gpio_init(14) -- 继电器1: 收竿 (F键)
    C_PICO.gpio_set_dir(14, PICO_GPIO_OUT)
    C_PICO.gpio_put(14, 1) -- 默认拉高断开
    
    C_PICO.gpio_init(15) -- 继电器2: 抛竿 (3键)
    C_PICO.gpio_set_dir(15, PICO_GPIO_OUT)
    C_PICO.gpio_put(15, 1) -- 默认拉高断开
    
    -- 麦克风接在 ADC0 (物理引脚 GP26)
    C_PICO.adc_init()
    C_PICO.adc_gpio_init(26)
    C_PICO.adc_select_input(0)
    
    -- 2. 核心内存强开 (栈内存，绝对 0-GC)
    local CHUNK_SIZE = 256
    local raw_signal = L2C_NumberArray(256)
    
    -- 3. Goertzel 系数预处理 (8000Hz 采样率，256点)
    local COEFF_800HZ = 1.605473    -- 800Hz
    local COEFF_3000HZ = -1.414213  -- 3000Hz
    
    -- 4. 闭环状态机定义
    local STATE_COOLDOWN   = 0  -- 冷却防抖
    local STATE_CASTING    = 1  -- 执行抛竿
    local STATE_VERIFYING  = 2  -- 过筛校验 (1.5s)
    local STATE_WAIT_FISH  = 3  -- 安稳等鱼 (最大23s)
    local STATE_CATCHING   = 4  -- 执行收竿
    
    local current_state = STATE_COOLDOWN
    local state_timer_ms = 0
    local cast_timer_ms = 0
    local cooldown_duration_ms = 2000 -- 开局等2秒启动

    print("🚀 L2C 硅片雷达点火！[动态防卡死 + 继电器直控] 终极闭环启动...")
    
    while true do
        -- ⏱️ 物理锁频计时器：每次循环必定耗时 42ms
        local LOOP_MS = 42
        state_timer_ms = state_timer_ms + LOOP_MS
        cast_timer_ms = cast_timer_ms + LOOP_MS

        -- ============================================
        -- 【状态 0】：冷却防抖期
        -- ============================================
        if current_state == STATE_COOLDOWN then
            if state_timer_ms >= cooldown_duration_ms then
                print("\n========================================")
                print("✅ 冷却完毕，开启新一轮循环！")
                current_state = STATE_CASTING
            end

        -- ============================================
        -- 【状态 1】：执行抛竿动作
        -- ============================================
        elseif current_state == STATE_CASTING then
            print("🎣 [动作] 电磁铁重击 3 号键 (抛竿/空竿重开)!")
            C_PICO.gpio_put(15, 0)
            freertos_delay_ms(120)
            C_PICO.gpio_put(15, 1)
            
            state_timer_ms = 0
            cast_timer_ms = 0
            current_state = STATE_VERIFYING
            print("🔍 进入 1.5 秒过筛区，监听 WA 退货警告 (800Hz)...")

        -- ============================================
        -- 【状态 2/3】：频域监听雷达 (800Hz 或 3000Hz)
        -- ============================================
        elseif current_state == STATE_VERIFYING or current_state == STATE_WAIT_FISH then
            
            -- 🟢 过筛晋升判定
            if current_state == STATE_VERIFYING and state_timer_ms >= 1500 then
                print("🟢 1.5秒验货通过，未听到退货音！进入安稳等鱼状态...")
                current_state = STATE_WAIT_FISH
            end
            
            -- 🚨 【核心防卡死锁】 23 秒熔断保护！
            if current_state == STATE_WAIT_FISH and cast_timer_ms >= 23000 then
                print("⚠️ [熔断保护] 23秒死等超时！未见中鱼信号！")
                print("🛑 判定为死鱼、卡视野或漏帧！引导进入常规重抛流程...")
                cooldown_duration_ms = 1500
                state_timer_ms = 0
                current_state = STATE_COOLDOWN
            else
                -- 没有超时，正常采集音频
                local sum = 0.0
                for i = 1, CHUNK_SIZE do
                    local val = C_PICO.adc_read()
                    raw_signal[i] = val
                    sum = sum + val
                    C_PICO.sleep_us(123) 
                end
                
                local v_mean = sum / 256.0
                local variance_sum = 0.0
                for i = 1, CHUNK_SIZE do
                    raw_signal[i] = raw_signal[i] - v_mean
                    variance_sum = variance_sum + (raw_signal[i] * raw_signal[i])
                end
                
                local v_std = variance_sum / 256.0 
                
                -- 只要有足够响的声音
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

        -- ============================================
        -- 【状态 4】：执行收竿动作
        -- ============================================
        elseif current_state == STATE_CATCHING then
            print("💥 [动作] 电磁铁重击 F 键 (收网)!")
            C_PICO.gpio_put(14, 0)
            freertos_delay_ms(120)
            C_PICO.gpio_put(14, 1)
            
            print("⏳ 鱼已入包！进入 5 秒整理防抖期...")
            cooldown_duration_ms = 5000
            state_timer_ms = 0
            current_state = STATE_COOLDOWN
        end

        -- 释放 CPU 调度权 (10ms)
        freertos_delay_ms(10)
    end
end

C_PICO.stdio_init_all()
print("🛰️ 准备装载 L2C 全自动狙击任务...")
freertos_create_task("SniperTask", L2C_FuncPtr(sniper_task))
freertos_start()
