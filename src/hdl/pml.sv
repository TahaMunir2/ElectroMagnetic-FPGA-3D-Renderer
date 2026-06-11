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
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            1: begin
                ca = 16'sd8174;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            2: begin
                ca = 16'sd8045;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            3: begin
                ca = 16'sd7695;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            4: begin
                ca = 16'sd7014;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            5: begin
                ca = 16'sd5892;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
            default: begin
                ca = 16'sd8192;
                cb_e = -16'sd717;
                cb_bz = -16'sd717;
            end
        endcase
    end

endmodule
