module dma_buf #(
    parameter DATA_WD = 32,
    parameter BE_WD   = DATA_WD / 8
)(
    
    input                    clk_i,
    input                    rstn_i,

    input                    wvalid_i, //PUSH_CTRL模块
    input [DATA_WD - 1 : 0]  wdata_i,
    input [BE_WD - 1 : 0]    wbe_i,
    output                   wready_o,

    output                   rvalid_o, //POP_CTRL模块
    output [DATA_WD - 1 : 0] rdata_o,
    input [BE_WD - 1 : 0]    rbe_i,
    input                    rready_i
);

//---------------------WRITE LOGIC-------------------------
    enum logic [1 : 0] {SRC_WR_IDLE = 'b0,SRC_WR_RUN,SRC_WR_DONE} src_wr_cs,src_wr_ns;

    wire   fire_in;
    assign fire_in = wvalid_i && wready_o;

    reg                   wvalid_keep;
    reg [BE_WD - 1   : 0] wbe_keep; 
    reg [DATA_WD - 1 : 0] wdata_keep;  

    always @(posedge clk_i or negedge rstn_i) begin //将valid等控制信号和数据先保存起来
        if(~rstn_i) begin
            wvalid_keep <= 'b0;
            wbe_keep    <= 4'b1111;
        end
        else if (src_wr_cs == SRC_WR_DONE) begin
            wvalid_keep <= 'b0;
            wbe_keep    <= 4'b1111;
        end
        else if(fire_in) begin
            wvalid_keep <= wvalid_i;
            wdata_keep  <= wdata_i;
            wbe_keep    <= wbe_i;
        end
    end

    localparam COUNT_WD = $clog2(BE_WD);
    reg [COUNT_WD - 1 : 0] src_byte_index_ns,src_byte_index_cs;
    reg [COUNT_WD - 1 : 0] src_byte_trgt;
    reg [COUNT_WD : 0]     wbyte_length_ns,wbyte_length_cs;
    wire                   not_full;

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            src_byte_index_cs <= 'b0;
            wbyte_length_cs   <= 'b0;
        end
        else begin
            src_byte_index_cs <= src_byte_index_ns;
            wbyte_length_cs   <= wbyte_length_ns;
        end
    end

    always @(*) begin //利用for循环找到起始byte_enable中1的位置，确定目标trgt的位置
            src_byte_index_ns = src_byte_index_cs;
            wbyte_length_ns = 'b0;
            if(src_wr_cs == SRC_WR_IDLE && not_full) begin //在RUN之前遍寻wbe_keep，来找到第一个1出现的位置index                                                               //和1出现的次数length,并通过加法确定trgt的位置
                for(reg [2:0] i = 0;i < 4;i++) begin
                    if (wbe_keep[i]) begin  
                        src_byte_index_ns = i;
                        break;
                    end
                end

                for(reg [2:0] j = 0;j < 4;j++) begin
                    if(wbe_keep[j]) begin
                        wbyte_length_ns = wbyte_length_ns + 1'b1;
                    end
                end

                src_byte_trgt = src_byte_index_ns + wbyte_length_ns - 1;
        end

        else if (src_wr_cs == SRC_WR_RUN) begin //在RUN的时候，每一拍index + 1
            src_byte_index_ns = src_byte_index_ns + 1'b1;
        end
    end

    wire         wdone     = src_byte_index_cs == src_byte_trgt;
    wire         push_en   = (src_wr_cs == SRC_WR_RUN) && (not_full);
    wire [7 : 0] push_data = wdata_keep >> (src_byte_index_cs*8);

    reg wready;
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            wready <= 1'b1;
        end
        else if(fire_in) begin
            wready <= 'b0;
        end
        else if(src_wr_cs == SRC_WR_DONE) begin
            wready <= 1'b1;
        end
    end
    assign wready_o = wready;
//-----------------------fsm-------------------------------------
    always @(posedge clk_i or negedge rstn_i) begin
        if(~rstn_i) begin
            src_wr_cs <= SRC_WR_IDLE;
        end
        else begin
            src_wr_cs <= src_wr_ns;
        end
    end

    always @(*) begin
        src_wr_ns = src_wr_cs;
        case (src_wr_cs) 
            SRC_WR_IDLE: begin
                if(wvalid_keep) begin
                    src_wr_ns = SRC_WR_RUN;
                end    
            end
            SRC_WR_RUN: begin
                if(wdone) begin
                    src_wr_ns = SRC_WR_DONE;
                end
            end
            SRC_WR_DONE: begin
                src_wr_ns = SRC_WR_IDLE;
            end
        endcase
    end


//---------------------READ LOGIC-------------------------

    wire         pop_en;
    wire [7 : 0] pop_data;
    wire         not_empty;
    wire         rdone;

    enum logic [1 : 0] {DST_RD_IDLE = 'b0,DST_RD_RUN,DST_RD_DONE} dst_rd_cs,dst_rd_ns;

    
    reg [DATA_WD - 1 : 0]  r_data_keep;

    reg [COUNT_WD - 1 : 0] dst_byte_index_ns,dst_byte_index_cs;
    reg [COUNT_WD - 1 : 0] dst_byte_trgt;
    reg [COUNT_WD : 0]     rbyte_length_ns,rbyte_length_cs;

    reg [BE_WD - 1 : 0]    r_be_keep;
    reg                    rready_keep;
    always @(posedge clk_i or negedge rstn_i) begin
        if(~rstn_i) begin
            r_be_keep   <= 'b0;
            rready_keep <= 'b0;
        end
        else if(dst_rd_cs == DST_RD_DONE) begin
            rready_keep <= 'b0;
        end
        else if(rready_i && dst_rd_cs == DST_RD_IDLE) begin
            r_be_keep   <= rbe_i;
            rready_keep <= rready_i;
        end
    end

    always @(posedge clk_i or negedge rstn_i) begin
        if(pop_en) begin
            r_data_keep[dst_byte_index_cs*8 +: 8] <= pop_data;
        end
    end

    assign pop_en    = dst_rd_cs == DST_RD_RUN && not_empty;

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            dst_byte_index_cs <= 'b0;
            rbyte_length_cs   <= 'b0;
        end
        else begin
            dst_byte_index_cs <= dst_byte_index_ns;
            rbyte_length_cs   <= rbyte_length_ns;
        end
    end

    always @(*) begin //利用for循环找到起始byte_enable中1的位置，确定目标trgt的位置
            dst_byte_index_ns = dst_byte_index_cs;
            rbyte_length_ns   = rbyte_length_cs;
        if(dst_rd_cs == DST_RD_IDLE && not_empty) begin //在RUN之前遍寻rbe_keep，来找到第一个1出现的位置index                                                              //和1出现的次数length,并通过加法确定trgt的位置
            for(reg [2:0] m = 0;m < 4;m++) begin
                if (rbe_keep[m]) begin  
                    dst_byte_index_ns = m;
                    break;
                end
            end

            for(reg [2:0] n = 0;n < 4;n++) begin
                if(rbe_keep[n]) begin
                    rbyte_length_ns = rbyte_length_ns + 1'b1;
                end
            end

            dst_byte_trgt = dst_byte_index_ns + rbyte_length_ns - 1;
        end

        else if (dst_rd_cs == DST_RD_RUN) begin //在RUN的时候，每一拍index + 1
            dst_byte_index_ns = dst_byte_index_ns + 1'b1;
        end
    end

//-----------------------fsm-------------------------------------

    always @(posedge clk_i or negedge rstn_i) begin
        if(~rstn_i) begin
            dst_rd_cs <= DST_RD_IDLE;
        end
        else begin
            dst_rd_cs <= dst_rd_ns;
        end
    end

    always @(*) begin
        dst_rd_ns = dst_rd_cs;
        case (dst_rd_cs) 
            DST_RD_IDLE: begin
                if(rready_keep) begin
                    dst_rd_ns = DST_RD_RUN;
                end    
            end
            DST_RD_RUN: begin
                if(rdone) begin
                    dst_rd_ns = DST_RD_DONE;
                end
            end
            DST_RD_DONE: begin
                dst_rd_ns = DST_RD_IDLE;
            end
        endcase
    end

    
    assign rdone     = dst_byte_index_cs == dst_byte_trgt && dst_rd_cs == SRC_WR_RUN;
    assign rdata_o   = r_data_keep;
    assign rvalid_o  = dst_rd_cs == DST_RD_DONE;

syn_fifo #(
    .DATA_WD(8),
    .DEPTH(64)
    ) buf_fifo (
    .clk_i(clk_i),
    .rstn_i(rstn_i),

    .wr_valid_i(push_en),
    .wr_data_i(push_data),
    .wr_ready_o(not_full),

    .rd_ready_i(pop_en),
    .rd_data_o(pop_data),
    .rd_valid_o(not_empty)
    );


endmodule