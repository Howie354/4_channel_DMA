module syn_fifo #(
    parameter DATA_WD = 8,
    parameter DEPTH   = 16
) (
    input                    clk_i,
    input                    rstn_i,

    input                    wr_valid_i,
    input [DATA_WD - 1 : 0]  wr_data_i,
    output                   wr_ready_o,

    output                   rd_valid_o,
    output [DATA_WD - 1 : 0] rd_data_o,
    input                    rd_ready_i
);
    
    localparam ADDR_WD = $clog2(DEPTH) + 1;

    //flags
    wire fire_in  = wr_valid_i && wr_ready_o;
    wire fire_out = rd_valid_o && rd_ready_i;
    wire full     = (wptr[ADDR_WD - 1] ^ rptr[ADDR_WD - 1]) && (wptr[ADDR_WD - 2 : 0] == rptr[ADDR_WD - 2 : 0]);
    wire empty    = wptr == rptr;

    //wptr,rptr
    reg [ADDR_WD - 1 : 0] wptr;
    reg [ADDR_WD - 1 : 0] rptr;

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            wptr <= 'b0;
        end
        else if(fire_in) begin
            wptr <= wptr + 1'b1;
        end
    end

    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            rptr <= 'b0;
        end
        else if(fire_out) begin
            rptr <= rptr + 1'b1;
        end
    end

    //input & output 
    reg [DATA_WD - 1 : 0] mem [DEPTH - 1 : 0];    
    always @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            
        end
        else if(fire_in) begin
            mem[wptr[ADDR_WD - 2 : 0]] <= wr_data_i;
        end
    end

    assign rd_data_o  = mem[rptr[ADDR_WD - 2 : 0]];
    assign wr_ready_o = !full;
    assign rd_valid_o = !empty;

endmodule