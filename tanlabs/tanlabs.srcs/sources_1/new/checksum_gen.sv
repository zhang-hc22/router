`include "frame_datapath.svh"
module checksum_gen (
    input wire clk,
    input wire rst,
    input wire start,
    output reg finished,

    input ether_hdr in,
    output reg [15:0] sum
); 
    logic computing;        // ���ڼ���
    logic [3:0] counter; 
    logic [16:0] sum1, sum2, sum3, sum4, sum5;

    always_ff @( posedge clk ) begin : handle_signal
        if (rst) begin
            counter <= 4'h0;
            finished <= 1'b0;
            computing <= 1'b0;
        end else begin
            if (start) begin
                computing <= 1;
            end
            if (computing) begin
                if (counter <= 11) begin
                    counter <= counter + 1;
                end
                else if (counter == 12) begin
                    computing <= 0;
                    finished <= 1;
                end 
            end else begin
                finished <= 0;
                counter <= 4'h0;
            end
        end
    end

    always_ff @( posedge clk ) begin : handle_checksum
        if (rst) begin
            sum1 <= 17'h0;
            sum2 <= 17'h0;
            sum3 <= 17'h0;
            sum4 <= 17'h0;
            sum5 <= 17'h0;
            sum <= 0;
        end else begin
            if (start) begin
                sum1 <= 17'h0;
                sum2 <= 17'h0;
                sum3 <= 17'h0;
                sum4 <= 17'h0;
                sum5 <= in.ip6.next_hdr + IP6_HEADER_LENGTH_BIG_ENDIAN;
                sum <= 0;
            end 
            else if (computing) begin
                if (counter < 8) begin
                    sum1 <= sum1 + {in.ip6.src[(counter<<3) +: 8], in.ip6.src[(counter<<3) + 8 +: 8]} - (16'h0 - sum1[16]);
                    sum2 <= sum2 + {in.ip6.dst[(counter<<3) +: 8], in.ip6.dst[(counter<<3) + 8 +: 8]} - (16'h0 - sum2[16]);
                    sum3 <= sum3 + {in.ip6.p[(counter<<3) +: 8], in.ip6.p[(counter<<3) + 8 +: 8]} - (16'h0 - sum3[16]);
                    sum4 <= sum4 + {in.ip6.p[((counter+8)<<3) +: 8], in.ip6.p[((counter+8)<<3) + 8 +: 8]} - (16'h0 - sum4[16]);
                end
                else if (counter == 8) begin
                    sum1 <= sum1 - (16'h0 - sum1[16]) + sum2 - (16'h0 - sum2[16]);
                    sum3 <= sum3 - (16'h0 - sum3[16]) + sum4 - (16'h0 - sum4[16]);
                end
                else if (counter == 9) begin
                    sum1 <= sum1 - (16'h0 - sum1[16]) + sum3 - (16'h0 - sum3[16]);
                end
                else if (counter == 10) begin
                    sum1 <= sum1 - (16'h0 - sum1[16]) + sum5 - (16'h0 - sum5[16]);
                end
                else if (counter == 11) begin
                    sum <= sum1 - (16'h0 - sum1[16]);
                    // sum <= 16'h0;
                end
            end
        end
    end 

endmodule