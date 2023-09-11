module dma_src_ctrl #(
    parameter DATA_WD = 32,
    parameter ADDR_WD = 32,
    parameter LEN_WD  = 12,
    parameter BE_WD   = DATA_WD / 8
) (
//-----global signal-----
    input                    clk_i, 
    input                    rstn_i,

//-----from / to DMA_CH_RF-----
    input                    start_ch_req_i, //to-do ---> the explain
    output                   start_ch_ack_o,

    input [ADDR_WD - 1 : 0]  src_addr_i,
    input [LEN_WD - 1 : 0]   data_length_i, 

    input [ADDR_WD - 1 : 0]  bd_addr_i,
    input                    bd_last_i,
    output [DATA_WD - 1 : 0] bd_info_o,
    output [3 : 0]           bd_cs_o,
    output                   bd_update_o,

//-----from / to DMA_DST_CTRL-----
    input                    dst_idle_i,
    output                   src_done_o,

//-----from / to DMA_CH_BUF-----
    output                   buf_wvalid_o,
    output [BE_WD - 1 : 0]   buf_wbe_o,
    output [DATA_WD - 1 : 0] buf_wdata_o,
    input                    buf_wready_i,

//-----from / to CORE_BUS-----
    output                   core_ld_req_o,
    input                    core_ld_gnt_i,

    output                   core_ld_we_o,
    output [BE_WD - 1 : 0]   core_ld_be_o,
    
    output [DATA_WD - 1 : 0] core_ld_wdata_o,
    
    output [ADDR_WD - 1 : 0] core_ld_addr_o,
    input [DATA_WD - 1 : 0]  core_ld_rdata_i,
    input                    core_ld_rvalid_i

);

