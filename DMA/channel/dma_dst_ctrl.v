module dma_dst_ctrl #(
    parameter DATA_WD = 32,
    parameter ADDR_WD = 32,
    parameter LEN_WD  = 12,
    parameter BE_WD   = DATA_WD / 8
) (
    input                    clk_i,
    input                    rstn_i,

//-----from / to DMA_CH_RF-----
    input [ADDR_WD - 1 : 0]  dst_addr_i,
    input [LEN_WD - 1 : 0]   data_length_i,

//-----from / to DMA_SRC_CTRL-----
    input                    src_done_i,
    output                   dst_idle_o,

//-----from / to DMA_CH_BUF-----
    input                    buf_rvalid_i,
    output                   buf_rready_o,
    output [BE_WD - 1 : 0]   buf_rbe_o,
    input [DATA_WD - 1 : 0]  buf_rdata_i,

//-----from / to CORE_BUS-----
    output                   core_st_req_o,
    input                    core_st_gnt_i,

    output                   core_st_we_o,
    output [BE_WD-1 : 0]     core_st_be_o,

    output [ADDR_WD - 1 : 0] core_st_addr_o,
    output [DATA_WD - 1 : 0] core_st_wdata_o,
    
    input [DATA_WD - 1 : 0]  core_st_rdata_i,
    input                    core_st_rvalid_i
);
    
