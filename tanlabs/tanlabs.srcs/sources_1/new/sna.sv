`include "frame_datapath.svh"
module sna #(
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH = 3
)
(
    input wire clk,
    input wire rst,
    input wire start,
    input wire drop,
    output reg finished,

    input frame_beat in,
    input reg [47:0] mac_addr [3:0],

    output ether_hdr out_data,
    output reg [DATA_WIDTH / 8 - 1:0] out_keep,
    output reg out_last,
    output reg [DATA_WIDTH / 8 - 1:0] out_user,
    output frame_meta out_meta,
    output reg out_is_first
);
    ether_hdr out_data_reg;
    nd_packet in_nd;
    nd_packet out_nd;  // solicited NA packet
    wire out_nd_ready;

    assign in_nd.ns = in.data.ip6.p;

    assign out_nd.na.icmpv6_type = 8'd136;
    assign out_nd.na.code = 8'd0;
    assign out_nd.na.reserved1 = 0;
    assign out_nd.na.reserved2 = 0;
    assign out_nd.na.checksum = 16'd0;

    // 1. NA 部分的 Target Address 字段直接从 NS 中复制过来。
    assign out_nd.na.target_address = in_nd.ns.target_address;

    // 2. Target Link-Layer Address 可选项的设置：
    // a. 若 NS 的 IP 目标地址不是一个组播地址，则目标链路层地址这一可选项可以被忽略；
    // Question：如何判断一个 IP 目标地址是否是一个组播地址？
    always_comb begin
        if (in.data.ip6.dst[7:0] != 8'hff) begin
            out_nd.na.options.nd_type = 8'd2;
            out_nd.na.options.length = 8'd1;
            out_nd.na.options.ethernet_addr = mac_addr[in.meta.id];  
        end 
        // b. 若 NS 的 IP 目标地址是一个组播地址，则 NA 报文必须包含目标链路层地址。
        else begin
            out_nd.na.options.nd_type = 8'd2;
            out_nd.na.options.length = 8'd1;
            out_nd.na.options.ethernet_addr = mac_addr[in.meta.id];  
        end
    end
    
    // 3. 若该节点是路由器，则将 NA 报文的 Router flag 设置为 1；否则设置为 0。
    assign out_nd.na.r_flag = 1'b1;

    // 4. 若 Target Address 是一个任播或该节点正在提供代理服务的单播地址，
    // 或者 NA 报文未包含目标链路层地址，则 Override flag 应该被设置为 0；
    // 否则应该设置为 1。
    assign out_nd.na.o_flag = 1'b1;

    logic [15:0] checksum;
    // 5. 若 NS 的源地址是一个未指定地址，则该节点必须将 Solicited flag 
    // 设置为 0 并以组播方式将邻居通告发送到所有节点组播地址；
    always_comb begin
        out_data_reg = in.data;
        if (in.data.ip6.src == 128'h0) begin
            out_nd.na.s_flag = 1'b0;        
            out_data_reg.ip6.dst = MULTICAST_TO_ALL;
        end
        // 否则，该节点必须将 Solicited flag 设置为 1 并以单播方式将邻居通告发送到 NS 源地址。
        else begin
            out_nd.na.s_flag = 1'b1;
            out_data_reg.ip6.dst = in.data.ip6.src;
        end

        out_data_reg.ip6.p = out_nd.na;
        out_data_reg.ip6.src = in_nd.ns.target_address;
        out_data_reg.src = mac_addr[in.meta.id];
        out_data_reg.dst = in.data.src;
    end

    always_comb begin
        out_meta = in.meta;
        out_meta.dest = in.meta.id;
        out_meta.drop = drop;
    end

    always_comb begin
        out_data = out_data_reg;
        out_data.ip6.p[31:16] = ~{checksum[7:0], checksum[15:8]};
    end
    
    assign out_keep = in.keep;
    assign out_last = in.last;
    assign out_user = in.user;
    assign out_is_first = in.is_first;

    checksum_gen _checksum_gen (
        .clk(clk),
        .rst(rst),
        .start(start),
        .finished(finished),

        .in(out_data_reg),
        .sum(checksum)
    );
endmodule