`timescale 1ns / 1ps
`include "frame_datapath.svh"

module NDP_handle(
    input wire clk,
    input wire rst,
    input frame_beat in,
    input wire handle,                      // 输入指示是否应该触发 ND 处理
    input wire [47:0] mac_addr_searched,    // 上缓存表里查询到的 mac 地址
    input wire [2:0] state_searched,        // 上缓存表里查询到的 state
    input wire exist,                       // 上缓存表里查询的表项是否存在
    input wire ack_nd_cache,                // 上缓存表里查询是否结束
    input wire checksum_correct,            // 从 checksum 模块获得的检查结果
    input wire ack_checksum,                // checksum 模块是否计算完毕
    input wire [127:0] local_link_addr [3:0],  // 配置好的四个网口的链路本地地址
    input wire wrong_ether_type,            // 是否收到了错误的以太网帧类型
    output wire s_flag,                     // 用于指示是否收到了一个 NS 报文
    output reg drop,                        // 用于指示这个 ND 报文是否需要舍弃 drop = drop || !valid
    output reg finish_nd_handle,            // 用于指示 ND 报文处理是否结束
    output reg [127:0] ip6_addr,            // 输出给缓存表的 ipv6 地址
    output reg [47:0] mac_addr,             // 输出给缓存表的 mac 地址
    output STATE state,                     // 输出给缓存表的表项的 state
    output OPERATION op,                    // 输出给缓存表的操作码
    output reg is_router_flag,              // 输出给缓存表的 is_router_flag
    output reg stb_nd_cache,                // 输出给缓存表的请求使能
    output reg stb_checksum                 // 输出给检查 checksum 的模块
);

    // 缓存表项 state:
    // INCOMPLETE     000
    // REACHABLE      001
    // STALE          010
    // DELAY          011
    // PROBE          100

    wire NS_validation;                // NS 报文验证合法性指示
    wire NA_validation;                // NA 报文验证合法性指示
    wire IP_Hop_Limit;                 // IP Hop Limit 检测，是否为 255
    wire ICMP_checksum;                // ICMP 校验和是否正确
    wire ICMP_code;                    // ICMP_code 是否为 0
    wire ICMP_length;                  // ICMP 长度是否大于等于 24 且是 8 的倍数
    wire Target_Address_not_multicast; // Target Address 是否是组播地址
    wire IP_src_undefined;             // NS 报文源地址是否是未指定地址
    wire valid;                        // NS 报文是否合法
    
    nd_packet ndp;
    assign ndp = in.data.ip6.p;

    reg option;                // option 是否合规
    always_comb begin
        if (s_flag) begin
            if (in.data.ip6.src != 0) begin
                if (in.data.ip6.dst[7:0] != 8'hff) begin
                    option = 1;
                end else begin
                   if (ndp.ns.options.nd_type != 0) begin
                        option = 1;
                    end else begin
                        option = 0;
                    end 
                end
            end else begin
                if (ndp.ns.options.nd_type != 0) begin
                    option = 0;
                end else begin
                    option = 1;
                end
            end
        end
    end

    wire match;           // target_address 跟我方ip地址是否匹配，仅在 NS 报文情况下需要
    assign match = (ndp.ns.target_address == local_link_addr[in.meta.id]) || !s_flag;


    assign s_flag = ndp.ns.icmpv6_type == 8'd135;

    assign IP_Hop_Limit = in.data.ip6.hop_limit == 8'hff;  // 检测 hop limit 是不是 255
    assign ICMP_code = ndp.ns.code == 0;                      // 检查 code 是不是 0，取 nsp，nap 都可以
    assign ICMP_length = in.data.ip6.payload_len >= 16'd24 && in.data.ip6.payload_len[2:0] == 3'b000;
    assign Target_Address_not_multicast = ndp.ns.target_address[7:0] != 8'hff;  // 检查 target address 是否是组播地址
    assign IP_src_undefined = in.data.ip6.src == 128'd0;   // 检查 NS 报文源 IP 地址是否是未指定地址
    
    // TODO: 再写一个模块判断 checksum 是否正确
    assign ICMP_checksum = checksum_correct;

    // 判断这个报文是否合法
    assign valid = handle && IP_Hop_Limit && ICMP_checksum && ICMP_code && ICMP_length && Target_Address_not_multicast && !IP_src_undefined && option && match && !wrong_ether_type;

    typedef enum logic [2:0]{ 
        INIT,           // 初始状态，将结束handle设置为0
        CHECKSUM,       // 验证 checksum
        SEARCHC,         // 上表中查询是否有表项 search cache
        INSERTC,         // 向表中插入  insert cache
        UPDATEC,         // 更新表项    update cache
        FINISH          // 结束
    } state_t;
    state_t handle_state;

    // 保存查询结果，防止结果不再输入
    reg [2:0] state_searched_saved;
    reg [47:0] mac_addr_searched_saved;

    // 维持FINISH状态的计数器
    reg [3:0] finish_counter;

    always_ff @( posedge clk ) begin
        if (rst) begin
            handle_state <= INIT;
            finish_nd_handle <= 0;
            ip6_addr <= 0;
            mac_addr <= 0;
            state <= INCOMPLETE;
            op <= UPDATE;
            is_router_flag <= 0;
            stb_nd_cache <= 0;
            stb_checksum <= 0;
            drop <= 0;
            state_searched_saved <= 0;
            mac_addr_searched_saved <= 0;
            finish_counter <= 0;
        end else begin
            case (handle_state)
                INIT: begin
                    finish_nd_handle <= 0;
                    drop <= 0;
                    state_searched_saved <= 0;
                    mac_addr_searched_saved <= 0;
                    finish_counter <= 0;
                    handle_state <= CHECKSUM;
                end
                CHECKSUM: begin
                    if (!ack_checksum) begin
                        stb_checksum <= 1;
                    end else begin
                        stb_checksum <= 0;
                        if (valid) begin
                            handle_state <= SEARCHC;
                        end else begin
                            handle_state <= FINISH;
                        end
                    end
                end
                SEARCHC: begin
                    if (s_flag) begin   // NS 报文
                        if (!IP_src_undefined && ndp.ns.options.ethernet_addr != 0) begin
                            if (!ack_nd_cache) begin
                                stb_nd_cache <= 1;
                                ip6_addr <= in.data.ip6.src;
                                op <= QUERY;
                            end else begin
                                stb_nd_cache <= 0;
                                if (exist) begin
                                    mac_addr_searched_saved <= mac_addr_searched;
                                    state_searched_saved <= state_searched;
                                    if (mac_addr_searched != ndp.ns.options.ethernet_addr) begin
                                        handle_state <= UPDATEC;
                                    end else begin
                                        handle_state <= FINISH;
                                    end
                                end else begin
                                    handle_state <= INSERTC;
                                end
                            end
                        end else begin
                            handle_state <= FINISH;
                        end
                    end else begin    // NA 报文
                        if (!ack_nd_cache) begin
                            stb_nd_cache <= 1;
                            ip6_addr <= in.data.ip6.src;
                            op <= QUERY;
                        end else begin
                            stb_nd_cache <= 0;
                            if (exist) begin
                                if (state_searched == INCOMPLETE) begin
                                    if (ndp.na.options.ethernet_addr == 0) begin
                                        drop <= 1;
                                        handle_state <= FINISH;
                                    end else begin
                                        handle_state <= UPDATEC;
                                    end
                                end else begin
                                    handle_state <= UPDATEC;
                                end
                            end else begin
                                drop <= 1;
                                handle_state <= FINISH;
                            end
                        end
                    end
                end
                UPDATEC: begin
                    if (s_flag) begin
                        if (!ack_nd_cache) begin
                            stb_nd_cache <= 1;
                            ip6_addr <= in.data.ip6.src;
                            mac_addr <= ndp.ns.options.ethernet_addr;
                            op <= UPDATE;
                            state <= STALE;     // 设置为 STALE
                            is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                        end else begin
                            stb_nd_cache <= 0;
                            handle_state <= FINISH;
                        end
                    end else begin
                        if (state_searched_saved == INCOMPLETE) begin   // 如果表中是不完整状态
                            if (ndp.na.s_flag) begin
                                if (!ack_nd_cache) begin
                                    stb_nd_cache <= 1;
                                    ip6_addr <= in.data.ip6.src;
                                    mac_addr <= ndp.ns.options.ethernet_addr;
                                    op <= UPDATE;
                                    state <= REACHABLE;
                                    is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                                end else begin
                                    stb_nd_cache <= 0;
                                    handle_state <= FINISH;
                                end
                            end else begin
                                if (!ack_nd_cache) begin
                                    stb_nd_cache <= 1;
                                    ip6_addr <= in.data.ip6.src;
                                    mac_addr <= ndp.ns.options.ethernet_addr;
                                    op <= UPDATE;
                                    state <= STALE;
                                    is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                                end else begin
                                    stb_nd_cache <= 0;
                                    handle_state <= FINISH;
                                end
                            end
                        end else begin    // 表中不是不完整状态
                            if (ndp.na.o_flag) begin
                                if (mac_addr_searched_saved == ndp.na.options.ethernet_addr) begin
                                    handle_state <= FINISH;
                                end else begin
                                    if (state_searched_saved != REACHABLE) begin
                                        drop <= 1;
                                        handle_state <= FINISH;
                                    end else begin
                                        if (!ack_nd_cache) begin
                                            stb_nd_cache <= 1;
                                            ip6_addr <= in.data.ip6.src;
                                            mac_addr <= mac_addr_searched_saved;   // 不进行更新，只把状态设置为STALE
                                            op <= UPDATE;
                                            state <= STALE;
                                            is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                                        end else begin
                                            stb_nd_cache <= 0;
                                            handle_state <= FINISH;
                                        end
                                    end
                                end
                            end else begin
                                if (s_flag) begin
                                    if (!ack_nd_cache) begin
                                        stb_nd_cache <= 1;
                                        ip6_addr <= in.data.ip6.src;
                                        mac_addr <= ndp.ns.options.ethernet_addr;
                                        op <= UPDATE;
                                        state <= REACHABLE;
                                        is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                                    end else begin
                                        stb_nd_cache <= 0;
                                        handle_state <= FINISH;
                                    end
                                end else begin
                                    if (mac_addr_searched_saved != ndp.na.options.ethernet_addr) begin
                                        if (!ack_nd_cache) begin
                                            stb_nd_cache <= 1;
                                            ip6_addr <= in.data.ip6.src;
                                            mac_addr <= ndp.ns.options.ethernet_addr;
                                            op <= UPDATE;
                                            state <= STALE;
                                            is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                                        end else begin
                                            stb_nd_cache <= 0;
                                            handle_state <= FINISH;
                                        end
                                    end else begin
                                        handle_state <= FINISH;
                                    end
                                end
                            end
                        end
                    end
                end
                INSERTC: begin
                    if (s_flag) begin
                        if (!ack_nd_cache) begin
                            stb_nd_cache <= 1;
                            ip6_addr <= in.data.ip6.src;
                            mac_addr <= ndp.ns.options.ethernet_addr;
                            op <= INSERT;
                            state <= STALE;     // 设置为 STALE
                            is_router_flag <= 0; // TODO: 不知道这个怎么设，先都设成0
                        end else begin
                            stb_nd_cache <= 0;
                            handle_state <= FINISH;
                        end
                    end else begin
                        // 接受 NA 报文不会出现插入表项的情况
                        drop <= 1;
                        handle_state <= FINISH;
                    end
                end
                FINISH: begin
                    // TODO: 维持多少个周期在 FINISH 状态
                    // if (finish_counter == 4'd12) begin
                    //     handle_state <= INIT;
                    //     finish_counter <= 0;
                    //     finish_nd_handle <= 0;
                    // end else begin
                    //     if (finish_counter > 0) begin
                    //         finish_counter <= finish_counter + 1;
                    //     end else begin
                    //         finish_nd_handle <= 1;
                    //         drop <= drop || !valid;
                    //         finish_counter <= finish_counter + 1;
                    //     end
                    // end
                    if (in.valid) begin
                        handle_state <= INIT;
                    end else begin
                        finish_nd_handle <= 1;
                        drop <= drop || !valid;
                    end
                end
                default begin
                    handle_state <= INIT;
                end
            endcase
        end
    end

endmodule
