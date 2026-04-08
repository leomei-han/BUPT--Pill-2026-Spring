// ============================================================
//  seg_output  —  数码管显示驱动
//  职责: 根据系统状态选择显示内容, 支持闪烁提示
// ============================================================
module seg_output(
    input         clk,
    input         clk_1Hz,
    input         reset,
    input         mode_switch,
    input         setting_switch,
    input  [7:0]  input_data,
    input         input_valid,
    input  [7:0]  pills_per_bottle,
    input  [7:0]  target_bottles,
    input  [11:0] total_pills_bcd,
    input  [7:0]  current_pills_bcd,
    input  [7:0]  bottle_count_bcd,
    input  [1:0]  work_state,
    output reg [4:1] display1,
    output reg [4:1] display2,
    output reg [4:1] display3,
    output reg [4:1] display4,
    output reg [4:1] display5
);

    // ---- 状态常量 (保持与 bottle_fsm 一致) ----
    localparam S_CFG  = 2'b00;
    localparam S_RUN  = 2'b01;
    localparam S_HALT = 2'b10;
    localparam S_WARN = 2'b11;

    // ---- 闪烁条件 ----
    wire flash = clk_1Hz;                                       // 1 Hz 节拍
    wire is_cfg_mode  = (~mode_switch) & (work_state == S_CFG); // 处于真实配置态
    wire fl_btl_sel   = is_cfg_mode &  setting_switch & flash;  // 瓶数参数闪烁
    wire fl_fill_sel  = is_cfg_mode & ~setting_switch & flash;  // 装入量参数闪烁
    wire fl_done      = mode_switch  & (work_state == S_HALT) & flash; // 完成闪烁

    // ---- 组合逻辑: 生成待显示 BCD 值 ----
    reg [4:1] seg1, seg2, seg3, seg4, seg5;

    always @(*) begin
        if (~mode_switch) begin
            // ===== 配置画面 =====
            seg1 = 4'h0;

            // 位 2-3: 目标瓶数
            if (is_cfg_mode & setting_switch & input_valid) begin
                seg2 = fl_btl_sel ? 4'hF : input_data[7:4];
                seg3 = fl_btl_sel ? 4'hF : input_data[3:0];
            end
            else begin
                seg2 = fl_btl_sel ? 4'hF : target_bottles[7:4];
                seg3 = fl_btl_sel ? 4'hF : target_bottles[3:0];
            end

            // 位 4-5: 每瓶装入量
            if (is_cfg_mode & ~setting_switch & input_valid) begin
                seg4 = fl_fill_sel ? 4'hF : input_data[7:4];
                seg5 = fl_fill_sel ? 4'hF : input_data[3:0];
            end
            else begin
                seg4 = fl_fill_sel ? 4'hF : pills_per_bottle[7:4];
                seg5 = fl_fill_sel ? 4'hF : pills_per_bottle[3:0];
            end
        end
        else begin
            // ===== 运行画面 =====
            if (fl_done) begin
                // 达标后整体闪灭
                seg1 = 4'hF;  seg2 = 4'hF;  seg3 = 4'hF;
                seg4 = 4'hF;  seg5 = 4'hF;
            end
            else begin
                seg1 = total_pills_bcd[11:8];
                seg2 = total_pills_bcd[7:4];
                seg3 = total_pills_bcd[3:0];
                seg4 = current_pills_bcd[7:4];
                seg5 = current_pills_bcd[3:0];
            end
        end
    end

    // ---- 输出寄存器: 消除组合毛刺 ----
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            display1 <= 4'h0;
            display2 <= 4'h0;
            display3 <= 4'h0;
            display4 <= 4'h0;
            display5 <= 4'h0;
        end
        else begin
            display1 <= seg1;
            display2 <= seg2;
            display3 <= seg3;
            display4 <= seg4;
            display5 <= seg5;
        end
    end

endmodule