module round_robin_arbiter_base #(
    parameter REQ_NUM = 8
) (
    input                  clk,
    input                  rstn,
    input  [REQ_NUM-1 : 0] reqs,
    output [REQ_NUM-1 : 0] grans
);
    
/*wire [2*REQ_NUM-1 : 0] double_reqs;
reg  [2*REQ_NUM-1 : 0] mask;
wire [2*REQ_NUM-1 : 0] masked_double_reqs_grans;
wire [2*REQ_NUM-1 : 0] masked_double_reqs;
wire [REQ_NUM-1 : 0]   masked_reqs;
wire                   has_masked_reqs;

assign has_masked_reqs = |masked_reqs;
assign masked_reqs = mask[REQ_NUM-1 : 0] & mask;
assign double_reqs = {reqs , reqs};
assign masked_double_reqs = double_reqs & mask;
assign masked_double_reqs_grans = masked_double_reqs & ~(masked_double_reqs - 1'b1);
assign grans = has_masked_reqs ? masked_double_reqs_grans[REQ_NUM-1 : 0] : masked_double_reqs_grans[2*REQ_NUM-1 : REQ_NUM];

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        mask <= {2*REQ_NUM{1'b1}};
    end
    else if (has_masked_reqs) begin
        mask <= {{REQ_NUM{1'b1}} , ~((grans-1'b1)|grans)};  
    end
    else if (mask[REQ_NUM-1 : 0] == 'b0) begin
        mask <= {2*REQ_NUM{1'b1}};
    end
end */

reg  [REQ_NUM-1 : 0]   priority_base; // 用于记录下一拍谁的优先级最高
wire [2*REQ_NUM-1 : 0] double_reqs;
wire [2*REQ_NUM-1 : 0] double_reqs_grans;

assign double_reqs = {reqs , reqs};
assign double_reqs_grans = double_reqs & ~(double_reqs - priority_base);
assign grans = double_reqs_grans[2*REQ_NUM-1 : REQ_NUM] | double_reqs_grans[REQ_NUM-1 : 0];

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        priority_base <= 'b1;
    end
    else if (|reqs) begin
        priority_base <= {grans[REQ_NUM-2 : 0] , grans[REQ_NUM-1]}; //这里采用的循环移位，不能简单的用向左移位，否则1000 移位后为 0001 而不是0000
    end
end
endmodule

//                                                     round_robin_arbiter    roind_robin_arbiter_base
// dobule_reqs                 = 1101_1101             reqs  1110             double_reqs    1110_1110 
// ~(doublule_reqs - priority) = 0010_1010             mask  1111             priority_base  0000_0001  
// priority_base               = 0000_1000             grans 0010             grans               0010  正确

// doubule_reqs - priority     = 1101_0101             reqs  0011             doulbe_reqs    0011_0011
//                                                     mask  1100             priority_base  0000_0100
//                                                     grans 0001             grans               0001  正确
// double_reqs_grans           = 0000_1000
// grans                       = 1000                  reqs  0110             double_reqs    0110_0110
//                                                     maske 1100             priority_base  0000_0010
                                   //                  grans 0100             grans               0010   有错误，不一样