module pcm_consumer (
    input wire clk_slow,      // 처리용 느린 클럭
    input wire rst_n,
    input wire fifo_empty,    // 큐 상태: 비었는가?
    input wire [23:0] data_in,  // FIFO에서 읽어온 데이터
    output reg rdreq          // FIFO 읽기 요청 (Pop)
);

    localparam STATE_IDLE = 2'b00;
    localparam STATE_POP  = 2'b01;
    
    reg [1:0] state;
    reg [23:0] received_data; // 수신 완료된 데이터 보관함

    always @(posedge clk_slow or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            rdreq <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    // 큐에 데이터가 들어오면 읽기 시작
                    if (!fifo_empty) begin
                        rdreq <= 1'b1; // 다음 클럭에 데이터를 뱉어내라고 큐에 요청
                        state <= STATE_POP;
                    end else begin
                        rdreq <= 1'b0;
                    end
                end
                
                STATE_POP: begin
                    if (!fifo_empty) begin
                        // 큐가 계속 차 있다면 계속 읽음 (수신 처리)
                        received_data <= data_in; // 실제 하드웨어 출력핀이나 다음 필터로 넘김
                        rdreq <= 1'b1;
                    end else begin
                        // 큐가 비면 즉시 중단
                        rdreq <= 1'b0;
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end
endmodule