`timescale 1ns / 1ps

// ============================================================
// i2c_slave.v - behavioral I2C slave for simulation
//
// Samples SDA on SCL rising edges. ACK and read data are driven only
// while SCL is low, so the model does not create false START/STOP edges.
// ============================================================
module i2c_slave #(
    parameter SLAVE_ADDR = 7'h3C,
    parameter READ_DATA  = 8'hBB
)(
    inout wire sda,
    input wire scl
);

    localparam ST_IDLE     = 3'd0;
    localparam ST_ADDR     = 3'd1;
    localparam ST_ADDR_ACK = 3'd2;
    localparam ST_WRITE    = 3'd3;
    localparam ST_DATA_ACK = 3'd4;
    localparam ST_READ     = 3'd5;
    localparam ST_READ_ACK = 3'd6;

    reg       sda_out = 1'b1;
    reg       sda_dir = 1'b0;
    reg [2:0] state = ST_IDLE;
    reg [3:0] bit_count = 4'd0;
    reg [7:0] shift_reg = 8'h00;
    reg       is_addressed = 1'b0;
    reg       is_read = 1'b0;
    reg       addr_match = 1'b0;
    reg [1:0] ack_phase = 2'd0;

    reg [7:0] start_count = 8'h00;
    reg [7:0] stop_count = 8'h00;
    reg [7:0] last_start_count = 8'h00;
    reg [7:0] last_stop_count = 8'h00;

    reg [7:0] addr_byte;
    reg [7:0] data_byte;

    assign sda = sda_dir ? sda_out : 1'bz;

    always @(negedge sda) begin
        if (scl === 1'b1)
            start_count <= start_count + 1'b1;
    end

    always @(posedge sda) begin
        if (scl === 1'b1)
            stop_count <= stop_count + 1'b1;
    end

    always @(posedge scl or negedge scl) begin
        if (scl === 1'b1) begin
            if (start_count != last_start_count) begin
                last_start_count = start_count;
                state = ST_ADDR;
                bit_count = 4'd0;
                shift_reg = 8'h00;
                is_addressed = 1'b0;
                is_read = 1'b0;
                addr_match = 1'b0;
                ack_phase = 2'd0;
                sda_dir = 1'b0;
            end

            case (state)
                ST_ADDR: begin
                    addr_byte = {shift_reg[6:0], sda};
                    shift_reg = addr_byte;

                    if (bit_count == 4'd7) begin
                        is_read = addr_byte[0];
                        addr_match = (addr_byte[7:1] == SLAVE_ADDR);
                        is_addressed = (addr_byte[7:1] == SLAVE_ADDR);
                        $display("[%0t ns] SLAVE 0x%02h: received addr byte=0x%02h addr=0x%02h rw=%b",
                                 $time, SLAVE_ADDR, addr_byte, addr_byte[7:1], addr_byte[0]);
                        if (addr_byte[7:1] == SLAVE_ADDR)
                            $display("[%0t ns] SLAVE 0x%02h: ADDRESS MATCH - sending ACK", $time, SLAVE_ADDR);
                        else
                            $display("[%0t ns] SLAVE 0x%02h: no match - NACK", $time, SLAVE_ADDR);
                        state = ST_ADDR_ACK;
                        bit_count = 4'd0;
                        ack_phase = 2'd0;
                    end else begin
                        bit_count = bit_count + 1'b1;
                    end
                end

                ST_ADDR_ACK: begin
                    if (ack_phase == 2'd1)
                        ack_phase = 2'd2;
                end

                ST_WRITE: begin
                    data_byte = {shift_reg[6:0], sda};
                    shift_reg = data_byte;

                    if (bit_count == 4'd7) begin
                        $display("[%0t ns] SLAVE 0x%02h: received data byte=0x%02h - sending ACK",
                                 $time, SLAVE_ADDR, data_byte);
                        state = ST_DATA_ACK;
                        bit_count = 4'd0;
                        ack_phase = 2'd0;
                    end else begin
                        bit_count = bit_count + 1'b1;
                    end
                end

                ST_DATA_ACK: begin
                    if (ack_phase == 2'd1)
                        ack_phase = 2'd2;
                end

                ST_READ_ACK: begin
                    state = ST_IDLE;
                    sda_dir = 1'b0;
                    is_addressed = 1'b0;
                    bit_count = 4'd0;
                end
            endcase
        end else begin
            if (stop_count != last_stop_count) begin
                last_stop_count = stop_count;
                state = ST_IDLE;
                bit_count = 4'd0;
                sda_dir = 1'b0;
                is_addressed = 1'b0;
                ack_phase = 2'd0;
            end else begin
                case (state)
                    ST_ADDR_ACK: begin
                        if (ack_phase == 2'd0) begin
                            if (addr_match) begin
                                sda_dir = 1'b1;
                                sda_out = 1'b0;
                            end else begin
                                sda_dir = 1'b0;
                            end
                            ack_phase = 2'd1;
                        end else if (ack_phase == 2'd2) begin
                            sda_dir = 1'b0;
                            ack_phase = 2'd0;
                            if (addr_match) begin
                                if (is_read) begin
                                    state = ST_READ;
                                    shift_reg = READ_DATA;
                                    bit_count = 4'd0;
                                    sda_dir = 1'b1;
                                    sda_out = READ_DATA[7];
                                end else begin
                                    state = ST_WRITE;
                                    shift_reg = 8'h00;
                                    bit_count = 4'd0;
                                end
                            end else begin
                                state = ST_IDLE;
                            end
                        end
                    end

                    ST_DATA_ACK: begin
                        if (ack_phase == 2'd0) begin
                            sda_dir = 1'b1;
                            sda_out = 1'b0;
                            ack_phase = 2'd1;
                        end else if (ack_phase == 2'd2) begin
                            sda_dir = 1'b0;
                            ack_phase = 2'd0;
                            state = ST_IDLE;
                            bit_count = 4'd0;
                            is_addressed = 1'b0;
                        end
                    end

                    ST_READ: begin
                        if (bit_count == 4'd7) begin
                            sda_dir = 1'b0;
                            state = ST_READ_ACK;
                            bit_count = 4'd0;
                        end else begin
                            sda_dir = 1'b1;
                            sda_out = shift_reg[6 - bit_count];
                            bit_count = bit_count + 1'b1;
                        end
                    end
                endcase
            end
        end
    end

endmodule

