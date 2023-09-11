module dma_channel #(
    parameter ADDR_WD = 32,
    parameter DATA_WD = 32,
    parameter LEN_WD  = 12,
    parameter BE_WD   = DATA_WD / 8 
) (
    //global
    input                    clk_i,
    input                    rstn_i,

    //rf memory port
    input                    mem_en_i,
    input                    mem_we_i,
    input  [DATA_WD - 1 : 0] mem_wdata_i,
    input  [ADDR_WD - 1 : 0] mem_addr_i,
    input  [BE_WD - 1 : 0]   mem_be_i,
    output [DATA_WD - 1 : 0] mem_rdata_o,

    //src lint master port
    output                   lint_src_req_o,
    output                   lint_src_we_o,
    output [ADDR_WD - 1 : 0] lint_src_addr_o,
    output [DATA_WD - 1 : 0] lint_src_wdata_o,
    output [BE_WD - 1 : 0]   lint_src_be_o,

    input                    lint_src_gnt_i,
    input [DATA_WD - 1 : 0]  lint_src_rdata_i,
    input                    lint_src_rvalid_i,

    //dst lint master port
    output                   lint_dst_req_o,
    output                   lint_dst_we_o,
    output [ADDR_WD - 1 : 0] lint_dst_addr_o,
    output [DATA_WD - 1 : 0] lint_dst_wdata_o,
    output [BE_WD - 1 : 0]   lint_dst_be_o,

    input                    lint_dst_gnt_i,
    input [DATA_WD - 1 : 0]  lint_dst_rdata_i,
    input                    lint_dst_rvalid_i

    );
    
//Intermediate variables

//from/to DMA_CH_RF & DMA_SRC_CTRL
wire                 start_ch_req;
wire                 start_ch_ack;
wire [LEN_WD-1 : 0]  data_length;
wire [ADDR_WD-1 : 0] src_addr;
wire [ADDR_WD-1 : 0] bd_addr;
wire [DATA_WD-1 : 0] bd_info;
wire [BE_WD-1 : 0]   bd_cs;
wire                 bd_update;
wire                 bd_last;

//from/to DMA_CH_RF & DMA_DST_CTRL  //share "data_length" wire
wire [ADDR_WD - 1 : 0] dst_addr;   

//from/to DMA_SRC_CTRL & BUF
wire [DATA_WD-1 : 0] buf_wdata;
wire                 buf_wvalid;
wire [BE_WD-1 : 0]   buf_wbe;
wire                 buf_wready;   

//from/to DMA_DST_CTRL & BUF
wire [DATA_WD-1 : 0] buf_rdata;
wire                 buf_rvalid;
wire [BE_WD-1 : 0]   buf_rbe;
wire                 buf_rready;

//from/to DMA_SRC_CTRL & DMA_DST_CTRL
wire                 src_done;
wire                 dst_idle;


dma_ch_rf #(
                .DATA_WD          ( DATA_WD           ),
                .ADDR_WD          ( ADDR_WD           ),
                .BE_WD            ( BE_WD             ),
                .LEN_WD           ( LEN_WD            )

) u_dma_ch_rf (
                .clk_i            ( clk_i             ),
                .rstn_i           ( rstn_i            ),
                
                .dst_addr_o       ( dst_addr          ), //dst_ctrl

                .start_ch_req_o   ( start_ch_req      ),
                .start_ch_ack_i   ( start_ch_ack      ),
                .data_length_o    ( data_length       ),
                .src_addr_o       ( src_addr          ),
                .bd_addr_o        ( bd_addr           ),
                .bd_info_i        ( bd_info           ),
                .bd_cs_i          ( bd_cs             ),
                .bd_update_i      ( bd_update         ),
                .bd_last_o        ( bd_last           ),

                .core_req_i       ( mem_en_i          ),
                .core_we_i        ( mem_we_i          ),
                .core_gnt_o       (                   ),
                .core_addr_i      ( mem_addr_i        ),
                .core_wdata_i     ( mem_wdata_i       ),
                .core_rdata_o     ( mem_rdata_o       ),
                .core_rvalid_o    (                   )
);

