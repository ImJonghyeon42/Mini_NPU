#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xuartlite_l.h"
#include "sleep.h"
#include "xil_types.h"

/* ================= UART 설정 ================= */
#ifndef UARTB
  #if defined(XPAR_AXI_UARTLITE_1_BASEADDR)
    #define UARTB XPAR_AXI_UARTLITE_1_BASEADDR
  #elif defined(XPAR_UARTLITE_1_BASEADDR)
    #define UARTB XPAR_UARTLITE_1_BASEADDR
  #else
    #define UARTB STDIN_BASEADDRESS
  #endif
#endif

static inline void uart_putc(char c){ XUartLite_SendByte(UARTB, (u8)c); }
static void uart_puts(const char *s){ while(*s) uart_putc(*s++); }
static void uart_flush_rx(void){ while(!XUartLite_IsReceiveEmpty(UARTB)) (void)XUartLite_RecvByte(UARTB); }

/* ================= CNN AXI Lite 레지스터 맵 ================= */
#define CNN_BASE_ADDR    XPAR_CNN_AXI_LITE_WRAPPER_0_BASEADDR  // Vivado에서 할당될 주소

// AXI Lite 레지스터 오프셋 (CNN_AXI_Lite_Wrapper와 일치)
#define REG_CONTROL      0x00    // 제어 레지스터
#define REG_STATUS       0x04    // 상태 레지스터
#define REG_RESULT_LOW   0x08    // CNN 결과 하위 32비트
#define REG_RESULT_HIGH  0x0C    // CNN 결과 상위 16비트  
#define REG_FRAME_COUNT  0x10    // 처리된 프레임 수
#define REG_ERROR_CODE   0x14    // 오류 코드

// 상태 레지스터 비트 정의
#define STATUS_CNN_BUSY     (1 << 0)   // CNN 처리 중
#define STATUS_RESULT_VALID (1 << 1)   // 결과 유효
#define STATUS_SPI_COMPLETE (1 << 2)   // SPI 프레임 완료

/* ================= PWM 및 초음파 설정 (기존 유지) ================= */
#define PWM_BASE   XPAR_DCMOTOR_MYIP_V1_0_BASEADDR
#define REG_EN     0x00
#define REG_DIR    0x04
#define REG_DUTY   0x08

#define UL_F   XPAR_ULTRASONIC_MYIP_V1_0_0_BASEADDR
#define UL_R   XPAR_ULTRASONIC_MYIP_V1_0_1_BASEADDR
#define UL_L   XPAR_ULTRASONIC_MYIP_V1_0_2_BASEADDR

/* ================= CNN 파라미터 (업데이트) ================= */
#define CNN_TIMEOUT_MS      100     // CNN 결과 대기 최대 시간
#define CNN_OUTPUT_SCALE    2048    // 추출된 가중치 기반 스케일링
#define CNN_STEER_MAX       80      // 최대 조향각

/* CNN 패턴 정의 */
#define CNN_PATTERN_STRAIGHT    0
#define CNN_PATTERN_LEFT_CURVE  1  
#define CNN_PATTERN_RIGHT_CURVE 2
#define CNN_PATTERN_START_END   3

/* ================= 기존 모터 제어 파라미터 (유지) ================= */
#define DUTY_MIN_MOVE   30
#define DUTY_MIN_TURN   14
#define DUTY_MAX       100
#define KICK_DUTY       70
#define KICK_MS        120
#define DEAD_US        150
#define SPIN_PWM        80
#define STEER_SIGN     (-1)
#define AUTO_BASE_PCT   50
#define WALL_CM        50
#define PANIC_CM       18
#define STEER_K        22
#define NEAR_BOOST_CM  35
#define STEER_BOOST     2
#define FRONT_SLOW1_CM  85
#define FRONT_SLOW2_CM  50
#define FRONT_SLOW1_PCT 40
#define FRONT_SLOW2_PCT 30
#define BACKUP_MS      800
#define BACKUP_PCT      55

