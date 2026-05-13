// ============================================================
//  seg_output  —  数码管显示驱动
//  职责: 根据系统状态选择显示内容, 支持闪烁提示
// ============================================================
module seg_output(
    input         clk_1Hz,
    input         mode_switch,
    input         setting_switch,
    input  [7:0]  input_data,
    input         input_valid,
    input  [7:0]  pills_per_bottle,
    input  [7:0]  target_bottles,
    input  [11:0] total_pills_bcd,
    input  [7:0]  current_pills_bcd,
    input  [7:0]  bottle_count_bcd,
    input         bottle_full_hint,
    input  [1:0]  work_state,
    output reg [4:1] display1,
    output reg [4:1] display2,
    output reg [4:1] display3,
    output reg [4:1] display4,
    output reg [4:1] display5,
    output reg [6:0] LG1
);

    // ---- 状态常量 (保持与 bottle_fsm 一致) ----
    localparam S_CFG  = 2'b00;
    localparam S_RUN  = 2'b01;
    localparam S_HALT = 2'b10;
    localparam S_WARN = 2'b11;
    localparam [7:0] DEFAULT_FILL = 8'h10;
    localparam [7:0] DEFAULT_GOAL = 8'h05;

    // LG1[0]..LG1[6] 对应七段 a..g, 高电平点亮。
    localparam [6:0] SEG_BLANK = 7'b0000000;
    localparam [6:0] SEG_0     = 7'b0111111;
    localparam [6:0] SEG_1     = 7'b0000110;
    localparam [6:0] SEG_2     = 7'b1011011;
    localparam [6:0] SEG_3     = 7'b1001111;
    localparam [6:0] SEG_4     = 7'b1100110;
    localparam [6:0] SEG_E     = 7'b1111001;

    // ---- 闪烁条件 ----
    wire flash = clk_1Hz;                                       // 1 Hz 节拍
    wire is_cfg_mode  = (~mode_switch) & (work_state == S_CFG); // 处于真实配置态
    wire fl_btl_sel   = is_cfg_mode &  setting_switch & flash;  // 瓶数参数闪烁
    wire fl_fill_sel  = is_cfg_mode & ~setting_switch & flash;  // 装入量参数闪烁
    wire fl_done      = (work_state == S_HALT) & flash; // 完成闪烁
    wire invalid_cfg   = is_cfg_mode & ~input_valid;

    // ---- 组合逻辑: 生成待显示 BCD 值 ----
    always @(*) begin
        if (is_cfg_mode) begin
            // ===== 配置画面 =====
            display1 = (invalid_cfg & flash) ? 4'hF : 4'h0;

            // 位 2-3: 目标瓶数
            if (setting_switch) begin
                display2 = fl_btl_sel ? 4'hF : (input_valid ? input_data[7:4] : DEFAULT_GOAL[7:4]);
                display3 = fl_btl_sel ? 4'hF : (input_valid ? input_data[3:0] : DEFAULT_GOAL[3:0]);
            end
            else begin
                display2 = fl_btl_sel ? 4'hF : target_bottles[7:4];
                display3 = fl_btl_sel ? 4'hF : target_bottles[3:0];
            end

            // 位 4-5: 每瓶装入量
            if (~setting_switch) begin
                display4 = fl_fill_sel ? 4'hF : (input_valid ? input_data[7:4] : DEFAULT_FILL[7:4]);
                display5 = fl_fill_sel ? 4'hF : (input_valid ? input_data[3:0] : DEFAULT_FILL[3:0]);
            end
            else begin
                display4 = fl_fill_sel ? 4'hF : pills_per_bottle[7:4];
                display5 = fl_fill_sel ? 4'hF : pills_per_bottle[3:0];
            end
        end
        else begin
            // ===== 运行画面 =====
            if (fl_done) begin
                // 达标后整体闪灭
                display1 = 4'hF;  display2 = 4'hF;  display3 = 4'hF;
                display4 = 4'hF;  display5 = 4'hF;
            end
            else begin
                display1 = total_pills_bcd[11:8];
                display2 = total_pills_bcd[7:4];
                display3 = total_pills_bcd[3:0];
                display4 = work_state[1] ? bottle_count_bcd[7:4] : current_pills_bcd[7:4];
                display5 = work_state[1] ? bottle_count_bcd[3:0] : current_pills_bcd[3:0];
            end
        end

        // LG1 状态位: 非法输入 > 完成 > 报警 > 当前瓶满 > 运行 > 配置
        if (invalid_cfg)
            LG1 = flash ? SEG_BLANK : SEG_E;
        else if (work_state == S_HALT)
            LG1 = SEG_4;
        else if (work_state == S_WARN)
            LG1 = SEG_3;
        else if ((work_state == S_RUN) & bottle_full_hint)
            LG1 = SEG_2;
        else if (work_state == S_RUN)
            LG1 = SEG_1;
        else
            LG1 = SEG_0;
    end

endmodule
