// ============================================================
//  bottle_fsm  —  装瓶流程状态机
//  职责: 4-状态 FSM、BCD 计数、蜂鸣器驱动
// ============================================================
module bottle_fsm(
    input         clk,              // 10 kHz 主时钟
    input         reset,            // 同步复位（电平开关经顶层两级同步后送入）
    input         mode_switch,      // SW10: 1=运行模式, 0=配置模式
    input         qd_pressed,       // QD 按键消抖后的单周期脉冲
    input         pill_pulse,       // 1 Hz 药片节拍（经 pulse_sync 同步后的单周期脉冲）
    input  [7:0]  pills_per_bottle, // 每瓶药片目标数（BCD 编码，由顶层锁存）
    input  [7:0]  target_bottles,   // 目标瓶数（扩展十位编码: [7:4] 二进制十位, [3:0] BCD 个位）
    output reg [1:0]  work_state,   // 当前 FSM 状态，2 位编码
    output [11:0] total_pills_bcd,  // 药片累计（3 位 BCD，送显示模块）
    output [7:0]  current_pills_bcd,// 当前瓶内药片数（2 位 BCD）
    output [7:0]  bottle_count_bcd, // 已完成瓶数（扩展十位编码，000-159）
    output        bottle_full_hint, // 当前瓶即将满（提前一拍预判，送 LG1 显示）
    output        buzzer            // 蜂鸣器使能
);

    // ---- 状态编码 ----
    // 编码经过精心设计：高位 work_state[1] = 1 的状态（HALT/WARN）
    // 恰好是需要蜂鸣器响的两个状态，因此蜂鸣器可以直接取该位，零逻辑门开销
    localparam S_CFG  = 2'b00;   // 参数配置
    localparam S_RUN  = 2'b01;   // 正常运行
    localparam S_HALT = 2'b10;   // 目标达成提醒（间歇蜂鸣）
    localparam S_WARN = 2'b11;   // 持续警报（持续蜂鸣）

    // ---- 计数寄存器 (全链路 BCD/扩展编码，避免二进制↔BCD 转换器的乘积项开销) ----
    reg [11:0] acc_total;        // 药片累计 000-999（3 位 BCD）
    reg [7:0]  acc_cur;          // 本瓶药片 00-99 （2 位 BCD，实际 ≤ 装入量上限 50）
    reg [7:0]  acc_btl;          // 已完成瓶 000-159（扩展十位编码: 十位二进制 0-15, 个位 BCD）

    // ---- 输出连线：寄存器直连输出端口，无额外逻辑 ----
    assign total_pills_bcd   = acc_total;
    assign current_pills_bcd = acc_cur;
    assign bottle_count_bcd  = acc_btl;

    // ---- 蜂鸣器使能 ----
    // 直接取状态码最高位：S_HALT(10) 和 S_WARN(11) 高位均为 1
    // 不需要比较器或 OR 门，一根线直连，节省宏单元
    assign buzzer = work_state[1];

    // ===========================================================
    //  BCD +1 辅助函数
    //  关键优化：用 == 4'd9 等值检测判断是否需要进位
    //  等值检测在硬件上只需一个 4 输入与门（1 个乘积项）
    //  如果用取余 (% 10) 实现 BCD 进位，会展开成大量乘积项
    //  对 CPLD 的 PLA 结构来说，乘积项是最稀缺的资源
    // ===========================================================

    // 3 位 BCD 加一（000-999），用于药片累计
    function [11:0] inc12;
        input [11:0] v;
        reg [3:0] d0, d1, d2;
        begin
            d0 = v[3:0];  d1 = v[7:4];  d2 = v[11:8];
            if (d0 == 4'd9) begin       // 个位满 9 → 归零并向十位进位
                d0 = 4'd0;
                if (d1 == 4'd9) begin   // 十位也满 9 → 归零并向百位进位
                    d1 = 4'd0;
                    if (d2 == 4'd9)
                        d2 = 4'd0;      // 百位溢出归零（999→000）
                    else
                        d2 = d2 + 1'b1;
                end
                else begin
                    d1 = d1 + 1'b1;
                end
            end
            else begin
                d0 = d0 + 1'b1;         // 个位未满，直接加一
            end
            inc12 = {d2, d1, d0};
        end
    endfunction

    // 2 段计数加一：个位 BCD 0-9，十位二进制 0-15（4-bit 自然溢出回绕）
    // 用于瓶内药片数和已完成瓶数：
    //   acc_cur 的十位 ≤ 5（装入量上限 50），行为与纯 BCD 完全一致
    //   acc_btl 借助二进制十位把量程扩展到 159（扩展十位编码，159→000 回绕）
    // 相比原先的“十位满 9 归零”，这里少了一个 ==9 比较器，乘积项更省
    function [7:0] inc8;
        input [7:0] v;
        reg [3:0] lo, hi;
        begin
            lo = v[3:0];  hi = v[7:4];
            if (lo == 4'd9) begin       // 个位满 9 → 归零并进位
                lo = 4'd0;
                hi = hi + 1'b1;         // 十位 15 时 4-bit 自然溢出归零
            end
            else begin
                lo = lo + 1'b1;
            end
            inc8 = {hi, lo};
        end
    endfunction

    // 2 段计数减一，用于“目标值前一拍”预判。
    // 不能直接用 target - 8'h01，因为 8'h10 - 1 会得到非法编码 8'h0F。
    // 借位逻辑对纯 BCD 和扩展十位编码同样成立：
    //   dec8_bcd(8'h50)=8'h49（装入量），dec8_bcd(8'hA0)=8'h99（瓶数 100→99）
    function [7:0] dec8_bcd;
        input [7:0] v;
        reg [3:0] lo, hi;
        begin
            lo = v[3:0];  hi = v[7:4];
            if (lo == 4'd0) begin
                lo = 4'd9;
                hi = hi - 1'b1;
            end
            else begin
                lo = lo - 1'b1;
            end
            dec8_bcd = {hi, lo};
        end
    endfunction

    // ---- 提前一拍预判逻辑（组合逻辑，不占寄存器） ----
    // bottle_about_full: 当前药片数 == 目标数-1，意味着下一颗药片到来时该瓶将满
    // 这样在新药片到来的同一个时钟沿内，可以同时完成计数、清零、换瓶，实现零延迟换瓶
    wire bottle_about_full = (acc_cur == dec8_bcd(pills_per_bottle))
                             && (pills_per_bottle != 8'h00);
    // goal_about_done: 已完成瓶数 == 目标瓶数-1，意味着当前瓶装满后就达标
    wire goal_about_done   = (acc_btl == dec8_bcd(target_bottles))
                             && (target_bottles != 8'h00);
    // 送给 seg_output，当瓶即将满时 LG1 显示 "2" 作为预警提示
    assign bottle_full_hint = bottle_about_full;

    // ===========================================================
    //  主控 FSM（同步复位，全部逻辑在 10 kHz 时钟上升沿触发）
    // ===========================================================
    always @(posedge clk) begin
        if (reset) begin
            work_state <= S_CFG;        // 复位回到配置态（计数器在 S_CFG 分支中清零）
        end
        else begin
            case (work_state)

                // ---- 配置态：等待参数写入，QD+SW10 启动运行 ----
                S_CFG: begin
                    acc_total <= 12'h000;   // 配置态持续清零所有计数器
                    acc_cur   <= 8'h00;
                    acc_btl   <= 8'h00;
                    // 安全联锁：必须同时满足 QD 按下且模式开关=1 才能启动
                    if (qd_pressed & mode_switch)
                        work_state <= S_RUN;
                end

                // ---- 运行态与警报态合并（节省资源：共用一份计数逻辑） ----
                // S_RUN: 正常计数，达标后自动跳转 S_HALT
                // S_WARN: 持续警报但仍允许计数（处理传送带上在途药片）
                S_RUN, S_WARN: begin
                    if (pill_pulse) begin
                        acc_total <= inc12(acc_total);   // 总计数 +1
                        acc_cur   <= inc8(acc_cur);      // 当前瓶 +1（默认路径）

                        // 提前一拍预判命中：这颗药片加完后该瓶恰好满
                        // 同一个时钟沿内同时执行：清零当前瓶、已完成瓶+1、检查达标
                        // → 零额外延迟周期的换瓶
                        if (bottle_about_full) begin
                            acc_cur <= 8'h00;            // 覆盖上面的 +1，清零换瓶
                            acc_btl <= inc8(acc_btl);    // 已完成瓶数 +1
                            // 仅在运行态检查达标（警报态不再跳转）
                            if (work_state == S_RUN && goal_about_done)
                                work_state <= S_HALT;
                        end
                    end
                end

                // ---- 提醒态：目标达成，等待操作员 QD 确认 ----
                S_HALT: begin
                    if (qd_pressed)
                        work_state <= S_WARN;   // 确认后进入持续警报态
                end

                default: work_state <= S_CFG;   // 未知状态安全回退
            endcase
        end
    end

endmodule
