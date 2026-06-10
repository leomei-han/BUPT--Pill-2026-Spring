// ============================================================
//  seg_output  —  数码管显示驱动
//  职责: 根据系统状态选择显示内容, 支持闪烁提示
//
//  纯组合逻辑模块：没有任何寄存器，不消耗宏单元的触发器资源
//  闪烁功能直接复用外部 clk_1Hz 的电平，不需要额外的分频计数器
// ============================================================
module seg_output(
    input         clk_1Hz,          // 1 Hz 时钟（直接用电平做闪烁，省掉分频计数器）
    input         mode_switch,      // SW10: 运行/配置模式
    input         setting_switch,   // SW9:  装入量/瓶数选择
    input  [7:0]  input_data,       // 拨码开关当前 BCD 值（配置态预览用）
    input         input_valid,      // sw_checker 校验结果
    input  [7:0]  pills_per_bottle, // 已锁存的每瓶装入量
    input  [7:0]  target_bottles,   // 已锁存的目标瓶数（扩展十位编码）
    input  [11:0] total_pills_bcd,  // 药片累计（运行态显示用）
    input  [7:0]  current_pills_bcd,// 当前瓶药片数
    input  [7:0]  bottle_count_bcd, // 已完成瓶数（扩展十位编码）
    input         bottle_full_hint, // 当前瓶即将满（LG1 显示预警）
    input  [1:0]  work_state,       // FSM 当前状态
    output reg [4:1] display1,      // 数码管第 1 位（板上 LG6，瓶数百位）
    output reg [4:1] display2,      // 数码管第 2 位（瓶数十位）
    output reg [4:1] display3,      // 数码管第 3 位（瓶数个位）
    output reg [4:1] display4,      // 数码管第 4 位
    output reg [4:1] display5,      // 数码管第 5 位
    output reg [6:0] LG1            // 七段状态指示灯
);

    // ---- 状态常量 (保持与 bottle_fsm 一致) ----
    localparam S_CFG  = 2'b00;
    localparam S_RUN  = 2'b01;
    localparam S_HALT = 2'b10;
    localparam S_WARN = 2'b11;
    localparam [7:0] DEFAULT_FILL = 8'h10;
    localparam [7:0] DEFAULT_GOAL = 8'h05;

    // LG1 七段码常量：[6:0] 对应 g f e d c b a，高电平点亮
    localparam [6:0] SEG_BLANK = 7'b0000000;    // 全灭
    localparam [6:0] SEG_0     = 7'b0111111;    // 显示 "0"：配置态
    localparam [6:0] SEG_1     = 7'b0000110;    // 显示 "1"：运行态
    localparam [6:0] SEG_2     = 7'b1011011;    // 显示 "2"：当前瓶即将满（预警）
    localparam [6:0] SEG_3     = 7'b1001111;    // 显示 "3"：持续警报态
    localparam [6:0] SEG_4     = 7'b1100110;    // 显示 "4"：目标达成提醒态
    localparam [6:0] SEG_E     = 7'b1111001;    // 显示 "E"：输入非法错误提示

    // ---- 闪烁条件 ----
    // 直接用 clk_1Hz 电平做闪烁开关，高电平时灭、低电平时亮
    // 省掉了一组分频计数器寄存器
    wire flash = clk_1Hz;
    wire is_cfg_mode  = (work_state == S_CFG);              // 当前处于配置态
    wire is_edit_mode = is_cfg_mode & ~mode_switch;         // 配置态且 SW10=0，允许编辑
    wire fl_btl_sel   = is_edit_mode &  setting_switch & flash; // 正在编辑瓶数 → 该参数闪烁
    wire fl_fill_sel  = is_edit_mode & ~setting_switch & flash; // 正在编辑装入量 → 该参数闪烁
    wire fl_done      = (work_state == S_HALT) & flash;     // 达标后全屏闪灭
    wire invalid_cfg  = is_edit_mode & ~input_valid;        // 当前输入非法

    // ---- 瓶数三位换算（组合逻辑，配置/运行两种画面共用一份） ----
    // 瓶数采用扩展十位编码：[7:4] 为二进制十位 0~15，[3:0] 为 BCD 个位
    // 十位 ≥ 10 表示数值 ≥ 100：百位显示 1，十位显示 hi-10（0~5）
    // 显示源三选一：编辑瓶数时实时预览拨码值（非法回退默认值）→
    //               配置态其余情况显示已锁存目标值 → 运行态显示已完成瓶数
    wire [7:0] goal_preview = (is_edit_mode & setting_switch)
                            ? (input_valid ? input_data : DEFAULT_GOAL)
                            : target_bottles;
    wire [7:0] btl_src   = is_cfg_mode ? goal_preview : bottle_count_bcd;
    wire       btl_ge100 = (btl_src[7:4] >= 4'd10);          // 数值 ≥ 100
    wire [3:0] btl_hund  = btl_ge100 ? 4'd1 : 4'd0;          // 百位（上限 159，只会是 0/1）
    wire [3:0] btl_tens  = btl_ge100 ? (btl_src[7:4] - 4'd10)// 十位 10~15 → 显示 0~5
                                     : btl_src[7:4];

    // ---- 组合逻辑: 根据 FSM 状态选择 5 位数码管显示内容 ----
    // 4'hF 表示灭（数码管 BCD 译码器对 F 不显示任何笔段）
    always @(*) begin
        if (is_cfg_mode) begin
            // ===== 配置画面：显示参数预览，正在编辑的参数闪烁 =====

            // 第 1-3 位：目标瓶数（百/十/个位，源选择与换算见上方 btl_* 信号）
            // 正在编辑瓶数(sw_sel=1)时三位一起闪烁；非法输入时预览回退默认值
            // 百位常显（含 0），保持配置画面原有的"第 1 位亮 0"外观
            display1 = fl_btl_sel ? 4'hF : btl_hund;
            display2 = fl_btl_sel ? 4'hF : btl_tens;
            display3 = fl_btl_sel ? 4'hF : btl_src[3:0];

            // 第 4-5 位：每瓶装入量（逻辑同上）
            if (is_edit_mode & ~setting_switch) begin
                display4 = fl_fill_sel ? 4'hF : (input_valid ? input_data[7:4] : DEFAULT_FILL[7:4]);
                display5 = fl_fill_sel ? 4'hF : (input_valid ? input_data[3:0] : DEFAULT_FILL[3:0]);
            end
            else begin
                display4 = fl_fill_sel ? 4'hF : pills_per_bottle[7:4];
                display5 = fl_fill_sel ? 4'hF : pills_per_bottle[3:0];
            end
        end
        else begin
            // ===== 运行画面：显示实时计数 =====
            if (fl_done) begin
                // 达标提醒态(S_HALT)：全部数码管随 1 Hz 闪灭，提醒操作员
                display1 = 4'hF;  display2 = 4'hF;  display3 = 4'hF;
                display4 = 4'hF;  display5 = 4'hF;
            end
            else begin
                display1 = btl_ge100 ? btl_hund : 4'hF; // 第 1 位：瓶数百位（<100 时灭，保持原外观）
                display2 = btl_tens;                    // 第 2 位：已完成瓶数十位
                display3 = btl_src[3:0];                // 第 3 位：已完成瓶数个位
                display4 = current_pills_bcd[7:4];      // 第 4 位：当前瓶药片十位
                display5 = current_pills_bcd[3:0];      // 第 5 位：当前瓶药片个位
            end
        end

        // ===== LG1 七段状态指示灯 =====
        // 优先级从高到低：非法输入(E闪烁) > 达标(4) > 警报(3) > 瓶满预警(2) > 运行(1) > 配置(0)
        if (invalid_cfg)
            LG1 = flash ? SEG_BLANK : SEG_E;           // 非法输入：E 与空白交替闪烁
        else if (work_state == S_HALT)
            LG1 = SEG_4;                                // 目标达成提醒
        else if (work_state == S_WARN)
            LG1 = SEG_3;                                // 持续警报
        else if ((work_state == S_RUN) & bottle_full_hint)
            LG1 = SEG_2;                                // 运行中且当前瓶即将满
        else if (work_state == S_RUN)
            LG1 = SEG_1;                                // 正常运行
        else
            LG1 = SEG_0;                                // 配置态
    end

endmodule
