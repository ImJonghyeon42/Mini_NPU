#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xil_io.h"
#include "xuartlite_l.h"
#include "sleep.h"
#include "xil_types.h"

/* ================= UART 선택 ================= */
#ifndef UARTB
  #if defined(XPAR_AXI_UARTLITE_1_BASEADDR)
    #define UARTB XPAR_AXI_UARTLITE_1_BASEADDR  /* 앱/BT 연결 UARTLite */
  #elif defined(XPAR_UARTLITE_1_BASEADDR)
    #define UARTB XPAR_UARTLITE_1_BASEADDR
  #else
    #define UARTB STDIN_BASEADDRESS
  #endif
#endif

static inline void uart_putc(char c){ XUartLite_SendByte(UARTB, (u8)c); }
static void uart_puts(const char *s){ while(*s) uart_putc(*s++); }
static void uart_flush_rx(void){ while(!XUartLite_IsReceiveEmpty(UARTB)) (void)XUartLite_RecvByte(UARTB); }

/* ================= CNN IP 레지스터 맵 ================= */
#define CNN_BASE    XPAR_MYIP_CNN_V1_0_BASEADDR  /* Block Design에서 할당될 주소 */
#define CNN_CONTROL 0x00    /* 제어 레지스터 (bit0: start, bit1: reset) */
#define CNN_STATUS  0x04    /* 상태 레지스터 (bit0: result_valid) */
#define CNN_RESULT_LOW  0x08    /* CNN 결과 하위 32비트 */
#define CNN_RESULT_HIGH 0x0C    /* CNN 결과 상위 16비트 */

/* ================= PWM IP 레지스터 맵 ================= */
#define PWM_BASE   XPAR_DCMOTOR_MYIP_V1_0_BASEADDR
#define REG_EN     0x00
#define REG_DIR    0x04
#define REG_DUTY   0x08

/* ================= 초음파 IP 베이스 ================= */
#define UL_F   XPAR_ULTRASONIC_MYIP_V1_0_0_BASEADDR
#define UL_R   XPAR_ULTRASONIC_MYIP_V1_0_1_BASEADDR
#define UL_L   XPAR_ULTRASONIC_MYIP_V1_0_2_BASEADDR

/* ================= 채널/차륜 매핑 ================= */
#define CH_FR 0
#define CH_FL 1
#define CH_RL 2
#define CH_RR 3

/* 특정 바퀴 반전(정/역 뒤집힘) — {FR,FL,RL,RR} */
static const u8 MOTOR_INV[4] = { 1, 0, 1, 0 };

/* ================= 파라미터 ================= */
#define DUTY_MIN_MOVE   30     /* 주행 유지용 최소 듀티(빠른 바퀴용) */
#define DUTY_MIN_TURN   14     /* 코너링 시 느린 바퀴 최소 듀티(펄싱 방지) */
#define DUTY_MAX       100
#define KICK_DUTY       70
#define KICK_MS        120
#define DEAD_US        150
#define SPIN_PWM        80

#define STEER_SIGN     (-1)    /* 양수=좌, 음수=우 (부호 스위치) */

#define AUTO_BASE_PCT   50     /* 기본 크루즈 속도 */

/* ==== 자율 튜닝 ==== */
#define WALL_CM        50     /* 더 멀리서부터 회피 시작 */
#define PANIC_CM       18      /* F만 비상 */
#define STEER_K        22      /* 조향 민감도 상향 */

#define NEAR_BOOST_CM  35      /* 가까운 구간이면 조향 가중치 추가 */
#define STEER_BOOST     2      /* 가중치 배수 */

/* 전방 감속 밴드 */
#define FRONT_SLOW1_CM  85
#define FRONT_SLOW2_CM  50
#define FRONT_SLOW1_PCT 40
#define FRONT_SLOW2_PCT 30

/* F 근접 시 후진 파라미터 */
#define BACKUP_MS      800     /* 0.8초 후진 */
#define BACKUP_PCT      55     /* 후진 PWM(%) */

/* ================= CNN 파라미터 ================= */
#define CNN_TIMEOUT_MS    100   /* CNN 결과 대기 최대 시간 */
#define CNN_SCALE_FACTOR  1000  /* CNN 결과 스케일링 */
#define CNN_STEER_MAX     80    /* CNN 최대 조향각 */
#define CNN_CONFIDENCE_MIN 0.6  /* CNN 신뢰도 최소값 */

