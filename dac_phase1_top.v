module dac_phase1_top (
    // --- 시스템 기본 핀 ---
    input  wire        sys_clk,       // 보드 메인 클럭 (예: 50MHz)
    input  wire        rst_n,         // 리셋 스위치 (Active Low)
    
    // --- 유저 제어 핀 ---
    input  wire        sel_mode,      // 0: PCM (R2R) 모드, 1: DSD 모드
    
    // --- XMOS XU316 입력 핀 ---
    input  wire        xmos_bclk,     // 비트 클럭 (DSD 클럭 공용)
    input  wire        xmos_lrck,     // 워드 클럭 (PCM 좌우 구분)
    input  wire        xmos_data,     // PCM 직렬 데이터 (또는 DSD_L)
    input  wire		  xmos_dsd_r,
    
    // --- 최종 아날로그 출력 핀 (만능기판 연결용) ---
    output wire [23:0] r2r_l_out,     // 좌측 24비트 R2R 출력
    output wire [23:0] r2r_r_out,     // 우측 24비트 R2R 출력
    output wire        dsd_l_out,     // 좌측 DSD LPF 출력
    output wire        dsd_r_out,     // 우측 DSD LPF 출력
    
    // --- 릴레이 제어 핀 ---
    output wire        relay_ctrl     // 아날로그 경로 전환 스위칭 신호
);

    // ========================================================
    // 내부 와이어 (Internal Wires) 선언
    // ========================================================
    
    // I2S Receiver -> FIFO 연결용 와이어
    wire [23:0] i2s_pcm_l;
    wire [23:0] i2s_pcm_r;
    wire        i2s_valid; // 24비트 데이터가 모였을 때 뜨는 플래그
    
    // FIFO -> Consumer 연결용 와이어
    wire [47:0] fifo_rdata; // L(24) + R(24) 합쳐서 48비트
    wire        fifo_empty;
    wire        fifo_rinc;  // Consumer가 FIFO에서 데이터를 읽겠다는 신호
    

    // ========================================================
    // 1. I2S 수신부 (직렬 -> 24비트 병렬 변환)
    // ========================================================
    // XMOS의 직렬 PCM 데이터를 받아 24비트 병렬 데이터로 모아줍니다.
    // (이 모듈은 향후 코딩이 필요합니다.)
     
    i2s_receiver u_i2s_rx (
        .rst_n      (rst_n),
        .bclk       (xmos_bclk),
        .lrck       (xmos_lrck),
        .sdata      (xmos_data),
        .pcm_l      (i2s_pcm_l),
        .pcm_r      (i2s_pcm_r),
        .data_valid (i2s_valid)
    );
    

    // ========================================================
    // 2. 비동기 FIFO 큐 (Left / Right 개별 인스턴스화)
    // ========================================================
    wire [23:0] fifo_q_l, fifo_q_r;
    wire fifo_empty_l, fifo_empty_r;
    
    // 두 FIFO 중 하나라도 비어있으면 empty 상태로 취급
    assign fifo_empty = fifo_empty_l | fifo_empty_r; 
    assign fifo_rdata = {fifo_q_l, fifo_q_r};

    // 좌측(Left) 채널용 FIFO
    asyn_fifo u_fifo_left (
        .data    (i2s_pcm_l),    // 쓰기 데이터 (24-bit)
        .wrclk   (xmos_bclk),    // 쓰기 클럭
        .wrreq   (i2s_valid),    // 쓰기 요청
        .wrfull  (),             // (사용 안 함)
        
        .rdclk   (sys_clk),      // 읽기 클럭
        .rdreq   (fifo_rinc),    // 읽기 요청
        .q       (fifo_q_l),     // 읽기 데이터 (24-bit)
        .rdempty (fifo_empty_l)  // 비어있음 플래그
    );

    // 우측(Right) 채널용 FIFO
    asyn_fifo u_fifo_right (
        .data    (i2s_pcm_r),    // 쓰기 데이터 (24-bit)
        .wrclk   (xmos_bclk),    // 쓰기 클럭
        .wrreq   (i2s_valid),    // 쓰기 요청
        .wrfull  (),             // (사용 안 함)
        
        .rdclk   (sys_clk),      // 읽기 클럭
        .rdreq   (fifo_rinc),    // 읽기 요청
        .q       (fifo_q_r),     // 읽기 데이터 (24-bit)
        .rdempty (fifo_empty_r)  // 비어있음 플래그
    );
// ========================================================
// 3. PCM Consumer (FSM 상태 기계 - FIFO 읽기 제어용)
// ========================================================
// 출력 핀이 없으므로 FIFO에서 데이터를 읽어내는(rdreq) 컨트롤러 역할만 수행합니다.
pcm_consumer u_consumer (
    .clk_slow   (sys_clk),       // clk ➔ clk_slow 매핑
    .rst_n      (rst_n),
    .fifo_empty (fifo_empty),    // 좌/우 FIFO 중 하나라도 비면 멈춤
    .data_in    (fifo_q_l),      // 24비트만 받으므로 좌측 데이터만 연결 (모니터링용)
    .rdreq      (fifo_rinc)      // 이 신호가 두 FIFO의 데이터를 동시에 뽑아냅니다.
);

// ========================================================
// 4. Dual Path Router (PCM / DSD 경로 분기)
// ========================================================
dual_path_router u_router (
    .clk        (sys_clk),
    .rst_n      (rst_n),
    .sel_mode   (sel_mode),      // <--- 나중에 XMOS Pin 7(DSD ON)과 연결!
        
    .pcm_l_in   (fifo_q_l),      
    .pcm_r_in   (fifo_q_r),      
    .dsd_l_in   (xmos_data),     // Pin 3: I2S DATA / DSD LEFT
    .dsd_r_in   (xmos_lrck),     // Pin 5: I2S LRCK / DSD RIGHT (이 부분 수정!)
    
    .r2r_l_out  (r2r_l_out),
    .r2r_r_out  (r2r_r_out),
    .dsd_l_out  (dsd_l_out),
    .dsd_r_out  (dsd_r_out),
    .relay_ctrl (relay_ctrl)
);
endmodule