/* ================= 채널/차륜 매핑 (기존 유지) ================= */
#define CH_FR 0
#define CH_FL 1
#define CH_RL 2
#define CH_RR 3
static const u8 MOTOR_INV[4] = { 1, 0, 1, 0 };

/* ================= 상태 변수 ================= */
static int  speed_pct = DUTY_MIN_MOVE;
static int  steer     = 0;
static char last_mode = 'X';
static int  auto_mode = 0;
static int  cnn_active = 0;
static s32  last_cnn_result = 0;
static int  cnn_pattern = -1;
static int  cnn_timeout_count = 0;
static int prev_dutyL = -1, prev_dutyR = -1;

/* ================= AXI Lite 헬퍼 함수 ================= */

/**
 * AXI Lite 레지스터 읽기
 */
static inline u32 axi_read_reg(u32 offset) {
    return Xil_In32(CNN_BASE_ADDR + offset);
}

/**
 * AXI Lite 레지스터 쓰기
 */
static inline void axi_write_reg(u32 offset, u32 value) {
    Xil_Out32(CNN_BASE_ADDR + offset, value);
}

/**
 * CNN 상태 확인
 */
static int cnn_is_busy(void) {
    u32 status = axi_read_reg(REG_STATUS);
    return (status & STATUS_CNN_BUSY) ? 1 : 0;
}

/**
 * CNN 결과 유효성 확인
 */
static int cnn_result_available(void) {
    u32 status = axi_read_reg(REG_STATUS);
    return (status & STATUS_RESULT_VALID) ? 1 : 0;
}

/**
 * 처리된 프레임 수 읽기
 */
static u32 cnn_get_frame_count(void) {
    return axi_read_reg(REG_FRAME_COUNT);
}

/* ================= CNN 전용 함수 (AXI Lite 기반) ================= */

/**
 * CNN 초기화
 */
static void cnn_init(void) {
    // 제어 레지스터 초기화
    axi_write_reg(REG_CONTROL, 0x00);
    usleep(1000);
    
    xil_printf("[CNN] AXI Lite 인터페이스 초기화 완료\r\n");
    xil_printf("[CNN] Base Address: 0x%08lx\r\n", (unsigned long)CNN_BASE_ADDR);
    
    // 상태 확인
    u32 status = axi_read_reg(REG_STATUS);
    xil_printf("[CNN] 초기 상태: 0x%08lx\r\n", (unsigned long)status);
}

/**
 * CNN 48비트 결과를 조향각으로 변환 (AXI Lite 기반)
 */
static s32 cnn_read_steering_angle(void) {
    // 1. 결과 유효성 확인
    if (!cnn_result_available()) {
        return 0;  // 결과 없음
    }
    
    // 2. 48비트 CNN 결과 읽기 (AXI Lite)
    u32 result_low = axi_read_reg(REG_RESULT_LOW);
    u32 result_high = axi_read_reg(REG_RESULT_HIGH) & 0xFFFF;
    
    // 3. 48비트 조합
    s64 raw_result = ((s64)result_high << 32) | result_low;
    
    // 4. 조향각 변환 (추출된 가중치 기반)
    s32 steering_angle = (s32)(raw_result / CNN_OUTPUT_SCALE);
    
    // 5. 조향각 제한
    steering_angle = clamp(steering_angle, -CNN_STEER_MAX, CNN_STEER_MAX);
    
    return steering_angle;
}

/**
 * CNN 패턴 분류 (업데이트된 임계값)
 */
static int cnn_classify_pattern(s32 result) {
    int abs_result = (result < 0) ? -result : result;
    
    if (abs_result < 8) {
        return CNN_PATTERN_STRAIGHT;
    } else if (result > 25) {
        return CNN_PATTERN_LEFT_CURVE;
    } else if (result < -25) {
        return CNN_PATTERN_RIGHT_CURVE;
    } else {
        return CNN_PATTERN_START_END;
    }
}

/**
 * CNN 기반 조향 로직
 */
