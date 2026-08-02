-- ==============================================================================
-- examples/20_pico_sniper_dma.tl
-- 终极边缘声纹刺客：DMA 硬件泵 -> 无锁流水线 -> Core 1 Q15 DSP 大脑 -> 继电器
-- ==============================================================================

-- @l2c_import: std/pico.tl
-- @l2c_import: std/multicore.tl
-- @l2c_import: std/ringbuffer.tl
-- @l2c_import: std/dsp.tl

local function delay_ms(ms: integer)
    C_PICO.sleep_us(ms * 1000)
end

-- 🛡️ 单例屏障：确保全局物理内存绝对唯一
local function Get_SharedQueue(): SPSC_Queue
    return SPSC_Queue._cast(L2C_Static("SPSC_Queue"))
end

local function Get_DMABuffer(): integer
    -- 向底层勒索 256 个整数的连续物理内存，转化为整数指针
    return L2C_PtrAsInt(L2C_Static("[256]integer"))
end

-- ============================================================================
-- ⚡ 硬件中断服务程序 (ISR)
-- 警告：运行在芯片最底层的 IRQ 上下文！绝对禁止延时、闭包和打印！
-- ============================================================================
local function dma_isr_handler()
    local q = Get_SharedQueue()
    local buf_ptr = Get_DMABuffer()
    
    -- ⚡ 修复核心：使用 16 位专属物理探针读取 DMA 紧凑写入的数据！
    for i = 0, 255 do
        local val = C_PICO.l2c_read_adc_buf16(buf_ptr, i)
        SPSC_Push(q, val)
    end
    
    -- 🚀 极简物理传参：直接传入 integer
    C_PICO.l2c_pico_dma_irq_clear_and_restart(0, buf_ptr)
end

