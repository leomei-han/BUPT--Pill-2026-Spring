// ============================================================
//  sw_checker  —  BCD 输入范围检查
//  装入量范围: 01 ~ 50 ;  瓶数范围: 01 ~ 18
// ============================================================
module sw_checker(
    input  [7:0] input_data,
    input        setting_switch,
    output reg   input_valid
);

    wire [3:0] hi = input_data[7:4];
    wire [3:0] lo = input_data[3:0];

    wire hi_legal = (hi <= 4'd9);
    wire lo_legal = (lo <= 4'd9);

    always @(*) begin
        input_valid = 1'b0;

        if (hi_legal & lo_legal) begin
            if (~setting_switch) begin
                // 每瓶装入量: 00-50
                case (hi)
                    4'd0, 4'd1, 4'd2, 4'd3, 4'd4: input_valid = 1'b1;
                    4'd5: input_valid = (lo == 4'd0);
                    default: input_valid = 1'b0;
                endcase
            end
            else begin
                // 目标瓶数: 00-18
                case (hi)
                    4'd0: input_valid = 1'b1;
                    4'd1: input_valid = (lo <= 4'd8);
                    default: input_valid = 1'b0;
                endcase
            end
        end
    end

endmodule