static int cnn_apply_steering_logic(s32 cnn_steer) {
    cnn_pattern = cnn_classify_pattern(cnn_steer);
    
    switch (cnn_pattern) {
        case CNN_PATTERN_STRAIGHT:
            return cnn_steer;
            
        case CNN_PATTERN_LEFT_CURVE:
            return clamp(cnn_steer + 3, -CNN_STEER_MAX, CNN_STEER_MAX);
            
        case CNN_PATTERN_RIGHT_CURVE:
            return clamp(cnn_steer - 3, -CNN_STEER_MAX, CNN_STEER_MAX);
            
        case CNN_PATTERN_START_END:
            return cnn_steer / 2;
            
        default:
            return 0;
    }
}

/**
 * CNN 시스템 상태 체크
 */
static void cnn_system_status(void) {
    u32 status = axi_read_reg(REG_STATUS);
    u32 frame_count = axi_read_reg(REG_FRAME_COUNT);
    u32 error_code = axi_read_reg(REG_ERROR_CODE);
    
    xil_printf("[CNN_STATUS] Status: 0x%08lx\r\n", (unsigned long)status);
    xil_printf("[CNN_STATUS] Frames: %lu\r\n", (unsigned long)frame_count);
    xil_printf("[CNN_STATUS] Errors: %lu\r\n", (unsigned long)error_code);
    xil_printf("[CNN_STATUS] Busy: %s\r\n", (status & STATUS_CNN_BUSY) ? "YES" : "NO");
    xil_printf("[CNN_STATUS] Result: %s\r\n", (status & STATUS_RESULT_VALID) ? "VALID" : "NONE");
}

/* ================= 기존 모터 제어 함수들 (유지) ================= */

static inline u8 apply_inv_to_dir_bits(u8 dir_bits){
    u8 d=0;
    for(int ch=0; ch<4; ++ch){
        u8 bit = (dir_bits>>ch)&1u;
        if (MOTOR_INV[ch]) bit ^= 1u;
        d |= (bit<<ch);
    }
    return d & 0x0F;
}

static inline u32 pack_duty(u8 d0,u8 d1,u8 d2,u8 d3){
    d0=clamp(d0,0,100); d1=clamp(d1,0,100); d2=clamp(d2,0,100); d3=clamp(d3,0,100);
    return ((u32)d3<<24)|((u32)d2<<16)|((u32)d1<<8)|((u32)d0);
}

static void set_all(u8 en_mask, u8 dir_rev_mask1bit, u8 d0,u8 d1,u8 d2,u8 d3){
    Xil_Out32(PWM_BASE + REG_EN, 0x0);
    usleep(DEAD_US);
    u8 dir_hw = apply_inv_to_dir_bits(dir_rev_mask1bit & 0x0F);
    Xil_Out32(PWM_BASE + REG_DIR,  dir_hw);
    Xil_Out32(PWM_BASE + REG_DUTY, pack_duty(d0,d1,d2,d3));
    Xil_Out32(PWM_BASE + REG_EN,   en_mask & 0x0F);
}

static inline int min_nonzero(int a, int b){
    if (a==0) return b;
    if (b==0) return a;
    return (a<b)?a:b;
}

static void compute_lr_duty(int base, int st, int *L, int *R){
    int s = st * STEER_SIGN;
    int l = (base*(100 + s))/100;
    int r = (base*(100 - s))/100;
    l = clamp(l,0,DUTY_MAX);
    r = clamp(r,0,DUTY_MAX);
    if (l >= r){
        if (l>0 && l<DUTY_MIN_MOVE) l = DUTY_MIN_MOVE;
        if (r>0 && r<DUTY_MIN_TURN) r = DUTY_MIN_TURN;
    }else{
        if (r>0 && r<DUTY_MIN_MOVE) r = DUTY_MIN_MOVE;
        if (l>0 && l<DUTY_MIN_TURN) l = DUTY_MIN_TURN;
    }
    *L=l; *R=r;
}

