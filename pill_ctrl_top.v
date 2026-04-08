// ============================================================
//  pill_ctrl_top  —  顶层模块
//  功能: 信号互联、开关分配、按键消抖、参数锁存
// ============================================================
module pill_ctrl_top(
    input  clk_10kHz,
    input  clk_1Hz,
    input  QD,
    input  CLR,
    input  [10:1] switches,
    output [4:1]  display1,
    output [4:1]  display2,
    output [4:1]  display3,
    output [4:1]  display4,
    output [4:1]  display5,
    output        buzzer
);

    // ---------- 开关映射 ----------
    wire       sw_mode   = switches[10];    // 1 = 运行, 0 = 配置
    wire       sw_sel    = switches[9];     // 0 = 装入量, 1 = 瓶数
    wire [7:0] sw_dat    = switches[8:1];   // BCD 数据

    // ---------- 内部信号 ----------
    wire        trig_pulse;         // 消抖后的 QD 单脉冲
    wire        sys_rst;            // 同步复位
    wire        med_tick;           // 1 Hz 药片节拍
    wire        dat_ok;             // 输入范围合法标志
    wire [1:0]  fsm_st;            // 控制器状态
    wire [11:0] sum_pills;         // 累计药片(3位BCD)
    wire [7:0]  cur_pills;         // 本瓶药片(2位BCD)
    wire [7:0]  done_btl;          // 已完成瓶数(2位BCD)

    // ---------- 参数寄存器 ----------
    reg [7:0] cfg_fill;            // 每瓶装入量
    reg [7:0] cfg_goal;            // 目标瓶数

    // ---------- QD 消抖 (2-bit 移位) ----------
    reg [1:0] r_qd;
    always @(posedge clk_10kHz)
        r_qd <= {r_qd[0], QD};

    assign trig_pulse = (r_qd == 2'b01);   // 捕获上升沿

    // ---------- CLR 同步 (3-bit 移位, 原信号低有效) ----------
    reg [2:0] r_clr;
    always @(posedge clk_10kHz)
        r_clr <= {r_clr[1:0], ~CLR};

    assign sys_rst = r_clr[2];

    // ---------- 参数锁存 ----------
    always @(posedge clk_10kHz or posedge sys_rst) begin
        if (sys_rst) begin
            cfg_fill <= 8'h10;    // 上电默认 10 颗/瓶
            cfg_goal <= 8'h05;    // 上电默认 5 瓶
        end
        else if (~sw_mode & trig_pulse & dat_ok) begin
            if (~sw_sel)
                cfg_fill <= sw_dat;
            else
                cfg_goal <= sw_dat;
        end
    end

    // ---------- 子模块实例化 ----------
    pulse_sync u_pulse_sync(
        .clk_10kHz  (clk_10kHz),
        .clk_1Hz    (clk_1Hz),
        .reset      (sys_rst),
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
        .buzzer           (buzzer)
    );

    seg_output u_seg_output(
        .clk              (clk_10kHz),
        .clk_1Hz          (clk_1Hz),
        .reset            (sys_rst),
        .mode_switch      (sw_mode),
        .setting_switch   (sw_sel),
        .input_data       (sw_dat),
        .input_valid      (dat_ok),
        .pills_per_bottle (cfg_fill),
        .target_bottles   (cfg_goal),
        .total_pills_bcd  (sum_pills),
        .current_pills_bcd(cur_pills),
        .bottle_count_bcd (done_btl),
        .work_state       (fsm_st),
        .display1         (display1),
        .display2         (display2),
        .display3         (display3),
        .display4         (display4),
        .display5         (display5)
    );

endmodule