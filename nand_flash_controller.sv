module nand_flash_controller #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 32,
  parameter CMND_WIDTH = 16,
  parameter BYTE_PER_PAGE = 2048,
  parameter PAGE_PER_BLOCK = 64,
  parameter BLOCK_SIZE = 2048 // 2Gb NAND-FLASH
) (
  input  logic                    clk,
  input  logic                    reset,
  
  output logic                    CE_N,
  output logic                    WE_N,
  output logic                    RE_N,
  output logic                    CLE,
  output logic                    ALE,
  input  logic [7:0]              IO_I,
  output logic [7:0]              IO_O,
  output logic                    IO_OE,
  output logic                    WP_N,
  input  logic                    RB_N,
  
  input  logic [CMND_WIDTH-1:0]   cpu_if_command,
  input  logic                    cpu_if_command_valid,
  input  logic [ADDR_WIDTH-1:0]   cpu_if_address,
  input  logic [ADDR_WIDTH/8-1:0] cpu_if_address_bytes,
  input  logic [ADDR_WIDTH-1:0]   cpu_if_data_bytes,
  input  logic                    cpu_if_data_rw,
  input  logic                    cpu_if_data_wp,
  input  logic                    cpu_if_access_request,
  output logic                    cpu_if_access_complete,
  output logic                    cpu_if_access_ready,
  
  output logic                    buf_rd_write,
  output logic [ADDR_WIDTH-1:0]   buf_rd_address,
  output logic [DATA_WIDTH-1:0]   buf_rd_write_data,
  output logic [ADDR_WIDTH-1:0]   buf_wr_address,
  input  logic [DATA_WIDTH-1:0]   buf_wr_read_data,
  
  output logic                    busy
);

  localparam COUNT_WIDTH = $clog2(BYTE_PER_PAGE);
  logic [COUNT_WIDTH-1:0] count;
  
  typedef enum {IDLE,COMMAND1,COMMAND2,ADDRESS,DATA_WR,DATA_RD,DONE} state_type;
  state_type state;
  
  assign busy = !(state == IDLE);
  assign WP_N = !cpu_if_data_wp;
  
  always_ff @(posedge clk) begin
    if (reset) begin
      CE_N <= 1'b1;
    end else begin
      CE_N <= state == IDLE;
    end
  end
  
  always_ff @(posedge clk) begin
    if (reset) begin
      CLE <= 1'b0;
    end else begin
      CLE <= state == COMMAND1 || state == COMMAND2;
    end
  end
  
  always_ff @(posedge clk) begin
    if (reset) begin
      ALE <= 1'b0;
    end else begin
      ALE <= state == ADDRESS;
    end
  end
  
  always_ff @(posedge clk) begin
    if (reset) begin
      WE_N <= 1'b1;
    end else if (RB_N && WE_N && (state == ADDRESS || state == COMMAND1 || state == COMMAND2 || state == DATA_WR)) begin
      WE_N <= 1'b0;
    end else begin
      WE_N <= 1'b1;
    end
  end
  
  always_ff @(posedge clk) begin
    if (reset) begin
      RE_N <= 1'b1;
    end else if (RB_N && RE_N && (state == DATA_RD)) begin
      RE_N <= 1'b0;
    end else begin
      RE_N <= 1'b1;
    end
  end
  
endmodule