static void map_lr_to_duty(int dutyL,int dutyR,u8 *d0,u8 *d1,u8 *d2,u8 *d3){
    u8 duty[4]={0,0,0,0};
    duty[CH_RL]=(u8)dutyL;
    duty[CH_FL]=(u8)dutyL;
    duty[CH_RR]=(u8)dutyR;
    duty[CH_FR]=(u8)dutyR;
    *d0=duty[0]; *d1=duty[1]; *d2=duty[2]; *d3=duty[3];
}

static void stop_all(void){ 
    Xil_Out32(PWM_BASE + REG_EN, 0x0); 
    last_mode='X'; 
    auto_mode=0; 
    cnn_active=0; 
}

static void drive_lr_sync(u8 dirL_revbit, u8 dirR_revbit, int dutyL, int dutyR){
    dutyL = clamp(dutyL,0,DUTY_MAX);
    dutyR = clamp(dutyR,0,DUTY_MAX);
    int delta_ok = 1;
    if (prev_dutyL>=0 && prev_dutyR>=0){
        int dL = (dutyL>prev_dutyL)? (dutyL-prev_dutyL) : (prev_dutyL-dutyL);
        int dR = (dutyR>prev_dutyR)? (dutyR-prev_dutyR) : (prev_dutyR-dutyR);
        if (dL < 2 && dR < 2) delta_ok = 0;
    }
    if (!delta_ok) return;
    u8 d0,d1,d2,d3; map_lr_to_duty(dutyL,dutyR,&d0,&d1,&d2,&d3);
    u8 dir_bits = 0;
    if (dirL_revbit){ dir_bits |= (1<<CH_RL); dir_bits |= (1<<CH_FL); }
    if (dirR_revbit){ dir_bits |= (1<<CH_RR); dir_bits |= (1<<CH_FR); }
    int need_kick = (last_mode=='X') || (dutyL<=DUTY_MIN_TURN) || (dutyR<=DUTY_MIN_TURN);
    if (need_kick && (dutyL>0 || dutyR>0)){
        u8 kd0,kd1,kd2,kd3; map_lr_to_duty(KICK_DUTY,KICK_DUTY,&kd0,&kd1,&kd2,&kd3);
        set_all(0x0F, dir_bits, kd0,kd1,kd2,kd3);
        usleep(KICK_MS*1000);
    }
    set_all(0x0F, dir_bits, d0,d1,d2,d3);
    prev_dutyL = dutyL;
    prev_dutyR = dutyR;
}

static void spin_with_rear_fix(int left) {
    u8 d0,d1,d2,d3;
    map_lr_to_duty(SPIN_PWM, SPIN_PWM, &d0,&d1,&d2,&d3);
    u8 dir_bits = 0;
    if (left){
        dir_bits |= (1<<CH_FL);
        dir_bits |= (1<<CH_RR);
    }else{
        dir_bits |= (1<<CH_FR);
        dir_bits |= (1<<CH_RL);
    }
    int need_kick = (last_mode=='X');
    if (need_kick){
        u8 kd0,kd1,kd2,kd3; map_lr_to_duty(KICK_DUTY, KICK_DUTY, &kd0,&kd1,&kd2,&kd3);
        set_all(0x0F, dir_bits, kd0,kd1,kd2,kd3);
        usleep(KICK_MS*1000);
    }
    set_all(0x0F, dir_bits, d0,d1,d2,d3);
}

static void go_forward_curved(void){
    int L,R; compute_lr_duty(speed_pct, steer, &L, &R);
    drive_lr_sync(0,0,L,R); last_mode='W';
}
static void go_backward_curved(void){
    int L,R; compute_lr_duty(speed_pct, steer, &L, &R);
    drive_lr_sync(1,1,L,R); last_mode='S';
}
static void turn_left_spin(void){  spin_with_rear_fix(1); last_mode='A'; }
static void turn_right_spin(void){ spin_with_rear_fix(0); last_mode='D'; }

static void reapply_motion(void){
    switch (last_mode){
        case 'W': go_forward_curved();  break;
        case 'S': go_backward_curved(); break;
        case 'A': turn_left_spin();     break;
        case 'D': turn_right_spin();    break;
        default: break;
    }
}