//-----FSM-----
    localparam ST_DST_IDLE  = 3'b000;
    localparam ST_DST_FIRST = 3'b001;
    localparam ST_DST_SEQ   = 3'b010;
    localparam ST_DST_LAST  = 3'b011;
    localparam ST_DST_DONE  = 3'b100;

    reg [2 : 0] st_cs,st_ns;
    wire buf_fire     = buf_rvalid_i && buf_rready_o;
    wire core_st_fire = core_st_req_o && core_st_gnt_i;
    
    wire only_one_beat;
    wire has_extra_beat;
    wire only_last_beat;

    //-----start_st-----
    reg start_st;
    always @(posedge clk_i or rstn_i) begin
        if(!rstn_i) begin
            start_st <= 'b0;
        end
        else if (start_st) begin
            start_st <= 1'b0;
        end
        else if(src_done_i && st_cs == ST_DST_IDLE) begin
            start_st <= 1'b1;
        end
    end

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            st_cs <= ST_DST_IDLE;
        end
        else begin
            st_cs <= st_ns;
        end
    end

    always @(*) begin
        st_ns = st_cs;
        case (st_cs) //focus only when 'gnt_i pulse',state can change
            ST_DST_IDLE: begin
                if(start_st) begin
                    st_ns = ST_DST_FIRST;
                end
            end
            ST_DST_FIRST: begin
                if(core_st_gnt_i) begin
                    st_ns = only_one_beat ? ST_DST_DONE :
                        (has_extra_beat ? ST_DST_SEQ :
                        ST_DST_LAST);
                end
            end
            ST_DST_SEQ: begin
                if(core_st_gnt_i) begin
                    st_ns = only_last_beat ? ST_DST_LAST : ST_DST_SEQ;
                end
            end
            ST_DST_LAST: begin
                if(core_st_gnt_i) begin
                    st_ns = ST_DST_DONE;
                end
            end
            ST_DST_DONE: begin
                st_ns = ST_DST_IDLE;
            end
        endcase
    end

    

    //-----only_one_beat;has_extra_beat;only_last_beat
    assign only_one_beat  = dst_addr_i[1 : 0] + data_length_i     <= 4;
    assign has_extra_beat = dst_addr_i[1 : 0] + data_length_i      > 8;

    //-----data_cnt;data_incr-----
    reg [LEN_WD - 1 : 0]  data_cnt;
    localparam INCR_WD =  $clog2(BE_WD);
    reg [INCR_WD  : 0]    data_incr;
    reg [BE_WD - 1 : 0]   be_cs,be_ns;

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            data_cnt <= 'b0;
        end
        else if(st_cs == ST_DST_DONE) begin
            data_cnt <= 'b0;
        end
        else if((st_cs == ST_DST_FIRST | st_cs == ST_DST_SEQ | st_cs == ST_DST_LAST) && core_st_gnt_i) begin
            data_cnt <= data_cnt + data_incr;
        end
    end

    integer i;
    always @(*) begin
        data_incr = 'b0;
        if(st_cs == ST_DST_FIRST | st_cs == ST_DST_SEQ | st_cs == ST_DST_LAST) begin
            for (i = 0; i < BE_WD; i = i + 1) begin
                data_incr[i] = data_incr + be_cs[i];
            end
        end
    end

    assign only_last_beat = data_length_i - data_cnt - data_incr  <= 4; //1111 1111 1100

    //-----be_cs;be_ns-----
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            be_cs <= 'b0;
        end
        else begin
            be_cs <= be_ns;
        end
    end

    integer m,n;
    always @(*) begin
        be_ns = be_cs;
        if(st_cs == ST_DST_SEQ) begin
            be_ns = 4'b1111;
        end
        if(st_cs == ST_DST_FIRST) begin
            for(m = 0; m < BE_WD; m = m + 1) begin
                if(!only_one_beat) begin //0011 1100
                    be_ns[m] = m >= dst_addr_i[1 : 0];
                end
                else begin // consider dst_addr + data_length <= 4 ; 0110,1111
                    be_ns[m] = (m >= dst_addr_i[1 : 0]) && (m < (dst_addr_i[1 : 0] + data_length_i));
                end
            end
        end
        if(st_ns == ST_DST_LAST && (st_cs == ST_DST_SEQ || st_cs == ST_DST_FIRST)) begin //0011 1111 1100 because data_cnt would change along with beat,so must control the cs == seq
            for(n = 0; n < BE_WD; n = n + 1) begin 
                be_ns[n] <= (n < data_length_i - data_cnt - data_incr); 
            end
        end
    end

    //-----output-----
    
    //dst_idle_o
    assign dst_idle_o = st_cs == ST_DST_IDLE;

    //buf_rready_o
    reg buf_rready;
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            buf_rready <= 'b0;
        end
        else if(buf_fire) begin
            buf_rready <= 'b0;
        end
        else if(st_cs == ST_DST_IDLE && st_ns == ST_DST_FIRST) begin
            buf_rready <= 1'b1;
        end
        else if((st_cs == ST_DST_FIRST | st_cs == ST_DST_SEQ | st_cs == ST_DST_LAST) && core_st_gnt_i) begin
            buf_rready <= 1'b1;
        end
    end
    assign buf_rready_o = buf_rready;

    //buf_rbe_o
    assign buf_rbe_o = be_ns; //Give 'be' to 'buf' in advance so that it can pop up the correct data
    
    //core_st_req_o
    reg core_st_req;
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            core_st_req <= 'b0;
        end
        else if(core_st_fire) begin
            core_st_req <= 'b0;
        end
        else if((st_cs == ST_DST_FIRST | st_cs == ST_DST_SEQ | st_cs == ST_DST_LAST) & buf_rvalid_i) begin
            core_st_req <= 1'b1;
        end
    end
    assign core_st_req_o = core_st_req;


    //core_st_we_o 1--->write
    assign core_st_we_o = 1'b1;

    //core_st_addr_o
    reg core_st_addr;
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            core_st_addr <= 'b0;
        end
        else if(st_cs == ST_DST_IDLE && st_ns == ST_DST_FIRST) begin
            core_st_addr <= {dst_addr_i[ADDR_WD - 1 : 2],{2'b00}};
        end
        else if((st_cs == ST_DST_FIRST | st_cs == ST_DST_SEQ | st_cs == ST_DST_LAST) && core_st_gnt_i) begin
            core_st_addr <= core_st_addr + 4;
        end
    end
    assign core_st_addr_o = core_st_addr;
    
    //core_st_wdata_o
    assign core_st_wdata_o = buf_rdata_i;

    //core_st_be_o
    assign core_st_be_o = be_cs;

endmodule