`timescale 1ns/1ps

module cordic_source_adapter (
    input  wire               clk,
    input  wire               rst,

    input  wire               sample_req,
    input  wire signed [15:0] phase_step_q313,
    input  wire signed [15:0] amplitude_q313,

    output reg  signed [15:0] source_q313,
    output reg                source_valid,
    output reg                busy,

    output reg  signed [15:0] s_axis_phase_tdata,
    output reg                s_axis_phase_tvalid,

    input  wire [31:0]        m_axis_dout_tdata,
    input  wire               m_axis_dout_tvalid
);

    localparam signed [17:0] PI_Q313     = 18'sd25736;
    localparam signed [17:0] NEG_PI_Q313 = -18'sd25736;
    localparam signed [17:0] TWO_PI_Q313 = 18'sd51472;

    reg signed [15:0] phase_acc_q313;
    wire signed [17:0] phase_sum;
    reg signed [15:0] phase_wrapped;

    wire signed [15:0] sin_fix16_14;
    wire signed [15:0] sin_q313;
    wire signed [31:0] scaled_q313;

    assign phase_sum = {{2{phase_acc_q313[15]}}, phase_acc_q313}
                     + {{2{phase_step_q313[15]}}, phase_step_q313};

    always @* begin
        if (phase_sum > PI_Q313)
            phase_wrapped = phase_sum - TWO_PI_Q313;
        else if (phase_sum < NEG_PI_Q313)
            phase_wrapped = phase_sum + TWO_PI_Q313;
        else
            phase_wrapped = phase_sum[15:0];
    end

    assign sin_fix16_14 = m_axis_dout_tdata[31:16];
    assign sin_q313     = sin_fix16_14 >>> 1;
    assign scaled_q313  = ($signed(sin_q313) * $signed(amplitude_q313)) >>> 13;

    function signed [15:0] sat16;
        input signed [31:0] value;
        begin
            if (value > 32'sd32767)
                sat16 = 16'sh7fff;
            else if (value < -32'sd32768)
                sat16 = 16'sh8000;
            else
                sat16 = value[15:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            phase_acc_q313      <= 16'sd0;
            s_axis_phase_tdata  <= 16'sd0;
            s_axis_phase_tvalid <= 1'b0;
            source_q313         <= 16'sd0;
            source_valid        <= 1'b0;
            busy                <= 1'b0;
        end else begin
            s_axis_phase_tvalid <= 1'b0;
            source_valid        <= 1'b0;

            if (sample_req && !busy) begin
                phase_acc_q313      <= phase_wrapped;
                s_axis_phase_tdata  <= phase_wrapped;
                s_axis_phase_tvalid <= 1'b1;
                busy                <= 1'b1;
            end

            if (busy && m_axis_dout_tvalid) begin
                source_q313  <= sat16(scaled_q313);
                source_valid <= 1'b1;
                busy         <= 1'b0;
            end
        end
    end

endmodule