/* ================= 초음파 읽기 (기존 유지) ================= */
static inline u32 ultra_read_once(u32 base){
    u32 ones = Xil_In32(base + 0x00) & 0xF;
    u32 tens = Xil_In32(base + 0x04) & 0xF;
    return tens*10 + ones;
}

static u32 ultra_read_avg(u32 base, int n){
    u32 sum=0, cnt=0;
    for(int i=0;i<n;i++){
        u32 v = ultra_read_once(base);
        if(v>0 && v<=400){ sum+=v; cnt++; }
        usleep(1000);
    }
    return (cnt? sum/cnt : 0);
}

/* ================= CNN + 초음파 융합 자율주행 (AXI Lite 기반) ================= */
static void auto_step_with_cnn(void){
    /* 1) 초음파 센서 읽기 */
    u32 F = ultra_read_avg(UL_F, 3);
    u32 R = ultra_read_avg(UL_R, 3);
    u32 L = ultra_read_avg(UL_L, 3);

    /* 2) 비상상황: 전방 근접 시 기존 로직 우선 */
    if (F>0 && F<=PANIC_CM){
        int left_more_space = (L >= R);
        int save_spd = speed_pct, save_st = steer;
        speed_pct = BACKUP_PCT;
        steer = 0;
        go_backward_curved();
        usleep(BACKUP_MS * 1000);
        if (left_more_space) turn_left_spin();
        else                 turn_right_spin();
        for(int i=0;i<10 && auto_mode;i++) usleep(100000);
        speed_pct = AUTO_BASE_PCT;
        steer = 0;
        go_forward_curved();
        return;
    }

    /* 3) 전방 감속 */
    if      (F>0 && F<FRONT_SLOW2_CM) speed_pct = FRONT_SLOW2_PCT;
    else if (F>0 && F<FRONT_SLOW1_CM) speed_pct = FRONT_SLOW1_PCT;
    else                              speed_pct = AUTO_BASE_PCT;

    /* 4) 조향 결정: CNN vs 초음파 융합 */
    int final_steer = 0;
    
    if (cnn_active) {
        /* CNN 결과 읽기 (AXI Lite) */
        s32 cnn_steer = cnn_read_steering_angle();
        
        if (cnn_steer != 0) {
            /* CNN 결과 가공 */
            int processed_cnn_steer = cnn_apply_steering_logic(cnn_steer);
            last_cnn_result = processed_cnn_steer;
            cnn_timeout_count = 0;
            
            /* 초음파 장애물 회피 */
            int obstacle_steer = 0;
            if (R>0 && R<=WALL_CM) obstacle_steer +=  (WALL_CM - (int)R) * STEER_K;
            if (L>0 && L<=WALL_CM) obstacle_steer += -(WALL_CM - (int)L) * STEER_K;

            int side_near = min_nonzero((int)R, (int)L);
            if (side_near>0 && side_near <= NEAR_BOOST_CM){
                obstacle_steer *= STEER_BOOST;
            }
            
            /* 융합 제어 로직 */
            if (abs(obstacle_steer) > 20) {
                final_steer = clamp(obstacle_steer, -80, 80);
            } else if (abs(obstacle_steer) > 10) {
                final_steer = clamp((obstacle_steer * 2 + processed_cnn_steer) / 3, -80, 80);
            } else {
                final_steer = clamp(processed_cnn_steer, -80, 80);
            }
            
        } else {
            /* CNN 결과 없음 → 타임아웃 처리 */
            cnn_timeout_count++;
            if (cnn_timeout_count > 10) {
                int s = 0;
                if (R>0 && R<=WALL_CM) s +=  (WALL_CM - (int)R) * STEER_K;
                if (L>0 && L<=WALL_CM) s += -(WALL_CM - (int)L) * STEER_K;
                
                int side_near = min_nonzero((int)R, (int)L);
                if (side_near>0 && side_near <= NEAR_BOOST_CM){
                    s *= STEER_BOOST;
                }
                final_steer = clamp(s, -80, +80);
                last_cnn_result = last_cnn_result * 9 / 10;
            } else {
                final_steer = last_cnn_result;
            }
        }
    } else {
        /* CNN 비활성 → 기존 초음파 로직 */
        int s = 0;
        if (R>0 && R<=WALL_CM) s +=  (WALL_CM - (int)R) * STEER_K;
        if (L>0 && L<=WALL_CM) s += -(WALL_CM - (int)L) * STEER_K;

        int side_near = min_nonzero((int)R, (int)L);
        if (side_near>0 && side_near <= NEAR_BOOST_CM){
            s *= STEER_BOOST;
        }
        final_steer = clamp(s, -80, +80);
    }
    
    steer = final_steer;

    /* 5) 최종 적용 */
    go_forward_curved();

    /* 6) 디버깅 출력 */
    static int dbg=0; if(++dbg>=10){ dbg=0;
        const char* pattern_names[] = {"직선", "좌곡선", "우곡선", "시작종료"};
        const char* current_pattern = (cnn_pattern >= 0 && cnn_pattern < 4) ? 
                                    pattern_names[cnn_pattern] : "알수없음";
        
        if (cnn_active) {
            xil_printf("[AUTO+CNN] F=%lu R=%lu L=%lu | SPD=%d STEER=%d | CNN=%d(%s) TO=%d\r\n",
                       (unsigned long)F, (unsigned long)R, (unsigned long)L,
                       speed_pct, steer, (int)last_cnn_result, current_pattern, cnn_timeout_count);
        } else {
            xil_printf("[AUTO] F=%lu R=%lu L=%lu | SPD=%d STEER=%d\r\n",
                       (unsigned long)F, (unsigned long)R, (unsigned long)L,
                       speed_pct, steer);
        }
    }
}

