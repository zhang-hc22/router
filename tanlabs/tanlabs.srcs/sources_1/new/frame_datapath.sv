`timescale 1ns / 1ps

// Example Frame Data Path.

`include "frame_datapath.svh"

module frame_datapath
#(
    parameter DATA_WIDTH = 64,
    parameter ID_WIDTH = 3
)
(
    input wire eth_clk,
    input wire reset,

    input wire [47:0] mac_addr [3:0],

    input wire [DATA_WIDTH - 1:0] s_data,
    input wire [DATA_WIDTH / 8 - 1:0] s_keep,
    input wire s_last,
    input wire [DATA_WIDTH / 8 - 1:0] s_user,
    input wire [ID_WIDTH - 1:0] s_id,
    input wire s_valid,
    output wire s_ready,

    output wire [DATA_WIDTH - 1:0] m_data,
    output wire [DATA_WIDTH / 8 - 1:0] m_keep,
    output wire m_last,
    output wire [DATA_WIDTH / 8 - 1:0] m_user,
    output wire [ID_WIDTH - 1:0] m_dest,
    output wire m_valid,
    input wire m_ready,
    input wire [127:0] local_link_addr [3:0]
);

    frame_beat in8, in;
    wire in_ready;

    always @ (*)
    begin
        in8.meta = 0;
        in8.valid = s_valid;
        in8.data = s_data;
        in8.keep = s_keep;
        in8.last = s_last;
        in8.meta.id = s_id;
        in8.user = s_user;
    end

    // Track frames and figure out when it is the first beat.
    always @ (posedge eth_clk or posedge reset)
    begin
        if (reset)
        begin
            in8.is_first <= 1'b1;
        end
        else
        begin
            if (in8.valid && s_ready)
            begin
                in8.is_first <= in8.last;
            end
        end
    end

    // README: Here, we use a width upsizer to change the width to 56 bytes
    // (MAC 14 + IPv6 40 + round up 2) to ensure that L2 (MAC) and L3 (IPv6) headers appear
    // in one beat (the first beat) facilitating our processing.
    // You can remove this.
    frame_beat_width_converter #(DATA_WIDTH, DATAM_WIDTH) frame_beat_upsizer( // 这里把第二个width改为新定义的56Bytes
        .clk(eth_clk),
        .rst(reset),

        .in(in8),
        .in_ready(s_ready),
        .out(in),
        .out_ready(in_ready)
    );

    // README: Your code here.
    // See the guide to figure out what you need to do with frames.

    frame_beat mid8;   // 中间变量，用于将 56Bytes 转换为 64bits = 8Bytes
    frame_beat mid88;  // 中间变量，用于将 8Bytes  转换为 88Bytes
    wire mid8_ready;
    wire mid88_ready;
    wire out_ready;

    // 仿照in_ready的定义
    assign mid88_ready = out_ready || !mid88.valid;

    frame_beat_width_converter #(DATAM_WIDTH, DATA_WIDTH) frame_beat_downsizer_56_to_8( // 这里把 56Bytes 转换为 8Bytes
        .clk(eth_clk),
        .rst(reset),

        .in(in),
        .in_ready(in_ready),
        .out(mid8),
        .out_ready(mid8_ready)
    );

    frame_beat_width_converter #(DATA_WIDTH, DATAW_WIDTH) frame_beat_upsizer_8_to_88( // 这里把 8Bytes 转换为 88Bytes
        .clk(eth_clk),
        .rst(reset),

        .in(mid8),
        .in_ready(mid8_ready),
        .out(mid88),
        .out_ready(mid88_ready)
    );

    // 判断以太网帧下的网络层类型是不是 IPv6 (0x86DD)，若不是触发丢包
    wire wrong_ether_type;
    assign wrong_ether_type = mid88.data.ethertype != ETHERTYPE_IP6;

    // 判断 IPv6 报文中的类型是不是 ICMPv6 (0x3A)，若是把 ND_handle 拉高，用于触发 ND 协议的处理
    wire ND_handle;
    assign ND_handle = mid88.data.ip6.next_hdr == 8'h3a;

    frame_beat out;
    wire s_flag;
    wire ND_valid;
    wire finish_nd_handle;
    wire [47:0] mac_addr_searched;
    wire [2:0] state_searched;
    wire exist;
    wire ack_nd_cache;
    wire checksum_correct;
    wire ack_checksum;
    wire drop;
    wire [127:0] ip6_addr_for_cache;
    wire [47:0] mac_addr_for_cache;
    STATE state_for_cache;
    OPERATION op_for_cache;
    wire is_router_flag_for_cache;
    wire stb_nd_cache;
    wire stb_checksum;

    NDP_handle NDP_handler(
        .clk(eth_clk),
        .rst(reset),
        .in(mid88), 
        .handle(ND_handle),
        .mac_addr_searched(mac_addr_searched),
        .state_searched(state_searched),
        .exist(exist),
        .ack_nd_cache(ack_nd_cache),
        .checksum_correct(checksum_correct),
        .ack_checksum(ack_checksum),
        .local_link_addr(local_link_addr),
        .wrong_ether_type(wrong_ether_type),
        .s_flag(s_flag),
        .finish_nd_handle(finish_nd_handle),
        .drop(drop),
        .ip6_addr(ip6_addr_for_cache),
        .mac_addr(mac_addr_for_cache),
        .state(state_for_cache),
        .op(op_for_cache),
        .is_router_flag(is_router_flag_for_cache),
        .stb_nd_cache(stb_nd_cache),
        .stb_checksum(stb_checksum)
    );

    wire [15:0] sum;
    assign checksum_correct = sum == 0;
    checksum_gen ns_checksum(
        .clk(eth_clk),
        .rst(reset),
        .start(stb_checksum),
        .finished(ack_checksum),
        .in(mid88.data),
        .sum(sum)
    );

    neighbour_cache neighbour_cache (
        .clk(eth_clk),
        .rst(reset),
        .ipv6(ip6_addr_for_cache),
        .mac(mac_addr_for_cache),
        .state(state_for_cache),
        .is_router_flag(is_router_flag_for_cache),
        .op(op_for_cache),
        .mac_out(mac_addr_searched),
        .state_out(state_searched),
        .exist(exist),
        .stb(stb_nd_cache),
        .ack(ack_nd_cache)
    );

    // always @ (*)
    // begin
    //     out = mid88;
    //     // out.meta.dest = 0;  // All frames are forwarded to interface 0!
    //     // if (`should_handle(in)) begin
    //     //     out.data.src = in.data.dst;
    //     //     out.data.dst = in.data.src;
    //     // end
    //     // out.meta.dest = in.meta.id;
    // end

    logic sna_finished;          // SNA 发送完毕

    sna 
    #(
        .DATA_WIDTH(DATAW_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    )
    _sna (
        .clk(eth_clk),
        .rst(reset),
        .start(mid88.valid),
        .drop(drop),
        .finished(sna_finished),

        .in(mid88),
        .mac_addr(mac_addr),

        .out_data(out.data),
        .out_keep(out.keep),
        .out_last(out.last),
        .out_user(out.user),
        .out_meta(out.meta),
        .out_is_first(out.is_first)
    );

    reg [3:0] valid_cnt;
    always_ff @(posedge eth_clk) begin
        if (reset) begin
            valid_cnt <= 0;
            out.valid <= 0;
        end else begin
            if (finish_nd_handle && s_flag && !valid_cnt) begin   // TODO: 目前来看 nd_handle 比 sna_finished 更晚到来
                valid_cnt <= 1;
            end else begin
                if (valid_cnt > 0 && valid_cnt <= 12) begin
                    valid_cnt <= valid_cnt + 1;
                    out.valid <= 1;
                end else begin
                    out.valid <= 0;
                    if (!finish_nd_handle) begin
                        valid_cnt <= 0;
                    end
                end
            end
        end
    end


    reg out_is_first;
    always @ (posedge eth_clk or posedge reset)
    begin
        if (reset)
        begin
            out_is_first <= 1'b1;
        end
        else
        begin
            if (out.valid && out_ready)
            begin
                out_is_first <= out.last;
            end
        end
    end

    reg [ID_WIDTH - 1:0] dest;
    reg drop_by_prev;  // Dropped by the previous frame?
    always @ (posedge eth_clk or posedge reset)
    begin
        if (reset)
        begin
            dest <= 0;
            drop_by_prev <= 1'b0;
        end
        else
        begin
            if (out_is_first && out.valid && out_ready)
            begin
                dest <= out.meta.dest;
                drop_by_prev <= out.meta.drop_next;
            end
        end
    end

    // Rewrite dest.
    wire [ID_WIDTH - 1:0] dest_current = out_is_first ? out.meta.dest : dest;

    frame_beat filtered;
    wire filtered_ready;

    frame_filter
    #(
        .DATA_WIDTH(DATAW_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    )
    frame_filter_i(
        .eth_clk(eth_clk),
        .reset(reset),

        .s_data(out.data),
        .s_keep(out.keep),
        .s_last(out.last),
        .s_user(out.user),
        .s_id(dest_current),
        .s_valid(out.valid),
        .s_ready(out_ready),

        .drop(out.meta.drop || drop_by_prev),

        .m_data(filtered.data),
        .m_keep(filtered.keep),
        .m_last(filtered.last),
        .m_user(filtered.user),
        .m_id(filtered.meta.dest),
        .m_valid(filtered.valid),
        .m_ready(filtered_ready)
    );

    // README: Change the width back. You can remove this.
    frame_beat out8;
    frame_beat_width_converter #(DATAW_WIDTH, DATA_WIDTH) frame_beat_downsizer(
        .clk(eth_clk),
        .rst(reset),

        .in(filtered),
        .in_ready(filtered_ready),
        .out(out8),
        .out_ready(m_ready)
    );

    assign m_valid = out8.valid;
    assign m_data = out8.data;
    assign m_keep = out8.keep;
    assign m_last = out8.last;
    assign m_dest = out8.meta.dest;
    assign m_user = out8.user;
endmodule
