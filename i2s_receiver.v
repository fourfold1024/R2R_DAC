module i2s_receiver (
    input  wire        rst_n,       // 시스템 리셋 (Active Low)
    input  wire        bclk,        // I2S 비트 클럭 (XMOS 제공)
    input  wire        lrck,        // I2S 워드 클럭 (0: Left, 1: Right)
    input  wire        sdata,       // I2S 직렬 데이터 (MSB First)
    
    output reg  [23:0] pcm_l,       // 추출된 24비트 Left 데이터
    output reg  [23:0] pcm_r,       // 추출된 24비트 Right 데이터
    output reg         data_valid   // L/R 데이터 1세트가 모두 모였음을 알리는 플래그
);

    reg        lrck_d;              // 이전 클럭의 LRCK 상태 (엣지 검출용)
    reg [5:0]  bit_cnt;             // 비트 카운터 (0 ~ 63)
    reg [23:0] shift_reg;           // 직렬 데이터를 담아둘 임시 시프트 레지스터

    // BCLK의 상승 엣지(Rising Edge)에서 데이터를 샘플링합니다.
    always @(posedge bclk or negedge rst_n) begin
        if (!rst_n) begin
            lrck_d     <= 1'b0;
            bit_cnt    <= 6'd0;
            shift_reg  <= 24'd0;
            pcm_l      <= 24'd0;
            pcm_r      <= 24'd0;
            data_valid <= 1'b0;
        end else begin
            // 1. LRCK 엣지(변화) 검출
            lrck_d <= lrck;
            data_valid <= 1'b0;     // valid 플래그는 기본적으로 0 유지
            
            if (lrck != lrck_d) begin
                // Left ➔ Right 또는 Right ➔ Left로 채널이 바뀐 순간
                bit_cnt <= 6'd0;    // 카운터 초기화
            end else begin
                // 오버플로우 방지용 카운트 증가
                if (bit_cnt < 6'd63) begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
            
            // 2. I2S 데이터 시프트(Shift)
            // 표준 I2S는 LRCK 엣지 이후 1클럭(bit_cnt==0) 쉬고, 
            // bit_cnt가 1일 때 첫 데이터(MSB)가 들어옵니다.
            // 따라서 bit_cnt가 0 ~ 23일 때 (실제 클럭 사이클로는 1~24번째) 데이터를 밀어 넣습니다.
            if (bit_cnt >= 6'd0 && bit_cnt < 6'd24) begin
                shift_reg <= {shift_reg[22:0], sdata};
            end
            
            // 3. 24비트 래치(Latch) 및 Valid 신호 출력
            if (bit_cnt == 6'd23) begin
                if (lrck_d == 1'b0) begin
                    // LRCK가 0인 구간이 끝났으므로 Left 채널 데이터 완성
                    pcm_l <= {shift_reg[22:0], sdata}; 
                end else begin
                    // LRCK가 1인 구간이 끝났으므로 Right 채널 데이터 완성
                    pcm_r <= {shift_reg[22:0], sdata};
                    
                    // Left와 Right가 모두 갱신되었으므로 FIFO에게 "가져가!" 라고 신호를 보냄
                    data_valid <= 1'b1; 
                end
            end
        end
    end

endmodule