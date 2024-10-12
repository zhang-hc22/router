
module addr_conf(
    input wire clk,
    input wire rst_btn,           // 复位按钮

    input wire [15:0] dip_sw,     // 拨码开关
    input wire set_btn,           // 设置按钮

    output reg [47:0] mac_addr,
    output reg [127:0] ipv6_addr,

    output reg [3:0] addr_select,  // 地址选择信号
    output reg finished            // 地址配置完成信号
);
    logic [3:0] counter;   // 计数器
    logic [2:0] pos;       // 指定位数

    assign pos = counter - 1;
    
    always_ff @(posedge clk) begin
        if (rst_btn) begin
            counter <= 4'h0;
            finished <= 1'b0;
        end
        else begin
            if (set_btn) begin
                counter <= counter + 1;
            end
            if ((counter >= 4'd8 && addr_select[0] == 1'b1)
                || (counter >= 4'd3 && addr_select[0] == 1'b0)) begin
                finished <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin : select_address
        if (rst_btn) begin
            addr_select <= 4'h0;
        end else begin
            if (counter == 4'h1) begin
                addr_select <= dip_sw[3:0];
            end
        end
    end

    always_ff @(posedge clk) begin : set_addr
        if (rst_btn) begin
            mac_addr <= 48'h0;
            ipv6_addr <= 128'h0;
        end
        else if (set_btn) begin
            case ({pos, addr_select[0]})
                4'b0000: mac_addr[15:0] <= dip_sw;
                4'b0010: mac_addr[31:16] <= dip_sw;
                4'b0100: mac_addr[47:32] <= dip_sw;

                4'b0001: ipv6_addr[15:0] <= dip_sw;
                4'b0011: ipv6_addr[31:16] <= dip_sw;
                4'b0101: ipv6_addr[47:32] <= dip_sw;
                4'b0111: ipv6_addr[63:48] <= dip_sw;
                4'b1001: ipv6_addr[79:64] <= dip_sw;
                4'b1011: ipv6_addr[95:80] <= dip_sw;
                4'b1101: ipv6_addr[111:96] <= dip_sw;
                4'b1111: ipv6_addr[127:112] <= dip_sw;
                default: ;
            endcase
        end
    end
endmodule