/* ================= C 파서 및 기타 함수들 (기존 유지) ================= */
typedef struct { int state,s1,n1,got1,s2,n2,got2; } CParser;
static CParser cp = {0, +1, 0, 0, +1, 0, 0};

static inline int is_ws(char c){ return (c==' '||c=='\t'||c==','||c==';'); }
static inline int is_dg(char c){ return (c>='0'&&c<='9'); }

static void cparser_reset(void){ cp = (CParser){0, +1, 0, 0, +1, 0, 0}; }

static void cparser_finish(void){
    if (cp.got1 && cp.got2){
        auto_mode=0; cnn_active=0;
        int spd = clamp(cp.s1*cp.n1, -100, 100);
        int st  = clamp(cp.s2*cp.n2,  -80,  80);
        steer     = st;
        speed_pct = (spd>=0)? spd : (-spd);
        if (spd>0)      go_forward_curved();
        else if (spd<0) go_backward_curved();
        else            stop_all();
        xil_printf("[C] spd=%d steer=%d -> mode=%c\r\n", spd, st, last_mode);
    }
    cparser_reset();
}

static int handle_c_char(char c){
    if (cp.state==0){
        if (c=='C'||c=='c'){ cparser_reset(); cp.state=1; return 1; }
        return 0;
    }
    if (c=='C'||c=='c'){ cparser_finish(); cp.state=1; return 1; }

    switch(cp.state){
    case 1: if (is_ws(c)) return 1;
            if (c=='-'||c=='+'){ cp.s1=(c=='-')?-1:+1; cp.state=2; return 1; }
            if (is_dg(c)){ cp.s1=+1; cp.n1=c-'0'; cp.got1=1; cp.state=2; return 1; }
            cparser_reset(); return 1;
    case 2: if (is_dg(c)){ cp.n1=cp.n1*10+(c-'0'); cp.got1=1; return 1; }
            if (is_ws(c)){ cp.state=3; return 1; }
            cparser_finish(); return 1;
    case 3: if (is_ws(c)) return 1;
            if (c=='-'||c=='+'){ cp.s2=(c=='-')?-1:+1; cp.state=4; return 1; }
            if (is_dg(c)){ cp.s2=+1; cp.n2=c-'0'; cp.got2=1; cp.state=4; return 1; }
            cparser_finish(); return 1;
    case 4: if (is_dg(c)){ cp.n2=cp.n2*10+(c-'0'); cp.got2=1; return 1; }
            cparser_finish(); return 1;
    default: cparser_reset(); return 1;
    }
}

