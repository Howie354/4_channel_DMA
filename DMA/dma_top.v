module dma_top #(
    parameter CH_NUM     = 4,
    parameter ADDR_WD    = 32,
    parameter DATA_WD    = 32,
    parameter BE_WD      = DATA_WD / 8,
    parameter CH_NUM_CNT = $clog2(CH_NUM)
) (
    input logic                    clk_i,
    input logic                    rstn_i,

    //DMA_RF_MEM_PORT
    input logic                    mem_en_i,
    input logic                    mem_we_i,
    input logic [BE_WD - 1 : 0]    mem_be_i,
    input logic [DATA_WD - 1 : 0]  mem_wdata_i,
    input logic [ADDR_WD - 1 : 0]  mem_addr_i,

    output logic [DATA_WD - 1 : 0] mem_rdata_o,

    //DMA_SRC_MASTER_LINT_PORT
    output logic                   lint_src_req_o,
    output logic                   lint_src_we_o,
    output logic [BE_WD - 1 : 0]   lint_src_be_o,
    output logic [DATA_WD - 1 : 0] lint_src_wdata_o,
    output logic [ADDR_WD - 1 : 0] lint_src_addr_o,

    input logic                    lint_src_gnt_i,
    input logic                    lint_src_rvalid_i,
    input logic [DATA_WD - 1 : 0]  lint_src_rdata_i,

    //DMA_DST_MASTER_LINT_PORT
    output logic                   lint_dst_req_o,
    output logic                   lint_dst_we_o,
    output logic [BE_WD - 1 : 0]   lint_dst_be_o,
    output logic [DATA_WD - 1 : 0] lint_dst_wdata_o,
    output logic [ADDR_WD - 1 : 0] lint_dst_addr_o,

    input logic                    lint_dst_gnt_i,
    input logic                    lint_dst_rvalid_i,
    input logic [DATA_WD - 1 : 0]  lint_dst_rdata_i                  
);
//-------------CPU_CMD_MODULE---------------//   
//CPU ------> DMA_RF

logic [CH_NUM - 1 : 0]     mem_en;
logic [DATA_WD - 1 : 0]    mem_rdata [CH_NUM - 1 : 0];
logic [CH_NUM_CNT - 1 : 0] last_ch_num_cs;
logic [CH_NUM_CNT - 1 : 0] last_ch_num_ns;

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        last_ch_num_cs <= 'b0;
    end
    else begin
        last_ch_num_cs <= last_ch_num_ns;
    end
end

integer i;
always @(*) begin
    last_ch_num_ns = 'b0;
    mem_en         = 'b0;
    for(i = 0; i < CH_NUM; i = i + 1) begin
        if((mem_addr_i[5 +: CH_NUM_CNT] == i) && mem_en_i) begin
            mem_en[i]      = 1'b1;
            last_ch_num_ns = i;
        end
    end
end

assign mem_rdata_o = mem_rdata[last_ch_num_cs];
//------------------------------------------//

//---------SRC_ARBITER_MODULE---------------//
//DMA_SRC ------> ARBITER ------> OUTPUT
logic [CH_NUM - 1 : 0]  lint_src_req;
logic [CH_NUM - 1 : 0]  lint_src_we;
logic [BE_WD - 1 : 0]   lint_src_be    [CH_NUM - 1 : 0];
logic [DATA_WD - 1 : 0] lint_src_wdata [CH_NUM - 1 : 0];
logic [ADDR_WD - 1 : 0] lint_src_addr  [CH_NUM - 1 : 0];

logic [CH_NUM - 1 : 0]  lint_src_gnt;
logic [CH_NUM - 1 : 0]  lint_src_rvalid;
logic [DATA_WD - 1 : 0] lint_src_rdata;

//---keep which channel's req---
logic [CH_NUM - 1 : 0] src_sel;
logic [CH_NUM - 1 : 0] src_sel_q;
logic                  src_arb_forbid; //as soon as rvalid come,forbid could turn 0 

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        src_sel_q <= 'b0;
    end
    else if(|lint_src_req && ~src_arb_forbid) begin
        src_sel_q <= src_sel;
    end
end

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        src_arb_forbid <= 1'b0;
    end
    else if(lint_src_rvalid_i) begin
        src_arb_forbid <= 1'b0;
    end
    else if(|lint_src_req) begin
        src_arb_forbid <= 1'b1;
    end
end

//output 
integer j;
always @(*) begin
    lint_src_req_o   = 'b0;
    lint_src_we_o    = 'b0;
    lint_src_be_o    = 'b0;
    lint_src_wdata_o = 'b0;
    lint_src_addr_o  = 'b0;
    for(j = 0; j < CH_NUM; j = j + 1) begin
        if(src_sel_q[j]) begin
            lint_src_req_o   = lint_src_req[j];
            lint_src_we_o    = 1'b0;
            lint_src_be_o    = lint_src_be[j];
            lint_src_wdata_o = 'b0;
            lint_src_addr_o  = lint_src_addr[j];
        end
         
    end
end

integer k;
always @(*) begin
    lint_src_gnt    = 'b0;
    lint_src_rvalid = 'b0;
    for(k = 0; k < CH_NUM; k = k + 1) begin
        if(src_sel_q[k]) begin
            lint_src_gnt[k]    = lint_src_gnt_i;
            lint_src_rvalid[k] = lint_src_rvalid_i;
        end        
    end
