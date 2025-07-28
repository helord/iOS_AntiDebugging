//
//  AntiDebuggingModule.m
//  AntiDebuggingApp
//
//  iOS 16 호환 안티디버깅 구현 모듈
//

#import "AntiDebuggingModule.h"

// ptrace 관련 헤더
#import <dlfcn.h>
#import <sys/types.h>

// sysctl 관련 헤더
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <stdlib.h>

// ioctl 관련 헤더
#include <termios.h>
#include <sys/ioctl.h>

// exception ports 관련 헤더
#include <mach/task.h>
#include <mach/mach_init.h>

typedef int (*ptrace_ptr_t)(int _request, pid_t _pid, caddr_t _addr, int _data);

#if !defined(PT_DENY_ATTACH)
#define PT_DENY_ATTACH 31
#endif

/*!
 @brief 기본 ptrace 안티디버깅 기법
 @discussion 디버거가 프로세스에 attach하는 것을 방지
 */
void debugger_ptrace() {
    void* handle = dlopen(0, RTLD_GLOBAL | RTLD_NOW);
    ptrace_ptr_t ptrace_ptr = dlsym(handle, "ptrace");
    ptrace_ptr(PT_DENY_ATTACH, 0, 0, 0);
    dlclose(handle);
    NSLog(@"[AntiDebug] ptrace() 보호 활성화됨");
}

/*!
 @brief sysctl을 이용한 디버거 탐지
 @discussion P_TRACED 플래그를 확인하여 디버깅 상태를 검사
 @return YES if being debugged, NO otherwise
 */
bool debugger_sysctl(void) {
    int mib[4];
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    
    // 플래그 초기화
    info.kp_proc.p_flag = 0;
    
    // mib 초기화 - 특정 프로세스 ID의 정보를 요청
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();
    
    // sysctl 호출
    if (sysctl(mib, 4, &info, &info_size, NULL, 0) == -1) {
        NSLog(@"[AntiDebug] sysctl 호출 실패");
        return false;
    }
    
    // P_TRACED 플래그가 설정되어 있으면 디버깅 중
    bool isDebugged = ((info.kp_proc.p_flag & P_TRACED) != 0);
    if (isDebugged) {
        NSLog(@"[AntiDebug] sysctl: 디버거 감지됨!");
    }
    
    return isDebugged;
}

/*!
 @brief 직접 syscall을 이용한 ptrace 호출
 @discussion 라이브러리 후킹을 우회하여 직접 시스템 콜 사용
 */
void debugger_syscall(void) {
    // iOS 16에서는 syscall() 함수를 직접 사용할 수 없으므로
    // 어셈블리를 통한 시스템 콜 구현
    #ifdef __arm64__
    __asm__ volatile (
        "mov x0, #31\n"        // PT_DENY_ATTACH (첫 번째 인자)
        "mov x1, #0\n"         // pid (0 = current process)
        "mov x2, #0\n"         // addr (사용되지 않음)
        "mov x3, #0\n"         // data (사용되지 않음)
        "mov x16, #26\n"       // ptrace syscall number (중요!)
        "svc #128\n"           // supervisor call
    );
    #endif
    
    #ifdef __arm__
    __asm__ volatile (
        "mov r0, #31\n"        // PT_DENY_ATTACH
        "mov r1, #0\n"         // pid
        "mov r2, #0\n"         // addr
        "mov r3, #0\n"         // data (ARM32에서는 r3도 명시적 설정)
        "mov r12, #26\n"       // syscall number (r12 = ip register)
        "svc #80\n"            // supervisor call
    );
    #endif
    
    NSLog(@"[AntiDebug] syscall() 보호 활성화됨");
}


/*!
 @brief exception ports를 확인하여 디버거 탐지
 @discussion LLDB와 같은 디버거는 예외 포트를 설정함
 @return YES if being debugged, NO otherwise
 */
bool check_exception_ports(void) {
    struct ios_execp_info {
        exception_mask_t masks[EXC_TYPES_COUNT];
        mach_port_t ports[EXC_TYPES_COUNT];
        exception_behavior_t behaviors[EXC_TYPES_COUNT];
        thread_state_flavor_t flavors[EXC_TYPES_COUNT];
        mach_msg_type_number_t count;
    };
    
    struct ios_execp_info *info = malloc(sizeof(struct ios_execp_info));
    kern_return_t kr = task_get_exception_ports(mach_task_self(), EXC_MASK_ALL,
                                              info->masks, &info->count,
                                              info->ports, info->behaviors,
                                              info->flavors);
    
    bool isDebugged = false;
    if (kr == KERN_SUCCESS) {
        for (int i = 0; i < info->count; i++) {
            if (info->ports[i] != 0 || info->flavors[i] == THREAD_STATE_NONE) {
                NSLog(@"[AntiDebug] exception_ports: 디버거 감지됨!");
                isDebugged = true;
                break;
            }
        }
    }
    
    free(info);
    return isDebugged;
}

/*!
 @brief isatty를 이용한 디버거 탐지
 @discussion 터미널 환경 확인을 통한 LLDB 탐지
 @return YES if being debugged, NO otherwise
 */
bool check_isatty(void) {
    bool isDebugged = isatty(1);
    if (isDebugged) {
        NSLog(@"[AntiDebug] isatty: 디버거 감지됨!");
    }
    return isDebugged;
}

/*!
 @brief ioctl을 이용한 디버거 탐지
 @discussion 터미널 윈도우 크기 정보 확인을 통한 LLDB 탐지
 @return YES if being debugged, NO otherwise
 */
bool check_ioctl(void) {
    bool isDebugged = !ioctl(1, TIOCGWINSZ);
    if (isDebugged) {
        NSLog(@"[AntiDebug] ioctl: 디버거 감지됨!");
    }
    return isDebugged;
}