/* CNN 패턴 정의 (4클래스) */
#define CNN_PATTERN_STRAIGHT    0
#define CNN_PATTERN_LEFT_CURVE  1  
#define CNN_PATTERN_RIGHT_CURVE 2
#define CNN_PATTERN_START_END   3

/* ================= 상태 ================= */
static int  speed_pct = DUTY_MIN_MOVE; /* 0..100 */
static int  steer     = 0;             /* -80..+80 (양수=좌, 음수=우) */
static char last_mode = 'X';
static int  auto_mode = 0;             /* 0:수동 1:자율 2:CNN+초음파 융합 */

/* CNN 상태 */
static int  cnn_active = 0;            /* CNN 활성화 여부 */
static s32  last_cnn_result = 0;       /* 마지막 CNN 결과 */
static int  cnn_pattern = -1;          /* 현재 감지된 패턴 */
static int  cnn_timeout_count = 0;     /* CNN 타임아웃 카운터 */

/* 출력 데드밴드용 이전 듀티 저장(미세 변화 무시) */
static int prev_dutyL = -1, prev_dutyR = -1;

/* ================= 유틸/저수준 IO ================= */
static inline void w32(u32 reg, u32 v){ Xil_Out32(PWM_BASE + reg, v); }
static inline u32 r32(u32 reg){ return Xil_In32(PWM_BASE + reg); }
static inline int clamp(int v, int lo, int hi){ if(v<lo) return lo; if(v>hi) return hi; return v; }
#define BIT(ch) (1u<<(ch))
#define ALL_MASK (BIT(0)|BIT(1)|BIT(2)|BIT(3))

/* ================= CNN 전용 함수 ================= */

/**
 * CNN 초기화 - 시스템 시작 시 1회 실행
 */
static void cnn_init(void) {
    // CNN 리셋
    Xil_Out32(CNN_BASE + CNN_CONTROL, 0x02);  // reset bit
    usleep(1000);  // 1ms 대기
    Xil_Out32(CNN_BASE + CNN_CONTROL, 0x00);  // reset 해제
    
    xil_printf("[CNN] 초기화 완료 - Base: 0x%08lx\r\n", (unsigned long)CNN_BASE);
}

/**
 * CNN 결과 읽기 (논블로킹)
 * @return: 성공시 조향각(-80~+80), 실패시 0
 */
static s32 cnn_read_steering_angle(void) {
    // 1. 결과 유효성 확인
    u32 status = Xil_In32(CNN_BASE + CNN_STATUS);
    if (!(status & 0x01)) {
        return 0;  // 결과 없음
    }
    
    // 2. CNN 결과 읽기 (48비트 → 32비트 변환)
    u32 result_low = Xil_In32(CNN_BASE + CNN_RESULT_LOW);
    u32 result_high = Xil_In32(CNN_BASE + CNN_RESULT_HIGH) & 0xFFFF;
    
    // 3. 48비트 결합 후 조향각 추출
    s64 raw_result = ((s64)result_high << 32) | result_low;
    
    // 4. 스케일링 및 클램핑 (CNN 출력을 -80~+80 범위로)
    s32 steering_angle = (s32)(raw_result / CNN_SCALE_FACTOR);
    steering_angle = clamp(steering_angle, -CNN_STEER_MAX, CNN_STEER_MAX);
    
    return steering_angle;
}

/**
 * CNN 패턴 분류 (4클래스)
 * @param result: CNN 원시 결과
 * @return: 0=직선, 1=좌곡선, 2=우곡선, 3=시작/종료
 */
static int cnn_classify_pattern(s32 result) {
    int abs_result = (result < 0) ? -result : result;
    
    if (abs_result < 10) {
        return CNN_PATTERN_STRAIGHT;      // 직선
    } else if (result > 30) {
        return CNN_PATTERN_LEFT_CURVE;    // 좌곡선
    } else if (result < -30) {
        return CNN_PATTERN_RIGHT_CURVE;   // 우곡선
    } else {
        return CNN_PATTERN_START_END;     // 시작/종료
    }
}

/**
 * CNN 기반 조향 로직
 * @param cnn_steer: CNN에서 계산된 조향각
 * @return: 최종 적용할 조향각
 */
