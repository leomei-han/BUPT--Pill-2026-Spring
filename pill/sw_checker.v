// ============================================================
//  sw_checker  —  输入范围检查
//  装入量范围: 01 ~ 50（纯 BCD）
//  瓶数范围:   001 ~ 159（扩展十位编码: 十位二进制 0~15, 个位 BCD）
//
//  纯组合逻辑模块：没有任何寄存器，不消耗宏单元的触发器资源
//  仅占用少量乘积项（case 语句综合成简单的 AND-OR 逻辑）
// ============================================================
module sw_checker(
    input  [7:0] input_data,    // 拨码开关 SW8~SW1 的数据
    input        setting_switch, // SW9: 0=校验装入量范围, 1=校验瓶数范围
    output reg   input_valid    // 输出：1=数据合法, 0=数据非法
);

    wire [3:0] hi = input_data[7:4];    // 高 4 位（十位）
    wire [3:0] lo = input_data[3:0];    // 低 4 位（个位）

    wire hi_legal = (hi <= 4'd9);       // 十位是合法 BCD（仅装入量需要）
    wire lo_legal = (lo <= 4'd9);       // 个位是合法 BCD（两种参数都需要）
    wire lo_nonzero = (lo != 4'd0);
    wire hi_nonzero = (hi != 4'd0);

    always @(*) begin
        input_valid = 1'b0;             // 默认非法

        if (~setting_switch) begin
            // ---- 每瓶装入量: 01-50（两位都必须是合法 BCD）----
            if (hi_legal & lo_legal) begin
                case (hi)
                    4'd0: input_valid = lo_nonzero;             // 01-09
                    4'd1, 4'd2, 4'd3, 4'd4: input_valid = 1'b1;// 10-49（全部合法）
                    4'd5: input_valid = (lo == 4'd0);           // 仅 50 合法
                    default: input_valid = 1'b0;                // 51+ 拒绝
                endcase
            end
        end
        else begin
            // ---- 目标瓶数: 001-159（扩展十位编码）----
            // 十位允许二进制 0~15（A~F 表示 100~159），个位必须是合法 BCD
            // 只需排除两种情况：个位非法、数值为零 → 校验逻辑反而比 01-18 更省
            input_valid = lo_legal & (lo_nonzero | hi_nonzero);
        end
    end

endmodule
