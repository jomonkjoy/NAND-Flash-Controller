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
  
  always_ff @(posedge clk) begin
    case (state)
      COMMAND1 : IO_O <= cpu_if_command[7:0];
      COMMAND2 : IO_O <= cpu_if_command[15:8];
      ADDRESS  : IO_O <= cpu_if_address[8*count[2:0] +: 8];
      DATA_WR  : IO_O <= buf_wr_read_data[8*count[2:0] +: 8];
    endcase
  end
  
  logic [DATA_WIDTH-1:0] IO_i;
  always_ff @(posedge clk) begin
    if (state == DATA_RD && RB_N && RE_N) begin
      IO_i <= {IO_I,IO_i[DATA_WIDTH-1:8]};
    end
  end
  
  always_ff @(posedge clk) begin
    if (state == ADDRESS || state == COMMAND1 || state == COMMAND2 || state == DATA_WR || state == DONE) begin
      IO_OE <= 1'b1;
    end else begin
      IO_OE <= 1'b0;
    end
  end
  
  always_ff @(posedge clk) begin
    if (state == IDLE) begin
      buf_wr_address <= {ADDR_WIDTH{1'b0}};
    end else if (RB_N && WE_N && state == DATA_WR) begin
      buf_wr_address <= buf_wr_address + 1;
    end
  end
  
  assign buf_rd_write = state == DATA_RD && RE_N && RB_N && count[1:0] == 2'b11;
  assign buf_rd_address = {'h0,count[COUNT_WIDTH-1:2]};
  assign buf_rd_write_data = {IO_I,IO_i[DATA_WIDTH-1:8]};
  
  assign cpu_if_access_complete = state == DONE;
  
  always_ff @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      count <= 0;
      cpu_if_access_ready <= 1'b0;
    end else begin
      case (state)
        IDLE : begin
          if (cpu_if_access_ready && cpu_if_access_request) begin
            state <= COMMAND1;
            cpu_if_access_ready <= 1'b0;
          end else begin
            cpu_if_access_ready <= 1'b1;
          end
        end
        COMMAND1 : begin
          if (~WE_N && cpu_if_address_bytes != 0) begin
            state <= ADDRESS;
          end else if (~WE_N) begin
            state <= DONE;
          end
        end
        COMMAND2 : begin
          if (~WE_N && cpu_if_data_bytes != 0) begin
            state <= cpu_if_data_rw ? DATA_RD : DATA_WR;
          end else if (~WE_N) begin
            state <= DONE;
          end
        end
        ADDRESS : begin
          if (~WE_N && count[ADDR_WIDTH/8-1:0] >= cpu_if_address_bytes && cpu_if_command_valid) begin
            state <= COMMAND2;
            count <= 0;
          end else if (~WE_N && count[ADDR_WIDTH/8-1:0] >= cpu_if_address_bytes && cpu_if_data_bytes != 0) begin
            state <= cpu_if_data_rw ? DATA_RD : DATA_WR;
            count <= 0;
          end else if (~WE_N && count[ADDR_WIDTH/8-1:0] >= cpu_if_address_bytes) begin
            state <= DONE;
            count <= 0;
          end else if (~WE_N) begin
            count <= count + 1;
          end
        end
        DATA_WR : begin
          if (~WE_N && count >= cpu_if_data_bytes[COUNT_WIDTH-1:0]) begin
            state <= DONE;
            count <= 0;
          end else if (~WE_N) begin
            count <= count + 1;
          end
        end
        DATA_RD : begin
          if (~RE_N && count >= cpu_if_data_bytes[COUNT_WIDTH-1:0]) begin
            state <= DONE;
            count <= 0;
          end else if (~RE_N) begin
            count <= count + 1;
          end
        end
        DONE : begin
          state <= IDLE;
          cpu_if_access_ready <= 1'b1;
        end
        default : state <= IDLE;
      endcase
    end
  end
  
endmodule
