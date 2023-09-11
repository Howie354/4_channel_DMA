//-----register define-----
`define CH_CTRL  'd0 //0x00
`define BD_ADDR  'd1 //0x04
`define BD_CTRL  'd2 //0x08
`define SRC_ADDR 'd3 //0x0c
`define DST_ADDR 'd4 //0x10

//-----bits define-----
`define START_CH 'd0 //from CH_CTRL
`define BD_LAST  'd21 //from BD_CTRL

module dma_ch_rf #(
    parameter ADDR_WD = 32,
    parameter DATA_WD = 32,
    parameter LEN_WD  = 12,
    parameter BE_WD   = DATA_WD / 8
) (
    //-----total-----
    input  wire                   clk_i,
    input  wire                   rstn_i,

    //-----from / to CPU using core bus-----
    input  wire                   core_req_i,
    output wire                   core_gnt_o,
    input  wire                   core_we_i, // write--->1,read--->0
    input  wire [ADDR_WD - 1 : 0] core_addr_i, //include write or read addr
    input  wire [DATA_WD - 1 : 0] core_wdata_i,

    output wire [DATA_WD - 1 : 0] core_rdata_o,
    output wire                   core_rvalid_o,

    //------from / to SRC_CTRL-----
    output wire                   start_ch_req_o,
    input  wire                   start_ch_ack_i,

    output wire [ADDR_WD - 1 : 0] bd_addr_o,
    output wire [ADDR_WD - 1 : 0] src_addr_o,
    output wire [LEN_WD - 1 : 0]  data_length_o,
    output wire                   bd_last_o,

    input wire [BE_WD - 1 : 0]    bd_cs_i,
    input wire [DATA_WD  - 1 : 0] bd_info_i,
    input wire                    bd_update_i,

    //------from / to DST_CTRL-----
    output wire [ADDR_WD - 1 : 0] dst_addr_o
  //output wire [LEN_WD - 1 : 0]  data_length_o
);

    //-----deep 5 width DATA_WD register define----
    reg [DATA_WD - 1 : 0] reg_cs [4 : 0];
    reg [DATA_WD - 1 : 0] reg_ns [4 : 0];

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            for (integer i = 0;i < 5;i = i + 1) begin
                reg_cs[i] <= 'b0;
            end
        end
        else begin
            for (integer j = 0;j < 5;j = j + 1) begin
                reg_cs[j] <= reg_ns[j];
            end
        end
    end

    //------read logic------
    reg [DATA_WD - 1 : 0] core_rdata;
    assign core_rdata_o = core_rdata;
    always @(*) begin
        core_rdata = 'b0;
        case(core_addr_i[ADDR_WD - 1 : 2])
            'd0: begin
                core_rdata = reg_cs[`CH_CTRL];
            end
            'd1: begin
                core_rdata = reg_cs[`BD_ADDR];
            end
            'd2: begin
                core_rdata = reg_cs[`BD_CTRL];
            end
            'd3: begin
                core_rdata = reg_cs[`SRC_ADDR];
            end
            'd4: begin
                core_rdata = reg_cs[`DST_ADDR];
            end
            default: begin
                core_rdata = 'b0;
            end
        endcase    
    end

    reg core_rvalid;
    assign core_rvalid_o = core_rvalid;
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            core_rvalid ='b0;
        end
        if(core_req_i && !core_we_i) begin
            core_rvalid = 1'b1;
        end
        else begin
            core_rvalid = 1'b0;
        end
    end

    //-----write logic-----
    always @(*) begin
        if(start_ch_ack_i) begin
            reg_ns[`CH_CTRL][`START_CH] = 1'b0;
        end
        if(bd_cs_i == 1 && bd_update_i) begin
            reg_ns[`BD_CTRL] = bd_info_i;
        end
        if(bd_cs_i == 2 && bd_update_i) begin
            reg_ns[`SRC_ADDR] = bd_info_i;
        end
        if(bd_cs_i == 3 && bd_update_i) begin
            reg_ns[`DST_ADDR] = bd_info_i;
        end
        if(bd_cs_i == 4 && bd_update_i) begin
            reg_ns[`BD_ADDR] = bd_info_i;
        end
        if(core_req_i && core_we_i) begin //Internal modules take precedence over CPU
            case(core_addr_i[4 : 2])
                'd0: begin
                    reg_ns[`CH_CTRL] = core_wdata_i;
                end
                'd1: begin
                    reg_ns[`BD_ADDR] = core_wdata_i;
                end
            endcase
        end
    end

    //-----output-----
    assign core_gnt_o     = 1'b1; //after the next beat of req_i come
    
    assign start_ch_req_o = reg_cs[`CH_CTRL][`START_CH];
    assign bd_addr_o      = reg_cs[`BD_ADDR];
    assign src_addr_o     = reg_cs[`SRC_ADDR];
    assign data_length_o  = reg_cs[`BD_CTRL][11 : 0];
    assign bd_last_o      = reg_cs[`BD_CTRL][`BD_LAST];
    assign dst_addr_o     = reg_cs[`DST_ADDR];

endmodule