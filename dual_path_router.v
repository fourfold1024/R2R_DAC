module dual_path_router (
    input  wire        clk,         // 시스템 마스터 클럭
    input  wire        rst_n,       // 리셋 (Active Low)
    
    // --- 제어 신호 ---
    input  wire        sel_mode,    // 0: PCM (R2R) 모드, 1: DSD (Native) 모드
    
    // --- 내부 데이터 입력 (이전 모듈에서 넘어온 신호) ---
    input  wire [23:0] pcm_l_in,    // FIFO/필터를 거친 24비트 PCM 좌측 데이터
    input  wire [23:0] pcm_r_in,    // FIFO/필터를 거친 24비트 PCM 우측 데이터
    input  wire        dsd_l_in,    // XMOS에서 직결된 1비트 DSD 좌측 데이터
    input  wire        dsd_r_in,    // XMOS에서 직결된 1비트 DSD 우측 데이터
    
    // --- 외부 핀 출력 (보드 바깥으로 나가는 신호) ---
    output reg  [23:0] r2r_l_out,   // 좌측 R2R 저항 래더 24핀 출력
    output reg  [23:0] r2r_r_out,   // 우측 R2R 저항 래더 24핀 출력
    output reg         dsd_l_out,   // 좌측 DSD LPF 1핀 출력
    output reg         dsd_r_out,   // 우측 DSD LPF 1핀 출력
    
    // --- 아날로그 릴레이 제어 ---
    output reg         relay_ctrl   // 0: R2R 출력단 연결, 1: DSD 출력단 연결
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 리셋 시 모든 출력 핀을 0으로 초기화 (팝노이즈 방지)
            r2r_l_out  <= 24'd0;
            r2r_r_out  <= 24'd0;
            dsd_l_out  <= 1'b0;
            dsd_r_out  <= 1'b0;
            relay_ctrl <= 1'b0;
        end else begin
            if (sel_mode == 1'b1) begin
                // ==========================================
                // [다이렉트 DSD 모드]
                // ==========================================
                dsd_l_out  <= dsd_l_in;       // DSD 신호 패스스루
                dsd_r_out  <= dsd_r_in;
                
                r2r_l_out  <= 24'd0;          // PCM 출력 핀은 완전히 0으로 고정(Mute)
                r2r_r_out  <= 24'd0;          // R2R 저항망에 노이즈가 타는 것을 방지
                
                relay_ctrl <= 1'b1;           // 릴레이를 DSD LPF 회로 쪽으로 '딸깍' 전환
                
            end else begin
                // ==========================================
                // [PCM R2R 모드]
                // ==========================================
                r2r_l_out  <= pcm_l_in;       // 24비트 PCM 신호 출력
                r2r_r_out  <= pcm_r_in;
                
                dsd_l_out  <= 1'b0;           // DSD 출력 핀은 완전히 0으로 고정(Mute)
                dsd_r_out  <= 1'b0;
                
                relay_ctrl <= 1'b0;           // 릴레이를 R2R 회로 쪽으로 전환
            end
        end
    end

endmodule