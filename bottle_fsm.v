// ============================================================
//  bottle_fsm  —  装瓶流程状态机
//  职责: 4-状态 FSM、BCD 计数、蜂鸣器驱动
// ============================================================
module bottle_fsm(
    input         clk,
    input         reset,
    input         mode_switch,
    input         qd_pressed,
    input         pill_pulse,
    input  [7:0]  pills_per_bottle,
    input  [7:0]  target_bottles,
    output reg [1:0]  work_state,
    output [11:0] total_pills_bcd,
    output [7:0]  current_pills_bcd,
    output [7:0]  bottle_count_bcd,
    output        buzzer
);

    // ---- 状态编码 ----
    localparam S_CFG  = 2'b00;   // 参数配置
    localparam S_RUN  = 2'b01;   // 正常运行
    localparam S_HALT = 2'b10;   // 目标达成提醒
    localparam S_WARN = 2'b11;   // 持续警报

    // ---- 计数寄存器 (BCD 编码) ----
    reg [11:0] acc_total;        // 药片累计 000-999
    reg [7:0]  acc_cur;          // 本瓶药片 00-99
    reg [7:0]  acc_btl;          // 已完成瓶 00-99

    // ---- 输出连线 (完成/警报状态时第4-5位切换至瓶数) ----
    assign total_pills_bcd   = acc_total;
    assign current_pills_bcd = (work_state == S_HALT || work_state == S_WARN)
                                ? acc_btl : acc_cur;
    assign bottle_count_bcd  = acc_btl;

    // ---- 蜂鸣器: 目标达成 或 警报态均拉高 ----
    assign buzzer = (work_state == S_HALT) | (work_state == S_WARN);

    // ---- 预判逻辑 ----
    //  下一颗药落入后本瓶是否恰好装满
    wire bottle_about_full = (acc_cur == (pills_per_bottle - 8'h01))
                             && (pills_per_bottle != 8'h00);
    //  下一瓶完成后是否恰好达到目标
    wire goal_about_done   = (acc_btl == (target_bottles - 8'h01))
                             && (target_bottles != 8'h00);

    // ===========================================================
    //  BCD +1 辅助函数 (12-bit / 8-bit)
    // ===========================================================
    function [11:0] inc12;
        input [11:0] v;
        reg [3:0] d0, d1, d2;
        begin
            d0 = v[3:0];  d1 = v[7:4];  d2 = v[11:8];
            if (d0 < 4'd9)        begin d0 = d0 + 1'b1; end
            else begin
                d0 = 4'd0;
                if (d1 < 4'd9)    begin d1 = d1 + 1'b1; end
                else begin
                    d1 = 4'd0;
                    d2 = (d2 < 4'd9) ? d2 + 1'b1 : 4'd0;
                end
            end
            inc12 = {d2, d1, d0};
        end
    endfunction

    function [7:0] inc8;
        input [7:0] v;
        reg [3:0] lo, hi;
        begin
            lo = v[3:0];  hi = v[7:4];
            if (lo < 4'd9) begin lo = lo + 1'b1; end
            else begin
                lo = 4'd0;
                hi = (hi < 4'd9) ? hi + 1'b1 : 4'd0;
            end
            inc8 = {hi, lo};
        end
    endfunction

    // ===========================================================
    //  主控 FSM
    // ===========================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            work_state <= S_CFG;
            acc_total  <= 12'h000;
            acc_cur    <= 8'h00;
            acc_btl    <= 8'h00;
        end
        else begin
            case (work_state)
                // ---- 配置态: 清零并等待启动 ----
                S_CFG: begin
                    acc_total <= 12'h000;
                    acc_cur   <= 8'h00;
                    acc_btl   <= 8'h00;
                    if (qd_pressed & mode_switch)
                        work_state <= S_RUN;
                end

                // ---- 运行态: 逐颗计数 ----
                S_RUN: begin
                    if (pill_pulse) begin
                        acc_total <= inc12(acc_total);
                        acc_cur   <= inc8(acc_cur);

                        if (bottle_about_full) begin
                            acc_cur <= 8'h00;
                            acc_btl <= inc8(acc_btl);
                            if (goal_about_done)
                                work_state <= S_HALT;
                        end
                    end
                end

                // ---- 达标提醒: 等待确认 ----
                S_HALT: begin
                    if (qd_pressed)
                        work_state <= S_WARN;
                end

                // ---- 持续警报: 仍可继续计数 ----
                S_WARN: begin
                    if (pill_pulse) begin
                        acc_total <= inc12(acc_total);
                        acc_cur   <= inc8(acc_cur);
                        if (bottle_about_full) begin
                            acc_cur <= 8'h00;
                            acc_btl <= inc8(acc_btl);
                        end
                    end
                end

                default: work_state <= S_CFG;
            endcase
        end
    end

endmodule