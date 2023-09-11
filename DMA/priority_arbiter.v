module priority_arbiter #(
    parameter REQ_NUM = 8 
) (
    input                  clk,
    input                  rstn,
    input  [REQ_NUM-1 : 0] reqs,  //请求的指令
    output [REQ_NUM-1 : 0] grants //授权的指令
);
    wire  [REQ_NUM-1 : 0] pre_reqs; //表示第i个请求之前有没有请求,有请求为1.无请求为0

    assign pre_reqs[0] = 1'b0;
    assign grants[0] = reqs[0];

localparam VECTOR = 1'b1; //向量写法

generate if (VECTOR) begin        
    genvar i;
        for (i = 1; i < REQ_NUM; i = i+1) begin
            assign pre_reqs[i] = |reqs[i-1 : 0]; // pre_reqs[i] = reqs[i-1] | pre_reqs[i-1];
            assign grants[i] = reqs[i] & ~pre_reqs[i];
        end
end
else begin 
    assign grants = reqs & ~pre_reqs;
    assign pre_reqs[REQ_NUM-1 : 1] = reqs[REQ_NUM-2 : 0] | pre_reqs[REQ_NUM-2 : 0]; // 向量形式 
end
endgenerate
    /*reqs      = 0 1 1 0 
    reqs-1    = 0 1 0 1;
    ~(reqs-1) = 1 0 1 0;
    reqs & ~(reqs-1) = 0 0 1 0;*/
    
    // assign grants = reqs & ~(reqs-1);
endmodule     