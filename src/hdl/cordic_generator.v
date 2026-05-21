`timescale 1ns/1ps

/**
 * CORDIC Input Generator - Sine Wave Generator
 * 
 * Owner: Yi
 * 
 * Uses Xilinx CORDIC IP to generate sine/cosine waves
 * Outputs in Q3.13 fixed-point format for hard source excitation
 */

module cordic_generator #(
    parameter signed [15:0] AMPLITUDE_Q313 = 16'sd8192
)(
    // Clock and Reset
    input  wire clk,
    input  wire rst,
    
    // Input phase step. 16'h4000 is a quarter cycle, 16'h8000 is half.
    input  wire [15:0] phase_in,
    input  wire        phase_valid,
    
    // Output sine and cosine (Q3.13 fixed-point)
    output wire [15:0] sin_out,
    output wire [15:0] cos_out,
    output wire        out_valid
);

    reg [15:0] phase_acc;
    reg [15:0] phase_word;
    reg        phase_word_valid;

    wire [15:0] phase_next = phase_acc + phase_in;

    always @(posedge clk) begin
        if (rst) begin
            phase_acc <= 16'd0;
            phase_word <= 16'd0;
            phase_word_valid <= 1'b0;
        end else begin
            phase_word_valid <= phase_valid;

            if (phase_valid) begin
                phase_acc <= phase_next;
                phase_word <= phase_next;
            end
        end
    end

`ifdef VIVADO_CORDIC_IP
    wire [31:0] cordic_tdata;
    wire        cordic_tvalid;

    // Generate a Vivado CORDIC IP named "cordic_0" and configure it for:
    // - Function: Sin_and_Cos
    // - Phase input width: 16 bits
    // - Output width: 16-bit signed samples matching Q3.13 scale
    // - AXI4-Stream phase input and dout output
    //
    // If your generated IP has a different name or output packing, update only
    // this instantiation/mapping and keep the project-facing wrapper unchanged.
    cordic_0 cordic_ip (
        .aclk(clk),
        .s_axis_phase_tvalid(phase_word_valid),
        .s_axis_phase_tdata(phase_word),
        .m_axis_dout_tvalid(cordic_tvalid),
        .m_axis_dout_tdata(cordic_tdata)
    );

    assign cos_out = cordic_tdata[15:0];
    assign sin_out = cordic_tdata[31:16];
    assign out_valid = cordic_tvalid;
`else
    reg signed [15:0] sin_reg;
    reg signed [15:0] cos_reg;
    reg               valid_reg;

    function signed [15:0] real_to_q313;
        input real value;
        integer scaled;
        begin
            if (value >= 0.0) begin
                scaled = $rtoi(value * AMPLITUDE_Q313 + 0.5);
            end else begin
                scaled = $rtoi(value * AMPLITUDE_Q313 - 0.5);
            end

            if (scaled > 32767) begin
                real_to_q313 = 16'sh7fff;
            end else if (scaled < -32768) begin
                real_to_q313 = 16'sh8000;
            end else begin
                real_to_q313 = scaled[15:0];
            end
        end
    endfunction

    function signed [15:0] sin_q313;
        input [15:0] phase;
        real radians;
        begin
            radians = 6.28318530717958647692 * phase / 65536.0;
            sin_q313 = real_to_q313($sin(radians));
        end
    endfunction

    function signed [15:0] cos_q313;
        input [15:0] phase;
        real radians;
        begin
            radians = 6.28318530717958647692 * phase / 65536.0;
            cos_q313 = real_to_q313($cos(radians));
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            sin_reg <= 16'sd0;
            cos_reg <= AMPLITUDE_Q313;
            valid_reg <= 1'b0;
        end else begin
            valid_reg <= phase_word_valid;

            if (phase_word_valid) begin
                sin_reg <= sin_q313(phase_word);
                cos_reg <= cos_q313(phase_word);
            end
        end
    end

    assign sin_out = sin_reg;
    assign cos_out = cos_reg;
    assign out_valid = valid_reg;
`endif

endmodule
