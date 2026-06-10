// ============================================================
//  pill_ctrl_top  —  顶层模块
//  功能: 信号互联、开关分配、按键消抖、参数锁存
//  所有子模块在此实例化，统一运行在 10 kHz 主时钟域
// ============================================================
module pill_ctrl_top(
    input  clk_10kHz,           // TEC-8 提供的 10 kHz 主时钟
    input  clk_1Hz,             // TEC-8 提供的 1 Hz 时钟（模拟药片传感器）
    input  QD,                  // QD 按键（脉冲型，需要消抖）
    input  reset_sw,            // 复位拨码开关（电平型，高有效）
    input  [10:1] switches,     // 10 位拨码开关
    output [4:1]  display1,     // 数码管第 1 位（板上 LG6，瓶数百位）
    output [4:1]  display2,     // 数码管第 2 位（已完成瓶数十位）
    output [4:1]  display3,     // 数码管第 3 位（已完成瓶数个位）
    output [4:1]  display4,     // 数码管第 4 位（当前瓶药片十位）
    output [4:1]  display5,     // 数码管第 5 位（当前瓶药片个位）
    output [6:0]  LG1,          // 七段状态指示灯
    output        buzzer        // 蜂鸣器输出（2.5 kHz 方波）
);

    // ---------- 开关映射 ----------
    // 10 个拨码开关按功能划分为三组
    wire       sw_mode   = switches[10];    // SW10: 1=运行模式, 0=配置模式
    wire       sw_sel    = switches[9];     // SW9:  0=设置装入量, 1=设置瓶数
    wire [7:0] sw_dat    = switches[8:1];   // SW8~SW1: 8 位数据输入
                                            // 装入量: 2 位 BCD（01~99）
                                            // 瓶数: 扩展十位编码，SW8~5 二进制十位 0~15，SW4~1 BCD 个位（001~159）

    // 安全默认值：当输入非法时自动回退到这些值
    localparam [7:0] DEFAULT_FILL = 8'h10;  // 默认每瓶 10 颗（BCD 编码）
    localparam [7:0] DEFAULT_GOAL = 8'h05;  // 默认目标 5 瓶（BCD 编码）

    // ---------- 内部信号 ----------
    wire        trig_pulse;         // QD 消抖后的单周期脉冲（上升沿）
    wire        sys_rst;            // 同步复位信号（经两级同步后的电平）
    wire        med_tick;           // 1 Hz 药片节拍（经 pulse_sync 同步后的单周期脉冲）
    wire        dat_ok;             // sw_checker 输出：输入 BCD 数据范围合法
    wire [1:0]  fsm_st;            // bottle_fsm 输出：当前状态码
    wire [11:0] sum_pills;         // bottle_fsm 输出：累计药片（3 位 BCD）
    wire [7:0]  cur_pills;         // bottle_fsm 输出：本瓶药片（2 位 BCD）
    wire [7:0]  done_btl;          // bottle_fsm 输出：已完成瓶数（扩展十位编码，000-159）
    wire        bottle_full_hint;  // bottle_fsm 输出：当前瓶即将满
    wire        buzzer_en;          // bottle_fsm 输出：蜂鸣器使能

    // ---------- 参数寄存器 ----------
    reg [7:0] cfg_fill;            // 每瓶装入量（2 位 BCD，锁存后送 bottle_fsm）
    reg [7:0] cfg_goal;            // 目标瓶数  （扩展十位编码 001~159，锁存后送 bottle_fsm）

    // ---------- QD 按键消抖 (2-bit 移位寄存器 + 上升沿检测) ----------
    // QD 是脉冲型按键，需要捕获上升沿并产生单周期脉冲
    reg [1:0] r_qd;
    always @(posedge clk_10kHz)
        r_qd <= {r_qd[0], QD};

    // 前一拍为 0、当前拍为 1 → 上升沿，输出一个主时钟周期的脉冲
    assign trig_pulse = (r_qd == 2'b01);

    // ---------- 复位：电平开关同步 (不是 CLR 全局复位) ----------
    // 使用拨码开关而非按键作为复位信号，好处：
    //   1. 电平型信号只需同步不需消抖，省掉边沿检测比较器（对比 QD 多了 ==2'b01）
    //   2. 不依赖 TEC-8 的 CLR 全局复位，避免干扰其他实验功能
    // 两级寄存器同步：消除异步信号跨时钟域的亚稳态
    wire raw_reset_sw = reset_sw;
    reg [1:0] r_reset_sw;
    always @(posedge clk_10kHz)
        r_reset_sw <= {r_reset_sw[0], raw_reset_sw};

    // 直接取最后一级的电平值，不做边沿检测 → 比 QD 少一个比较器
    assign sys_rst = r_reset_sw[1];

    // ---------- 参数锁存 ----------
    // 仅在配置态（sw_mode=0）按下 QD 时写入，运行中不可修改（安全联锁）
    always @(posedge clk_10kHz) begin
        if (sys_rst) begin
            cfg_fill <= DEFAULT_FILL;       // 复位恢复默认值
            cfg_goal <= DEFAULT_GOAL;
        end
        else if (~sw_mode & trig_pulse) begin
            // sw_sel=0 写装入量，sw_sel=1 写瓶数
            // dat_ok 由 sw_checker 提供：非法输入自动回退默认值，不会写入错误参数
            if (~sw_sel)
                cfg_fill <= dat_ok ? sw_dat : DEFAULT_FILL;
            else
                cfg_goal <= dat_ok ? sw_dat : DEFAULT_GOAL;
        end
    end

    // ---------- 子模块实例化 ----------

    // 跨时钟域同步：将异步 1 Hz 信号转为主时钟域的单周期脉冲
    pulse_sync u_pulse_sync(
        .clk_10kHz  (clk_10kHz),
        .clk_1Hz    (clk_1Hz),
        .pill_pulse (med_tick)
    );

    // 输入校验：纯组合逻辑，不占寄存器资源
    sw_checker u_sw_checker(
        .input_data     (sw_dat),
        .setting_switch (sw_sel),
        .input_valid    (dat_ok)
    );

    // 流程核心：4 状态 FSM + BCD 计数 + 预判换瓶
    bottle_fsm u_bottle_fsm(
        .clk              (clk_10kHz),
        .reset            (sys_rst),
        .mode_switch      (sw_mode),
        .qd_pressed       (trig_pulse),
        .pill_pulse       (med_tick),
        .pills_per_bottle (cfg_fill),
        .target_bottles   (cfg_goal),
        .work_state       (fsm_st),
        .total_pills_bcd  (sum_pills),
        .current_pills_bcd(cur_pills),
        .bottle_count_bcd (done_btl),
        .bottle_full_hint  (bottle_full_hint),
        .buzzer           (buzzer_en)
    );

    // ---------- 蜂鸣器驱动 ----------
    // TEC-8 上是无源蜂鸣器，需要交流方波驱动
    // 2-bit 计数器对 10 kHz 四分频 → buzz_cnt[1] 产生 2.5 kHz 方波
    reg [1:0] buzz_cnt;
    always @(posedge clk_10kHz)
        buzz_cnt <= buzz_cnt + 1'b1;

    // 一个表达式实现两种报警模式，不需要 mux：
    //   S_WARN(11): fsm_st[0]=1 → OR 恒为 1 → 蜂鸣器持续响
    //   S_HALT(10): fsm_st[0]=0 → 跟随 clk_1Hz → 间歇鸣叫（1秒响1秒停）
    assign buzzer = buzzer_en & buzz_cnt[1] & (fsm_st[0] | clk_1Hz);

    // 显示驱动：纯组合逻辑，不占寄存器资源
    seg_output u_seg_output(
        .clk_1Hz          (clk_1Hz),
        .mode_switch      (sw_mode),
        .setting_switch   (sw_sel),
        .input_data       (sw_dat),
        .input_valid      (dat_ok),
        .pills_per_bottle (cfg_fill),
        .target_bottles   (cfg_goal),
        .total_pills_bcd  (sum_pills),
        .current_pills_bcd(cur_pills),
        .bottle_count_bcd (done_btl),
        .bottle_full_hint  (bottle_full_hint),
        .work_state       (fsm_st),
        .display1         (display1),
        .display2         (display2),
        .display3         (display3),
        .display4         (display4),
        .display5         (display5),
        .LG1              (LG1)
    );

endmodule