static void speed_step(int d){
    auto_mode=0; cnn_active=0;
    speed_pct += d;
    if (speed_pct!=0) speed_pct = clamp(speed_pct,DUTY_MIN_TURN,DUTY_MAX);
    else speed_pct = 0;
    xil_printf("SPD=%d%%, STEER=%d\r\n",speed_pct,steer);
    reapply_motion();
}

static void print_help(void){
    xil_printf("\r\n[Keys] W/A/S/D, X=stop, Z=auto, Y=auto+CNN, +=spd+10, -=spd-10, C <pwm> <steer>\r\n");
    xil_printf("[CNN] AXI Lite 인터페이스, 4패턴 인식, SPI 입력\r\n");
    xil_printf("[Commands] I=CNN상태, T=시스템테스트\r\n");
}

/* ================= main ================= */
int main(void)
{
    init_platform();
    uart_flush_rx();
    uart_puts("AXI Lite CNN READY\r\n");
    print_help();

    /* CNN AXI Lite 초기화 */
    cnn_init();

    /* PWM 프로브 */
    u32 b4 = Xil_In32(PWM_BASE + REG_DIR);
    Xil_Out32(PWM_BASE + REG_DIR, 0x5);
    u32 af = Xil_In32(PWM_BASE + REG_DIR);
    xil_printf("[PROBE] DIR before=%08lx after=%08lx (ok if different)\r\n",
               (unsigned long)b4, (unsigned long)af);
    Xil_Out32(PWM_BASE + REG_DIR, b4);

    stop_all();
    speed_pct = DUTY_MIN_MOVE;
    steer     = 0;

    int tick_ms = 0;

    while (1){
        /* ==== UART 처리 ==== */
        while (!XUartLite_IsReceiveEmpty(UARTB)){
            char c = XUartLite_RecvByte(UARTB);

            if (c=='\r' || c=='\n'){ if (cp.state) cparser_finish(); continue; }
            if (handle_c_char(c)) continue;

            switch (c){
            case 'Z': case 'z':
                auto_mode=1; cnn_active=0; speed_pct=AUTO_BASE_PCT; steer=0; 
                go_forward_curved();
                xil_printf("[AUTO] 초음파만: PWM %d%%\r\n", AUTO_BASE_PCT);
                break;
            case 'Y': case 'y':
                auto_mode=2; cnn_active=1; speed_pct=AUTO_BASE_PCT; steer=0;
                go_forward_curved();
                xil_printf("[AUTO+CNN] AXI Lite 융합모드: PWM %d%%\r\n", AUTO_BASE_PCT);
                break;
            case 'W': case 'w': auto_mode=0; cnn_active=0; go_forward_curved();  break;
            case 'S': case 's': case 'R': case 'r': auto_mode=0; cnn_active=0; go_backward_curved(); break;
            case 'A': case 'a': auto_mode=0; cnn_active=0; turn_left_spin();     break;
            case 'D': case 'd': auto_mode=0; cnn_active=0; turn_right_spin();    break;
            case 'X': case 'x': case ' ': stop_all(); xil_printf("STOP\r\n"); break;
            case '+': speed_step(+10); break;
            case '-': speed_step(-10); break;
            case 'I': case 'i': cnn_system_status(); break;  // CNN 상태 확인
            case 'T': case 't':  // 시스템 테스트
                xil_printf("[TEST] CNN AXI Lite 연결 테스트\r\n");
                cnn_system_status();
                break;
            default: break;
            }
        }

        /* ==== 자율주행 주기 동작 (20ms) ==== */
        if (auto_mode >= 1){
            if (tick_ms >= 20){
                auto_step_with_cnn();
                tick_ms = 0;
            }
        }

        usleep(1000);   /* 1 ms */
        tick_ms += 1;
    }

    cleanup_platform();
    return 0;
}