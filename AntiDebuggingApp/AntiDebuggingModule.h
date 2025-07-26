//
//  AntiDebuggingModule.h
//  AntiDebuggingApp
//
//  iOS 16 호환 안티디버깅 모듈
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// 각 안티디버깅 기법들을 함수로 모듈화
void debugger_ptrace(void);
bool debugger_sysctl(void);
void debugger_syscall(void);
bool check_exception_ports(void);
bool check_isatty(void);
bool check_ioctl(void);
void check_asm_debugger(void);

#ifdef __cplusplus
}
#endif
