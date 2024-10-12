`ifndef _FRAME_DATAPATH_VH_
`define _FRAME_DATAPATH_VH_

// 'w' means wide.
localparam DATAW_WIDTH = 8 * 88;  // 定义一个frame_beat最大可容纳数据量   88Bytes
localparam DATAM_WIDTH = 8 * 56;  // 定义中间状态的frame_beat大小 56Bytes
localparam ID_WIDTH = 3;
localparam MULTICAST_TO_ALL = 128'h010000000000000000000000000002ff;
localparam IP6_HEADER_LENGTH_BIG_ENDIAN = 16'h2800;

// README: Your code here.

// 定义 option 格式
typedef struct packed
{
    logic [15:0] round_up;
    logic [47:0] ethernet_addr;
    logic [7:0] length;
    logic [7:0] nd_type;
} option;

// 定义 NS 报文格式
typedef struct packed
{
    option options;
    logic [127:0] target_address;
    logic [31:0] reserved;
    logic [15:0] checksum;
    logic [7:0] code;
    logic [7:0] icmpv6_type;
} ns_packet;

// 定义 NA 报文格式
typedef struct packed
{
    option options;
    logic [127:0] target_address;
    logic [23:0] reserved2;
    logic r_flag;
    logic s_flag;
    logic o_flag;
    logic [4:0] reserved1;
    logic [15:0] checksum;
    logic [7:0] code;
    logic [7:0] icmpv6_type;
} na_packet;

// 定义 union ND 报文
typedef union packed
{
    na_packet na;
    ns_packet ns;
} nd_packet;

typedef struct packed
{
    logic [(DATAW_WIDTH - 8 * 40 - 8 * 14) - 1:0] p;
    logic [127:0] dst;
    logic [127:0] src;
    logic [7:0] hop_limit;
    logic [7:0] next_hdr;
    logic [15:0] payload_len;
    logic [23:0] flow_lo;
    logic [3:0] version;
    logic [3:0] flow_hi;
} ip6_hdr;

typedef struct packed
{
    ip6_hdr ip6;
    logic [15:0] ethertype;
    logic [47:0] src;
    logic [47:0] dst;
} ether_hdr;

typedef struct packed
{
    // Per-frame metadata.
    // **They are only effective at the first beat.**
    logic [ID_WIDTH - 1:0] id;  // The ingress interface.
    logic [ID_WIDTH - 1:0] dest;  // The egress interface.
    logic drop;  // Drop this frame (i.e., this beat and the following beats till the last)?
    logic dont_touch;  // Do not touch this beat!

    // Drop the next frame? It is useful when you need to shrink a frame
    // (e.g., replace an IPv6 packet to an ND solicitation).
    // You can do so by setting both last and drop_next.
    logic drop_next;

    // README: Your code here.
} frame_meta;

typedef struct packed
{
    // AXI-Stream signals.
    ether_hdr data;
    logic [DATAW_WIDTH / 8 - 1:0] keep;
    logic last;
    // The IP core will use this "user" signal to indicate errors, so do not modify it!
    logic [DATAW_WIDTH / 8 - 1:0] user;
    logic valid;

    // Handy signals.
    logic is_first;  // Is this the first beat of a frame?

    frame_meta meta;
} frame_beat;

typedef struct{
    reg [127:0] IPV6_ADDR;
    reg [47:0] MAC_ADDR;
    reg [2:0] STATE;
    reg Is_Router_Flag;
} neighbour_cache_entry;

`define should_handle(b) \
(b.valid && b.is_first && !b.meta.drop && !b.meta.dont_touch)

typedef enum logic [1:0]{
    UPDATE,INSERT,QUERY,DELETE
} OPERATION;

typedef enum logic [2:0]{
    INCOMPLETE,REACHABLE,STALE,DELAY,PROBE
} STATE;

// README: Your code here. You can define some other constants like EtherType.
localparam ID_CPU = 3'd4;  // The interface ID of CPU is 4.

localparam ETHERTYPE_IP6 = 16'hdd86;

`endif
