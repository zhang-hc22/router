
module button_in(
    input wire clk,
    
    input wire push_btn,
    output reg trigger
);
    reg prev_push_btn;

    always_ff @(posedge clk)
    begin
        prev_push_btn <= push_btn;
    end

    always_comb begin
        if (prev_push_btn == 1'b0 && push_btn == 1'b1) begin
            trigger = 1'b1;
        end else begin
            trigger = 1'b0;
        end 
    end
endmodule