//-----FSM control signal-----
    enum logic [3 : 0] {LD_IDLE = 'b0,LD_BD_CTRL,LD_BD_S_ADDR,LD_BD_D_ADDR,LD_BD_NEXT,LD_SRC_FIRST,LD_SRC_SEQ,LD_SRC_LAST,LD_SRC_DONE} ld_cs,ld_ns;

    reg  start_ld;
    wire only_one_beat;
    wire has_extra_beat;
    wire only_last_beat;
    reg  pre_next_bd;

    wire start_ch_fire = start_ch_ack_o && start_ch_req_i;

    localparam INCR_WD = $clog2(BE_WD);
    reg [LEN_WD - 1 : 0]   src_data_cnt;  //how much byte has been read
    reg [INCR_WD    : 0]   src_data_incr; //how much byte will been read per beat

    reg [BE_WD - 1 : 0]    be_cs;
    reg [BE_WD - 1 : 0]    be_ns;

//-----output intermediate signals-----   

//------FSM-----
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            ld_cs <= LD_IDLE;
        end
        else begin
            ld_cs <= ld_ns;
        end
    end

    always @(*) begin
        ld_ns = ld_cs;
        case(ld_cs)
            LD_IDLE: begin
                if(start_ld) begin
                    ld_ns = LD_BD_CTRL;
                end
            end
            LD_BD_CTRL: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = LD_BD_S_ADDR;
                end
            end
            LD_BD_S_ADDR: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = LD_BD_D_ADDR;
                end
            end
            LD_BD_D_ADDR: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = LD_BD_NEXT;
                end
            end
            LD_BD_NEXT: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = LD_SRC_FIRST;
                end
            end
            LD_SRC_FIRST: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = only_one_beat ? 
                    LD_SRC_DONE : (has_extra_beat ? 
                    LD_SRC_SEQ : LD_SRC_LAST );    
                end
            end
            LD_SRC_SEQ: begin
                if(core_ld_rvalid_i && only_last_beat) begin
                    ld_ns = LD_SRC_LAST;
                end
            end
            LD_SRC_LAST: begin
                if(core_ld_rvalid_i) begin
                    ld_ns = LD_SRC_DONE;
                end
            end
            LD_SRC_DONE: begin
                ld_ns = LD_IDLE;
            end
        endcase
    end

always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        start_ld <= 'b0;
    end
    else if(start_ld) begin //clear itself
        start_ld <= 1'b0;
    end
    else if(ld_cs == LD_IDLE && pre_next_bd && dst_idle_i) begin //next_bd
        start_ld <= 1'b1;
    end
    else if(ld_cs == LD_IDLE && start_ch_req_i) begin //first_bd
        start_ld <= 1'b1;
    end
end

always @(posedge clk_i or negedge rstn_i) begin
    if(rstn_i) begin
        pre_next_bd <= 'b0;
    end
    else if(pre_next_bd) begin
        pre_next_bd <= 1'b0;
    end
    else if(ld_cs == LD_SRC_DONE && !bd_last_i) begin
        pre_next_bd <= 1'b1;
    end
end

//-----only_one_beat-----
assign only_one_beat  = src_addr_i[1 : 0] + data_length_i <= 4; //1111
//-----has_extra_beat-----
assign has_extra_beat = src_addr_i[1 : 0] + data_length_i > 8; //0001 1111 1111
//-----only_last_beat-----
assign only_last_beat = (data_length_i - (src_data_cnt + src_data_incr)) <= 4; //only_last_beat need to pre judge, so must sum "incr"

//------src_data_cnt-----
always @(posedge clk_i or negedge rstn_i) begin 
    if(!rstn_i) begin
        src_data_cnt <= 'b0;
    end
    else if(ld_cs == LD_SRC_DONE) begin
        src_data_cnt <= 'b0;
    end
    else if((ld_cs == LD_SRC_FIRST || ld_cs == LD_SRC_SEQ || ld_cs == LD_SRC_LAST) && core_ld_rvalid_i) begin
        src_data_cnt <= src_data_cnt + src_data_incr;
    end
end

//------src_data_incr----- 
always @(*) begin //it change in current byte
    src_data_incr = 'b0;
    if((ld_cs == LD_SRC_FIRST || ld_cs == LD_SRC_SEQ || ld_cs == LD_SRC_LAST) && core_ld_rvalid_i) begin
        for(reg[2:0] i=0; i<4; i++) begin
            src_data_incr = src_data_incr + be_cs[i];
        end
    end
end

//-----be_ns & be_cs-----
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        be_cs <= 'b0;
    end
    else begin
        be_cs <= be_ns;
    end
end

always @(*) begin
    be_ns = be_cs;
    if(ld_ns == LD_BD_CTRL || ld_ns == LD_SRC_SEQ) begin
        be_ns = 4'b1111;
    end
    else if(ld_ns == LD_SRC_FIRST) begin
        for(reg[2:0] i=0; i<4; i++) begin
            if(src_addr_i[1:0] + data_length_i >= 4) begin //like 1110 / 1111 / 1000
                be_ns[i] = ~(i < src_addr_i[1:0]); //less than addr--->1'b0 ,bigger than addr--->1'b1
            end
            else begin //like 0110 "only one byte" 
                be_ns[i] = ~(i < src_addr_i[1:0]) && (i < src_addr_i[1:0] + data_length_i);
                //0110 "src_addr_i + length  = 3" link to the location of "0"110,so let the "i < src_addr_i + length" -----> 0 could negetive the byte left than far left 1
            end                                                                                
        end
    end
    else if(ld_ns == LD_SRC_LAST && (ld_cs == LD_SRC_SEQ || ld_cs == LD_SRC_FIRST)) begin 
        for(reg[2:0] j=0; j<4; j++) begin
            be_ns[j] = (j < data_length_i - (src_data_cnt + src_data_incr)); //like 0011,j link to the low byte 1; 
                                                           // if total data is 0111 1000 src_data_cnt in first byte ----> 0
                                                           // (cnt + incr) ---> last byte cnt, so (length - (cnt + incr))    
        end
    end
end

//-----output-----
    
//start_ch_ack_o
reg start_ch_ack;
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        start_ch_ack <= 'b0;
    end
    else if(start_ch_fire) begin
        start_ch_ack <= 1'b0;
    end
    else if(start_ch_req_i && ld_cs == LD_IDLE) begin //ack is not ready, Don't understand it as the relationship between valid and ready
        start_ch_ack <= 1'b1;
    end
end

assign start_ch_ack_o = start_ch_ack;

//bd_info_o ; bd_cs_o ; bd_update_o
assign bd_info_o   = core_ld_rdata_i;
assign bd_cs_o     = ld_cs;
assign bd_update_o = core_ld_rvalid_i;

//src_done_o
assign src_done_o = ld_cs == LD_SRC_DONE;

//buf_wvalid_o ; buf_wbe_o ; buf_wdata_o
assign buf_wvalid_o  = ((ld_cs == LD_SRC_FIRST) || (ld_cs == LD_SRC_SEQ) || (ld_cs == LD_SRC_LAST)) && core_ld_rvalid_i;
assign buf_wbe_o   = be_cs;
assign buf_wdata_o = core_ld_rdata_i;

//next_req
reg next_req;
reg core_ld_req;
wire core_ld_fire = core_ld_req_o && core_ld_gnt_i;
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        next_req <= 1'b0;
    end
    else if(core_ld_req) begin
        next_req <= 1'b0;
    end
    else if(((ld_cs == LD_SRC_FIRST) | (ld_cs == LD_SRC_SEQ)) && core_ld_rvalid_i) begin
        next_req <= 1'b1;
    end
end

//core_ld_req_o ; core_ld_we_o ; core_ld_be_o ; core_ld_wdata_o ;  core_ld_addr_o
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        core_ld_req <= 'b0;
    end
    else if(core_ld_fire) begin 
        core_ld_req <= 1'b0;
    end
    else if(ld_ns == LD_BD_CTRL) begin
        core_ld_req <= 1'b1;
    end
    else if((ld_cs == LD_BD_CTRL || ld_cs == LD_BD_S_ADDR || ld_cs == LD_BD_D_ADDR || ld_cs == LD_BD_NEXT) && core_ld_rvalid_i) begin //for the timing true,req set to 1 at cs
        core_ld_req <= 1'b1;
    end
    else if(next_req && buf_wready_i) begin //cause the buf can't tranfer data in one byte
        core_ld_req <= 1'b1;
    end
end

assign core_ld_req_o = core_ld_req;

assign core_ld_we_o    = 1'b0; //write--->1; read--->0
assign core_ld_be_o    = be_cs;
assign core_ld_wdata_o = 'b0;

reg [ADDR_WD - 1 : 0] core_ld_addr;
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) begin
        core_ld_addr <= 'b0;
    end
    else if(ld_ns == LD_BD_CTRL) begin
        core_ld_addr <= bd_addr_i;
    end
    else if(ld_ns == LD_SRC_FIRST) begin
        core_ld_addr <= {src_addr_i[ADDR_WD - 1 : 2],{2'b00}};
    end
    else if(core_ld_rvalid_i) begin
        core_ld_addr <= core_ld_addr + 4;
    end
end

assign core_ld_addr_o = core_ld_addr;

endmodule