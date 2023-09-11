module round_robin_arbiter #(
    parameter REQ_NUM = 4
) (
    input                    clk_i,
    input                    rstn_i,

    input  [REQ_NUM - 1 : 0] reqs_i,
    output [REQ_NUM - 1 : 0] gnts_o
);

reg  [REQ_NUM - 1 : 0] mask; //default 1111
wire [REQ_NUM - 1 : 0] mask_reqs;
wire                   has_masked_reqs;
wire [REQ_NUM - 1 : 0] mask_gnts;
wire [REQ_NUM - 1 : 0] unmask_gnts;

assign gnts_o          = has_masked_reqs ? mask_gnts : unmask_gnts;
assign mask_reqs       = mask & reqs_i;
assign has_masked_reqs = |mask_reqs;
assign unmask_gnts     = reqs_i & ~(reqs_i - 1'b1);
assign mask_gnts       = mask_reqs & ~(mask_reqs - 1'b1); //set the far right 1 bit one hot

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        mask <= {REQ_NUM{1'b1}};
    end
    else if(~(|mask)) begin
        mask <= {REQ_NUM{1'b1}};
    end
    else if(|reqs_i) begin
        mask <= ~(gnts_o | (gnts_o - 1'b1)); //set the bits far left than grans all 1
    end
end


    // reqs =                 8'b01010001;
    // mask =                 8'b11111100;
    // masked_reqs =          8'b01010000;
    // has_masked_reqs =             1'b1;
    // grants =               8'b00010000;

    // grants-1 =             8'b00001111;
    // grants|(grants-1) =    8'b00011111;
    // ~(grants|(grants-1)) = 8'b11100000;      形成下一个mask的算法
    // next_mask =            8'b11100000;

endmodule