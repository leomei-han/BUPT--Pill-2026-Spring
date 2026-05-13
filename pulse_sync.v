// ============================================================
//  pulse_sync  —  1 Hz 边沿脉冲发生器
//  用 10 kHz 主时钟采样 1 Hz 慢时钟, 输出单周期脉冲
// ============================================================
module pulse_sync(
    input  clk_10kHz,
    input  clk_1Hz,
    input  reset,
    output pill_pulse
);

    // 三级移位寄存器同步 + 边沿检测
    reg [2:0] sr;

    always @(posedge clk_10kHz) begin
        if (reset)
            sr <= 3'b000;
        else
            sr <= {sr[1:0], clk_1Hz};
    end

    // 取中间两位做上升沿判断
    assign pill_pulse = (sr[2:1] == 2'b01);

endmodule