dma_src_ctrl #(
                .DATA_WD          ( DATA_WD           ),
                .ADDR_WD          ( ADDR_WD           ),
                .BE_WD            ( BE_WD             ),
                .LEN_WD           ( LEN_WD            )
) u_dma_src_ctrl (
                .clk_i            ( clk_i             ),
                .rstn_i           ( rstn_i            ),

                .buf_wdata_o      ( buf_wdata         ),
                .buf_wvalid_o     ( buf_wvalid        ),
                .buf_wbe_o        ( buf_wbe           ),
                .buf_wready_i     ( buf_wready        ),

                .start_ch_req_i   ( start_ch_req      ),
                .start_ch_ack_o   ( start_ch_ack      ),
                .data_length_i    ( data_length       ),
                .src_addr_i       ( src_addr          ),
                .bd_addr_i        ( bd_addr           ),
                .bd_info_o        ( bd_info           ),
                .bd_cs_o          ( bd_cs             ),
                .bd_update_o      ( bd_update         ),
                .bd_last_i        ( bd_last           ),
       
                .src_done_o       ( src_done          ),
                .dst_idle_i       ( dst_idle          ),

                .core_ld_req_o    ( lint_src_req_o    ),
                .core_ld_gnt_i    ( lint_src_gnt_i    ),
                .core_ld_we_o     ( lint_src_we_o     ),
                .core_ld_be_o     ( lint_src_be_o     ),
                .core_ld_wdata_o  ( lint_src_wdata_o  ),
                .core_ld_addr_o   ( lint_src_addr_o   ),
                .core_ld_rdata_i  ( lint_src_rdata_i  ),
                .core_ld_rvalid_i ( lint_src_rvalid_i ) 
);

dma_dst_ctrl #(
                .DATA_WD          ( DATA_WD           ),
                .ADDR_WD          ( ADDR_WD           ),
                .BE_WD            ( BE_WD             ),
                .LEN_WD           ( LEN_WD            )
) u_dma_dst_ctrl (
                .clk_i            ( clk_i             ),
                .rstn_i           ( rstn_i            ),

                .data_length_i    ( data_length       ),
                .dst_addr_i       ( dst_addr          ),

                .src_done_i       ( src_done          ),
                .dst_idle_o       ( dst_idle          ),

                .buf_rdata_i      ( buf_rdata         ),
                .buf_rvalid_i     ( buf_rvalid        ),
                .buf_rbe_o        ( buf_rbe           ),
                .buf_rready_o     ( buf_rready        ),

                .core_st_req_o    ( lint_dst_req_o    ),
                .core_st_gnt_i    ( lint_dst_gnt_i    ),
                .core_st_we_o     ( lint_dst_we_o     ),
                .core_st_be_o     ( lint_dst_be_o     ),
                .core_st_wdata_o  ( lint_dst_wdata_o  ),
                .core_st_addr_o   ( lint_dst_addr_o   ),
                .core_st_rdata_i  ( lint_dst_rdata_i  ),
                .core_st_rvalid_i ( lint_dst_rvalid_i ) 
);

dma_buf #(
                .DATA_WD          ( DATA_WD           ),
                .ADDR_WD          ( ADDR_WD           ),
                .BE_WD            ( BE_WD             ),
                .LEN_WD           ( LEN_WD            )  
) u_dma_buf (
                .clk_i            ( clk_i             ),
                .rstn_i           ( rstn_i            ),

                .wdata_i          ( buf_wdata         ),
                .wbe_i            ( buf_wbe           ),
                .wvalid_i         ( buf_wvalid        ),
                .wready_o         ( buf_wready        ),

                .rbe_i            ( buf_rbe           ),
                .rready_i         ( buf_rready        ),
                .rdata_o          ( buf_rdata         ),
                .rvalid_o         ( buf_rvalid        )
);

endmodule