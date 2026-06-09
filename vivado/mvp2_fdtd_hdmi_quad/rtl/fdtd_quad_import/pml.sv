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
                cb_bz = -16'sd2867; 
            end
            1: begin
                ca = 16'sd7862;
                cb_e = -16'sd703;
                cb_bz = -16'sd2809;
            end
            2: begin
                ca = 16'sd6949;
                cb_e = -16'sd663;
                cb_bz = -16'sd2649;
            end
            3: begin
                ca = 16'sd5637;
                cb_e = -16'sd605;
                cb_bz = -16'sd2420;
            end
            4: begin
                ca = 16'sd4141;
                cb_e = -16'sd540;
                cb_bz = -16'sd2158;
            end
            5: begin
                ca = 16'sd2635;
                cb_e = -16'sd474;
                cb_bz = -16'sd1895;
            end
            default: begin
                ca = 16'sd8192;
                cb_e = -16'sd717;
                cb_bz = -16'sd2867;
            end
        endcase
    end

endmodule