static int cnn_apply_steering_logic(s32 cnn_steer) {
    cnn_pattern = cnn_classify_pattern(cnn_steer);
    
    // 패턴별 조향 보정
    switch (cnn_pattern) {
        case CNN_PATTERN_STRAIGHT:
            return cnn_steer;  // 직선: 그대로 적용
            
        case CNN_PATTERN_LEFT_CURVE:
            return clamp(cnn_steer + 5, -CNN_STEER_MAX, CNN_STEER_MAX);  // 좌곡선: 약간 강화
            
        case CNN_PATTERN_RIGHT_CURVE:
            return clamp(cnn_steer - 5, -CNN_STEER_MAX, CNN_STEER_MAX);  // 우곡선: 약간 강화
            
        case CNN_PATTERN_START_END:
            return cnn_steer / 2;  // 시작/종료: 부드럽게
            
        default:
            return 0;
    }
}

/* [기존 모터 제어 함수들은 그대로 유지] */
static inline u8 apply_inv_to_dir_bits(u8 dir_bits){
    u8 d=0;
    for(int ch=0; ch<4; ++ch){
        u8 bit = (dir_bits>>ch)&1u; /* 1=REV */
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
    w32(REG_EN, 0x0);
    usleep(DEAD_US);
    u8 dir_hw = apply_inv_to_dir_bits(dir_rev_mask1bit & 0x0F);
    w32(REG_DIR,  dir_hw);
    w32(REG_DUTY, pack_duty(d0,d1,d2,d3));
    w32(REG_EN,   en_mask & 0x0F);
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

static void stop_all(void){ w32(REG_EN,0x0); last_mode='X'; auto_mode=0; cnn_active=0; }

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
    if (dirL_revbit){ dir_bits |= BIT(CH_RL); dir_bits |= BIT(CH_FL); }
    if (dirR_revbit){ dir_bits |= BIT(CH_RR); dir_bits |= BIT(CH_FR); }

    int need_kick = (last_mode=='X') || (dutyL<=DUTY_MIN_TURN) || (dutyR<=DUTY_MIN_TURN);
    if (need_kick && (dutyL>0 || dutyR>0)){
        u8 kd0,kd1,kd2,kd3; map_lr_to_duty(KICK_DUTY,KICK_DUTY,&kd0,&kd1,&kd2,&kd3);
        set_all(ALL_MASK, dir_bits, kd0,kd1,kd2,kd3);
        usleep(KICK_MS*1000);
    }
    set_all(ALL_MASK, dir_bits, d0,d1,d2,d3);

    prev_dutyL = dutyL;
    prev_dutyR = dutyR;
}

static void spin_with_rear_fix(int left) {
    u8 d0,d1,d2,d3;
    map_lr_to_duty(SPIN_PWM, SPIN_PWM, &d0,&d1,&d2,&d3);

    u8 dir_bits = 0;
    if (left){
        dir_bits |= BIT(CH_FL);
        dir_bits |= BIT(CH_RR);
    }else{
        dir_bits |= BIT(CH_FR);
        dir_bits |= BIT(CH_RL);
    }

    int need_kick = (last_mode=='X');
    if (need_kick){
        u8 kd0,kd1,kd2,kd3; map_lr_to_duty(KICK_DUTY, KICK_DUTY, &kd0,&kd1,&kd2,&kd3);
        set_all(ALL_MASK, dir_bits, kd0,kd1,kd2,kd3);
        usleep(KICK_MS*1000);
    }
    set_all(ALL_MASK, dir_bits, d0,d1,d2,d3);
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

static void speed_step(int d){
    auto_mode=0; cnn_active=0;
    speed_pct += d;
    if (speed_pct!=0) speed_pct = clamp(speed_pct,DUTY_MIN_TURN,DUTY_MAX);
    else speed_pct = 0;
    xil_printf("SPD=%d%%, STEER=%d\r\n",speed_pct,steer);
    reapply_motion();
}

/* [기존 C 파서 코드들도 그대로 유지] */
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

/* ================= 초음파 읽기 ================= */
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

/* ================= CNN + 초음파 융합 자율주행 ================= */
static void auto_step_with_cnn(void){
    /* 1) 초음파 센서 읽기 */
    u32 F = ultra_read_avg(UL_F, 3);
    u32 R = ultra_read_avg(UL_R, 3);
    u32 L = ultra_read_avg(UL_L, 3);

    /* 2) 비상상황: 전방 근접 시 기존 로직 우선 */
    if (F>0 && F<=PANIC_CM){
        int left_more_space = (L >= R);

        /* 후진 */
        int save_spd = speed_pct, save_st = steer;
        speed_pct = BACKUP_PCT;
        steer = 0;
        go_backward_curved();
        usleep(BACKUP_MS * 1000);

        /* 스핀 */
        if (left_more_space) turn_left_spin();
        else                 turn_right_spin();
        for(int i=0;i<10 && auto_mode;i++) usleep(100000);

        /* 전진 재개 */
        speed_pct = AUTO_BASE_PCT;
        steer = 0;
        go_forward_curved();
        return;
    }

    /* 3) 전방 감속 (기존 로직) */
    if      (F>0 && F<FRONT_SLOW2_CM) speed_pct = FRONT_SLOW2_PCT;
    else if (F>0 && F<FRONT_SLOW1_CM) speed_pct = FRONT_SLOW1_PCT;
    else                              speed_pct = AUTO_BASE_PCT;

    /* 4) 조향 결정: CNN vs 초음파 융합 */
    int final_steer = 0;
    
    if (cnn_active) {
        /* CNN 결과 읽기 */
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
                /* 강한 장애물 신호 → 초음파 우선 */
                final_steer = clamp(obstacle_steer, -80, 80);
            } else if (abs(obstacle_steer) > 10) {
                /* 중간 장애물 신호 → 가중 평균 */
                final_steer = clamp((obstacle_steer * 2 + processed_cnn_steer) / 3, -80, 80);
            } else {
                /* 장애물 없음 → CNN 차선 추종 */
                final_steer = clamp(processed_cnn_steer, -80, 80);
            }
            
        } else {
            /* CNN 결과 없음 → 타임아웃 처리 */
            cnn_timeout_count++;
            if (cnn_timeout_count > 10) {  /* 200ms (20ms * 10) 타임아웃 */
                /* CNN 타임아웃 → 초음파만으로 처리 */
                int s = 0;
                if (R>0 && R<=WALL_CM) s +=  (WALL_CM - (int)R) * STEER_K;
                if (L>0 && L<=WALL_CM) s += -(WALL_CM - (int)L) * STEER_K;
                
                int side_near = min_nonzero((int)R, (int)L);
                if (side_near>0 && side_near <= NEAR_BOOST_CM){
                    s *= STEER_BOOST;
                }
                final_steer = clamp(s, -80, +80);
                
                /* 마지막 CNN 결과 서서히 감소 */
                last_cnn_result = last_cnn_result * 9 / 10;
            } else {
                /* 짧은 타임아웃 → 마지막 CNN 결과 유지 */
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

/* ================= 도움말 ================= */
static void print_help(void){
    xil_printf("\r\n[Keys] W/A/S/D, X=stop, Z=auto, Y=auto+CNN, +=spd+10, -=spd-10, C <pwm> <steer>\r\n");
    xil_printf("[CNN] 4패턴 인식: 직선/좌곡선/우곡선/시작종료\r\n");
}

/* ================= main ================= */
int main(void)
{
    init_platform();
    uart_flush_rx();
    uart_puts("BT + CNN READY\r\n");
    print_help();

    /* CNN 초기화 */
    cnn_init();

    /* PROBE */
    u32 b4 = r32(REG_DIR);
    w32(REG_DIR, 0x5);
    u32 af = r32(REG_DIR);
    xil_printf("[PROBE] DIR before=%08lx after=%08lx (ok if different)\r\n",
               (unsigned long)b4, (unsigned long)af);
    w32(REG_DIR, b4);

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
                xil_printf("[AUTO+CNN] 융합모드: PWM %d%%\r\n", AUTO_BASE_PCT);
                break;
            case 'W': case 'w': auto_mode=0; cnn_active=0; go_forward_curved();  break;
            case 'S': case 's': case 'R': case 'r': auto_mode=0; cnn_active=0; go_backward_curved(); break;
            case 'A': case 'a': auto_mode=0; cnn_active=0; turn_left_spin();     break;
            case 'D': case 'd': auto_mode=0; cnn_active=0; turn_right_spin();    break;
            case 'X': case 'x': case ' ': stop_all(); xil_printf("STOP\r\n"); break;
            case '+': speed_step(+10); break;
            case '-': speed_step(-10); break;
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