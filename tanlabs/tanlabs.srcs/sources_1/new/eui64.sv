
module eui64 (
    input wire [47:0] mac_addr,
    output reg [127:0] ipv6_addr
);
    // Convert MAC address to IPv6 address 
    assign ipv6_addr[7:0] = 8'hfe;
    assign ipv6_addr[15:8] = 8'h80;
    assign ipv6_addr[95:88] = 8'hff;
    assign ipv6_addr[103:96] = 8'hfe;
    
    assign ipv6_addr[71:64] = mac_addr[7:0] ^ (8'b00000010);
    assign ipv6_addr[79:72] = mac_addr[15:8];
    assign ipv6_addr[87:80] = mac_addr[23:16];

    assign ipv6_addr[111:104] = mac_addr[31:24];
    assign ipv6_addr[119:112] = mac_addr[39:32];
    assign ipv6_addr[127:120] = mac_addr[47:40];

    assign ipv6_addr[63:16] = 0;
endmodule