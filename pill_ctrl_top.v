// ============================================================
//  pill_ctrl_top  —  顶层模块
//  功能: 信号互联、开关分配、按键消抖、参数锁存
// ============================================================
module pill_ctrl_top(
    input  clk_10kHz,
    input  clk_1Hz,
    input  QD,
    input  reset_sw,
    input  [10:1] switches,
    output [4:1]  display1,
    output [4:1]  display2,
    output [4:1]  display3,
    output [4:1]  display4,
    output [4:1]  display5,
    output [6:0]  LG1,
    output        buzzer
);

    // ---------- 开关映射 ----------
    wire       sw_mode   = switches[10];    // 1 = 运行, 0 = 配置
    wire       sw_sel    = switches[9];     // 0 = 装入量, 1 = 瓶数
    wire [7:0] sw_dat    = switches[8:1];   // BCD 数据

    localparam [7:0] DEFAULT_FILL = 8'h10;  // 默认 10 颗/瓶
    localparam [7:0] DEFAULT_GOAL = 8'h05;  // 默认 5 瓶

    // ---------- 内部信号 ----------
    wire        trig_pulse;         // 消抖后的 QD 单脉冲
    wire        sys_rst;            // 同步复位
    wire        med_tick;           // 1 Hz 药片节拍
    wire        dat_ok;             // 输入范围合法标志
    wire [1:0]  fsm_st;            // 控制器状态
    wire [11:0] sum_pills;         // 累计药片(3位BCD)
    wire [7:0]  cur_pills;         // 本瓶药片(2位BCD)
    wire [7:0]  done_btl;          // 已完成瓶数(2位BCD)
    wire        bottle_full_hint;  // 当前瓶即将满
    wire        buzzer_en;          // 蜂鸣器使能(FSM输出)

    // ---------- 参数寄存器 ----------
    reg [7:0] cfg_fill;            // 每瓶装入量
    reg [7:0] cfg_goal;            // 目标瓶数

    // ---------- QD 消抖 (2-bit 移位) ----------
    reg [1:0] r_qd;
    always @(posedge clk_10kHz)
        r_qd <= {r_qd[0], QD};

    assign trig_pulse = (r_qd == 2'b01);   // 捕获上升沿

    // ---------- 复位电平开关同步 (高电平有效) ----------
    wire raw_reset_sw = reset_sw;
    reg [1:0] r_reset_sw;
    always @(posedge clk_10kHz)
        r_reset_sw <= {r_reset_sw[0], raw_reset_sw};

    assign sys_rst = r_reset_sw[1];

    // ---------- 参数锁存 ----------
    always @(posedge clk_10kHz) begin
        if (sys_rst) begin
            cfg_fill <= DEFAULT_FILL;
            cfg_goal <= DEFAULT_GOAL;
        end
        else if (~sw_mode & trig_pulse) begin
            if (~sw_sel)
                cfg_fill <= dat_ok ? sw_dat : DEFAULT_FILL;
            else
                cfg_goal <= dat_ok ? sw_dat : DEFAULT_GOAL;
        end
    end

    // ---------- 子模块实例化 ----------
    pulse_sync u_pulse_sync(
        .clk_10kHz  (clk_10kHz),
        .clk_1Hz    (clk_1Hz),
        .pill_pulse (med_tick)
    );

    sw_checker u_sw_checker(
        .input_data     (sw_dat),
        .setting_switch (sw_sel),
        .input_valid    (dat_ok)
    );

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

    // ---------- 蜂鸣器驱动: 2.5 kHz 方波(无源蜂鸣器需要交流信号) ----------
    reg [1:0] buzz_cnt;
    always @(posedge clk_10kHz)
        buzz_cnt <= buzz_cnt + 1'b1;

    assign buzzer = buzzer_en & buzz_cnt[1] & (fsm_st[0] | clk_1Hz);

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
