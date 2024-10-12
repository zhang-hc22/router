`include "frame_datapath.svh"

module neighbour_cache(
    input wire clk,
    input wire rst,


    input wire [127:0] ipv6,
    input wire [47:0] mac,
    input wire [2:0] state,
    input wire is_router_flag,
    input OPERATION op,
    
    output reg [47:0] mac_out,
    output reg [2:0] state_out,
    output reg exist,

    input wire stb,
    output reg ack
);

neighbour_cache_entry entry[20];
reg found[20];
reg [47:0] mac_temp[20];
reg [2:0] state_temp[20];

always_comb begin
    for(int i = 0; i < 20; i++) begin
        found[i] = (entry[i].IPV6_ADDR == ipv6);
        if(found[i]) begin
            mac_temp[i] = entry[i].MAC_ADDR;
            state_temp[i] = entry[i].STATE;
        end else begin
            mac_temp[i] = 48'b0;
            state_temp[i] = 3'b0;
        end
    end
end

assign exist=found[0] | found[1] | found[2] | found[3] | found[4] | found[5] | found[6] | found[7] | found[8] | found[9] | found[10] | found[11] | found[12] | found[13] | found[14] | found[15] | found[16] | found[17] | found[18] | found[19];
assign mac_out=mac_temp[0] | mac_temp[1] | mac_temp[2] | mac_temp[3] | mac_temp[4] | mac_temp[5] | mac_temp[6] | mac_temp[7] | mac_temp[8] | mac_temp[9] | mac_temp[10] | mac_temp[11] | mac_temp[12] | mac_temp[13] | mac_temp[14] | mac_temp[15] | mac_temp[16] | mac_temp[17] | mac_temp[18] | mac_temp[19];
assign state_out=state_temp[0] | state_temp[1] | state_temp[2] | state_temp[3] | state_temp[4] | state_temp[5] | state_temp[6] | state_temp[7] | state_temp[8] | state_temp[9] | state_temp[10] | state_temp[11] | state_temp[12] | state_temp[13] | state_temp[14] | state_temp[15] | state_temp[16] | state_temp[17] | state_temp[18] | state_temp[19];


always @(posedge clk) begin
    if(rst) begin
        ack <= 0;
    end else begin
        if(stb) begin
            if(ack)begin
                ack <= 1;
            end else begin
                case(op)
                    UPDATE:
                    begin
                        for(int i = 0; i < 20; i++) begin
                            if(entry[i].IPV6_ADDR == ipv6) begin
                                entry[i].MAC_ADDR <= mac;
                                entry[i].STATE <= state;
                                break;
                            end
                        end
                        ack <= 1;
                    end
                    INSERT:
                    begin
                        for(int i = 0; i < 20; i++) begin
                            if(entry[i].IPV6_ADDR == 128'b0) begin
                                entry[i].IPV6_ADDR <= ipv6;
                                entry[i].MAC_ADDR <= mac;
                                entry[i].STATE <= state;
                                break;
                            end
                        end
                        ack <= 1;
                    end
                    QUERY:
                    begin
                        ack <= 1;
                    end
                    DELETE:
                    begin
                        ack <= 1;
                    end
                endcase
            end
        end else begin
            ack <= 0;
        end
    end
end 
endmodule
