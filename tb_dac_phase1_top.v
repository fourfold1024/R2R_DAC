`timescale 1ns / 1ps

module tb_dac_phase1_top;
    // --- 시스템 입력 신호 (Stimulus) ---
    reg sys_clk;
    reg rst_n;
    reg sel_mode;
    
    // --- XMOS 가상 입력 신호 ---
    reg xmos_bclk;
    reg xmos_lrck;
    reg xmos_data;
    reg xmos_dsd_r;

    // --- 관찰할 출력 핀 (Observation) ---
    wire [23:0] r2r_l_out;
    wire [23:0] r2r_r_out;
    wire        dsd_l_out;
    wire        dsd_r_out;
    wire        relay_ctrl;

    // 1. 테스트할 최상위 모듈 (DUT: Device Under Test) 인스턴스화
    dac_phase1_top uut (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .sel_mode(sel_mode),
        .xmos_bclk(xmos_bclk),
        .xmos_lrck(xmos_lrck),
        .xmos_data(xmos_data),
        .xmos_dsd_r(xmos_dsd_r),
        .r2r_l_out(r2r_l_out),
        .r2r_r_out(r2r_r_out),
        .dsd_l_out(dsd_l_out),
        .dsd_r_out(dsd_r_out),
        .relay_ctrl(relay_ctrl)
    );

    // 2. 클럭 생성부
    initial sys_clk = 0;
    always #10 sys_clk = ~sys_clk; // 50MHz 메인 클럭 (주기 20ns)

    initial xmos_bclk = 0;
    always #160 xmos_bclk = ~xmos_bclk; // 대략 3MHz 비트 클럭 (주기 320ns)

    // 3. I2S 데이터 전송을 위한 자동화 태스크 (가상의 XMOS 역할)
    task send_i2s_word;
        input [23:0] data_l;
        input [23:0] data_r;
        integer i;
        begin
            // [Left Channel 전송]
            xmos_lrck = 1; 
            @(negedge xmos_bclk);
            xmos_lrck = 0; // LRCK 하강 (Left 시작)
            @(negedge xmos_bclk); // I2S 표준 1클럭 딜레이 대기
            
            for(i=23; i>=0; i=i-1) begin
                xmos_data = data_l[i]; // MSB부터 1비트씩 전송
                @(negedge xmos_bclk);
            end
            
            // 남은 8비트 패딩 (32비트 프레임 가정)
            for(i=0; i<8; i=i+1) begin
                xmos_data = 0;
                @(negedge xmos_bclk);
            end

            // [Right Channel 전송]
            xmos_lrck = 1; // LRCK 상승 (Right 시작)
            @(negedge xmos_bclk); // 1클럭 딜레이
            
            for(i=23; i>=0; i=i-1) begin
                xmos_data = data_r[i];
                @(negedge xmos_bclk);
            end
            
            for(i=0; i<8; i=i+1) begin
                xmos_data = 0;
                @(negedge xmos_bclk);
            end
        end
    endtask

    // 4. 메인 테스트 시나리오
    initial begin
        // 초기화
        rst_n = 0;
        sel_mode = 0;
        xmos_lrck = 0;
        xmos_data = 0;
        xmos_dsd_r = 0;
        
        #100;
        rst_n = 1; // 리셋 해제

        // ==========================================
        // 시나리오 1: PCM (R2R) 모드 테스트
        // ==========================================
        $display("=== PCM Mode Test ===");
        sel_mode = 0; // PCM 모드 선택
        
        // 첫 번째 24비트 오디오 샘플 주입 (L: AAAAAA, R: 555555)
        send_i2s_word(24'hAAAAAA, 24'h555555);
        
        // 두 번째 24비트 오디오 샘플 주입 (L: 123456, R: 654321)
        send_i2s_word(24'h123456, 24'h654321);
        
        // FIFO를 거쳐 Consumer가 데이터를 빼내 Router를 통해 출력될 때까지 대기
        #5000; 

        // ==========================================
        // 시나리오 2: DSD (Native) 모드 테스트
        // ==========================================
        $display("=== DSD Mode Test ===");
        sel_mode = 1; // 스위치를 DSD 모드로 전환
        #1000;
        
        // DSD는 I2S 프로토콜(LRCK 딜레이 등)을 무시하고 핀으로 데이터를 마구 쏟아냅니다.
        // xmos_data 핀이 DSD_L 역할을 겸하게 됩니다.
        xmos_data = 1; xmos_dsd_r = 0; #320;
        xmos_data = 0; xmos_dsd_r = 1; #320;
        xmos_data = 1; xmos_dsd_r = 1; #320;
        xmos_data = 0; xmos_dsd_r = 0; #320;

        #2000;
        $display("=== Simulation Completed ===");
        $stop; // 시뮬레이션 종료
    end

endmodule