end

assign lint_src_rdata = lint_src_rdata_i;

round_robin_arbiter #(
    .REQ_NUM(CH_NUM)
) u1_round_robin_arbiter (
    .clk_i(clk_i),
    .rstn_i(rstn_i),
    .reqs_i(lint_src_req & ~{CH_NUM{src_arb_forbid}}), //if forbid,pause process
    .gnts_o(src_sel)
);
//------------------------------------------//

//---------DST_ARBITER_MODULE---------------//
//DMA_DST ------> ARBITER ------> OUTPUT
logic [CH_NUM - 1 : 0]  lint_dst_req;
logic [CH_NUM - 1 : 0]  lint_dst_we;
logic [BE_WD - 1 : 0]   lint_dst_be    [CH_NUM - 1 : 0];
logic [DATA_WD - 1 : 0] lint_dst_wdata [CH_NUM - 1 : 0];
logic [ADDR_WD - 1 : 0] lint_dst_addr  [CH_NUM - 1 : 0];

logic [CH_NUM - 1 : 0]  lint_dst_gnt;
logic [CH_NUM - 1 : 0]  lint_dst_rvalid;
logic [DATA_WD - 1 : 0] lint_dst_rdata;

//---keep which channel's req---
logic [CH_NUM - 1 : 0] dst_sel;
logic [CH_NUM - 1 : 0] dst_sel_q;
logic                  dst_arb_forbid; //as soon as rvalid come,forbid could turn 0

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        dst_sel_q <= 'b0;
    end
    else if(|lint_dst_req && ~dst_arb_forbid) begin
        dst_sel_q <= dst_sel;
    end
end

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        dst_arb_forbid <= 1'b0;
    end
    else if(lint_dst_rvalid_i) begin
        dst_arb_forbid <= 1'b0;
    end
    else if(|lint_dst_req) begin
        dst_arb_forbid <= 1'b1;
    end
end

//output 
integer m;
always @(*) begin
    lint_dst_req_o   = 'b0;
    lint_dst_we_o    = 1'b1;
    lint_dst_be_o    = 'b0;
    lint_dst_wdata_o = 'b0;
    lint_dst_addr_o  = 'b0;
    for(m = 0; m < CH_NUM; m = m + 1) begin
        if(dst_sel_q[m]) begin
            lint_dst_req_o   = lint_dst_req[m];
            lint_dst_we_o    = 1'b1;
            lint_dst_be_o    = lint_dst_be[m];
            lint_dst_wdata_o = lint_dst_wdata[m];
            lint_dst_addr_o  = lint_dst_addr[m];
        end
         
    end
end

integer n;
always @(*) begin
    lint_dst_gnt    = 'b0;
    lint_dst_rvalid = 'b0;
    for(n = 0; n < CH_NUM; n = n + 1) begin
        if(dst_sel_q[n]) begin
            lint_dst_gnt[n]    = lint_dst_gnt_i;
            lint_dst_rvalid[n] = lint_dst_rvalid_i;
        end        
    end
end

assign lint_dst_rdata = lint_dst_rdata_i;

round_robin_arbiter #(
    .REQ_NUM(CH_NUM)
) u2_round_robin_arbiter (
    .clk_i(clk_i),
    .rstn_i(rstn_i),
    .reqs_i(lint_dst_req & ~{CH_NUM{dst_arb_forbid}}),
    .gnts_o(dst_sel)
);
//------------------------------------------//
//instantiation
generate
    genvar o;
    for(o = 0; o < CH_NUM; o = o + 1) begin
        dma_channel #(
            .ADDR_WD(ADDR_WD),
            .DATA_WD(DATA_WD), 
            .LEN_WD(12), 
            .BE_WD(BE_WD)
        ) dma_channel_o (
            .clk_i(clk_i),
            .rstn_i(rstn_i),

            //mem port
            .mem_en_i(mem_en[o]),         
            .mem_we_i(mem_we_i),          
            .mem_wdata_i(mem_wdata_i),       
            .mem_be_i(mem_be_i),          
            .mem_addr_i({27'b0,mem_addr_i[4 : 0]}), //the low 5 bits aims to focus which channel and which rf      
            .mem_rdata_o(mem_rdata[o]),

            //src lint port
            .lint_src_req_o(lint_src_req[o]),
            .lint_src_we_o(lint_src_we[o]),
            .lint_src_wdata_o(lint_src_wdata[o]),
            .lint_src_be_o(lint_src_be[o]),
            .lint_src_addr_o(lint_src_addr[o]),
            .lint_src_gnt_i(lint_src_gnt_i[o]),
            .lint_src_rvalid_i(lint_src_rvalid_i[o]),
            .lint_src_rdata_i(lint_src_rdata), //don't need to 2 dimension,because it controled by rvalid

            //dst lint port
            .lint_dst_req_o(lint_dst_req[o]),
            .lint_dst_we_o(lint_dst_we[o]),
            .lint_dst_wdata_o(lint_dst_wdata[o]),
            .lint_dst_be_o(lint_dst_be[o]),
            .lint_dst_addr_o(lint_dst_addr[o]),
            .lint_dst_gnt_i(lint_dst_gnt[o]),
            .lint_dst_rvalid_i(lint_dst_rvalid[o]),
            .lint_dst_rdata_i(lint_dst_rdata)
        );
    end
endgenerate

endmodule