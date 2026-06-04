`timescale 1ns / 1ps

module mock_i2c_slave #(
    parameter SLAVE_ADDR = 7'h3C,
    parameter READ_DATA  = 8'hBB // Data to send when read by master
)(
    inout wire sda,
    input wire scl
);

    reg [7:0] shift_reg;
    reg [3:0] bit_count;
    reg sda_out;
    reg sda_dir; // 1 = output, 0 = input
    reg is_addressed;
    reg is_read;
    
    assign sda = (sda_dir == 1'b1) ? sda_out : 1'bz;

    // Detect START and STOP conditions
    reg start_flag, stop_flag;
    
    always @(negedge sda) begin
        if (scl == 1'b1) start_flag <= 1; // START
        else start_flag <= 0;
    end
    
    always @(posedge sda) begin
        if (scl == 1'b1) stop_flag <= 1; // STOP
        else stop_flag <= 0;
    end
    
    // State machine based on SCL
    always @(negedge scl or posedge start_flag or posedge stop_flag) begin
        if (start_flag) begin
            bit_count <= 0;
            sda_dir <= 0;
            is_addressed <= 0;
            start_flag <= 0;
        end else if (stop_flag) begin
            sda_dir <= 0;
            is_addressed <= 0;
            stop_flag <= 0;
        end else begin
            if (!is_addressed) begin
                if (bit_count < 7) begin
                    shift_reg[6 - bit_count] <= sda;
                    bit_count <= bit_count + 1;
                end else if (bit_count == 7) begin
                    is_read <= sda;
                    if (shift_reg[6:0] == SLAVE_ADDR) begin
                        is_addressed <= 1;
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                    end
                    bit_count <= bit_count + 1;
                end else if (bit_count == 8) begin
                    sda_dir <= 0;
                    bit_count <= 0;
                    if (is_read) shift_reg <= READ_DATA;
                end
            end else begin
                // Data phase
                if (is_read) begin
                    // Read phase (slave transmits)
                    if (bit_count < 8) begin
                        sda_dir <= 1;
                        sda_out <= shift_reg[7 - bit_count];
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 0; // Release for Master ACK
                        bit_count <= 0;
                        is_addressed <= 0; // End after 1 byte for simplicity
                    end
                end else begin
                    // Write phase (slave receives)
                    if (bit_count < 8) begin
                        sda_dir <= 0;
                        shift_reg[7 - bit_count] <= sda;
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 8) begin
                        sda_dir <= 1;
                        sda_out <= 0; // ACK
                        bit_count <= bit_count + 1;
                    end else if (bit_count == 9) begin
                        sda_dir <= 0;
                        bit_count <= 0;
                        is_addressed <= 0; // End after 1 byte
                    end
                end
            end
        end
    end

endmodule