-- ============================================================================
-- 🧠 副核 (Core 1) 任务：Q15 DSP 大脑与状态机
-- ============================================================================
local function sniper_brain_task()
    local q = Get_SharedQueue()
    local out = IntBox._new() -- 0-GC 装箱指针
    
    -- 申请专属的 Core 1 DSP 计算缓冲物理内存
    local dsp_buf = L2C_PtrAsInt(L2C_Static("[256]integer"))
    local CHUNK_SIZE = 256

    -- 初始化电磁铁继电器
    C_PICO.gpio_init(14) C_PICO.gpio_set_dir(14, PICO_GPIO_OUT) C_PICO.gpio_put(14, 1) -- 收竿
    C_PICO.gpio_init(15) C_PICO.gpio_set_dir(15, PICO_GPIO_OUT) C_PICO.gpio_put(15, 1) -- 抛竿

    -- Q15 定点数系数 (精确无溢出)
    local COEFF_800HZ_Q15 = 53020
    local COEFF_3000HZ_Q15 = -46341

    local STATE_COOLDOWN   = 0
    local STATE_CASTING    = 1
    local STATE_VERIFYING  = 2
    local STATE_WAIT_FISH  = 3
    local STATE_CATCHING   = 4

    local current_state = STATE_COOLDOWN
    local state_timer_ms = 0
    local cast_timer_ms = 0
    local cooldown_duration_ms = 2000

    print("🚀 [Core 1 大脑] Q15 DSP 狙击手已就位，开启监听...")
    
    while true do
        if current_state == STATE_COOLDOWN then
            -- 冷却期直接排空队列，休眠省电
            while SPSC_Pop(q, out) do end
            delay_ms(10)
            state_timer_ms = state_timer_ms + 10
            
            if state_timer_ms >= cooldown_duration_ms then
                print("✅ 冷却完毕，执行抛竿！")
                current_state = STATE_CASTING
            end

        elseif current_state == STATE_CASTING then
            C_PICO.gpio_put(15, 0) delay_ms(120) C_PICO.gpio_put(15, 1)
            state_timer_ms = 0
            cast_timer_ms = 0
            
            -- 瞬间排空抛竿带来的机械噪音
            while SPSC_Pop(q, out) do end
            current_state = STATE_VERIFYING
            print("🔍 抛竿完成！监听 800Hz 退货警告...")

        elseif current_state == STATE_VERIFYING or current_state == STATE_WAIT_FISH then
            
            -- 🟢 阻塞式汲取 256 个点 (精确耗时 32ms，绝对的物理时钟锚点！)
            local count = 0
            while count < CHUNK_SIZE do
                if SPSC_Pop(q, out) then
                    L2C_WriteArray(dsp_buf, count, out.val)
                    count = count + 1
                end
            end
            
            state_timer_ms = state_timer_ms + 32
            cast_timer_ms = cast_timer_ms + 32
            
            if current_state == STATE_VERIFYING and state_timer_ms >= 1500 then
                print("🟢 1.5秒验货通过！安稳等鱼...")
                current_state = STATE_WAIT_FISH
            end
            
            if current_state == STATE_WAIT_FISH and cast_timer_ms >= 23000 then
                print("⚠️ [熔断] 23秒无鱼！重抛！")
                cooldown_duration_ms = 1500
                state_timer_ms = 0
                current_state = STATE_COOLDOWN
            else
                -- 🧮 Q15 定点数 DSP 极限运算
                local sum = 0
                for i = 0, CHUNK_SIZE - 1 do sum = sum + L2C_ReadArray(dsp_buf, i) end
                local mean = sum // CHUNK_SIZE
                
                local variance_sum = 0
                for i = 0, CHUNK_SIZE - 1 do
                    local v = L2C_ReadArray(dsp_buf, i) - mean
                    L2C_WriteArray(dsp_buf, i, v)
                    variance_sum = variance_sum + (v * v)
                end
                -- 去除放大倍数后的伪方差
                local v_std = variance_sum // CHUNK_SIZE 
                
                -- 动态阈值判定 (由于是 12bit ADC 的方差，您可根据真实环境调试)
                if v_std > 5000 then
                    local power_800 = dsp_goertzel_mag_q15(dsp_buf, COEFF_800HZ_Q15, 256)
                    local power_3000 = dsp_goertzel_mag_q15(dsp_buf, COEFF_3000HZ_Q15, 256)
                    
                    if current_state == STATE_VERIFYING and power_800 > power_3000 * 10 then
                        print("🔴 [退货警告] 800Hz 纯音！抛偏，重抛！")
                        current_state = STATE_CASTING
                    elseif current_state == STATE_WAIT_FISH and power_3000 > power_800 * 10 then
                        print("🎯 [完美中鱼] 3000Hz 纯音！收网！")
                        current_state = STATE_CATCHING
                    end
                end
            end

        elseif current_state == STATE_CATCHING then
            C_PICO.gpio_put(14, 0) delay_ms(120) C_PICO.gpio_put(14, 1)
            print("⏳ 鱼已入包！休眠防抖...")
            cooldown_duration_ms = 5000
            state_timer_ms = 0
            current_state = STATE_COOLDOWN
        end
    end
end

-- ============================================================================
-- 🫀 主核 (Core 0) 任务：全自动 DMA 硬件总线装配
-- ============================================================================
C_PICO.stdio_init_all()
print("🛰️ [系统] L2C 硬件架构苏醒！")

-- 1. 初始化容量为 1024 的 SPSC 跨核无锁隧道
local q = Get_SharedQueue()
local q_buf = L2C_PtrAsInt(L2C_Static("[1024]integer"))
SPSC_Init(q, 1024, q_buf)

-- 2. 点火！将大脑发射至 Core 1 物理核
Multicore_Launch(L2C_FuncPtr(sniper_brain_task))

-- 3. 挂载 DMA 硬件泵，移交控制权！
print("🫀 [Core 0] 正在挂载 DMA 硬件泵，设置 IRQ 中断...")
local dma_buf = Get_DMABuffer()
C_PICO.l2c_pico_adc_dma_start(0, dma_buf, 256, L2C_FuncPtr(dma_isr_handler))

print("✅ [Core 0] 硬件泵移交完毕！主 CPU 彻底解放，进入深度休眠维持心跳！")

while true do
    -- Core 0 没有任何业务逻辑，纯粹作为看门狗心跳存在
    delay_ms(1000)
    print("💓 [Core 0] System Heartbeat...")
end
