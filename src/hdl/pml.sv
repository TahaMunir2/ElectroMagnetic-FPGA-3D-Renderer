module pml #(
    parameter DATA_WIDTH = 16,
    parameter CELL_WIDTH = 6,
    parameter PML_SIZE   = 6
)(
    input  logic signed [CELL_WIDTH-1:0] d,
    output logic signed [DATA_WIDTH-1:0] ca,
    output logic signed [DATA_WIDTH-1:0] cb_bz,
    output logic signed [DATA_WIDTH-1:0] cb_e
);

    always_comb begin
        case (d)
            0: begin
                ca = 16'sd8192;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            1: begin
                ca = 16'sd8188;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            2: begin
                ca = 16'sd8180;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            3: begin
                ca = 16'sd8168;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            4: begin
                ca = 16'sd8152;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            5: begin
                ca = 16'sd8135;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
            default: begin
                ca = 16'sd8192;
                cb_e = -16'sd25;
                cb_bz = -16'sd25;
            end
        endcase
    end

endmodule
