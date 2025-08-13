# iOS 안티디버깅 구현 가이드

## 프로젝트 개요
이 프로젝트는 iOS 앱에서 디버거 탐지 및 차단을 위한 다양한 안티디버깅 기법들을 구현한 예제입니다.

## 프로젝트 구조

```
AntiDebuggingApp/
├── AntiDebuggingManager.swift          # Swift로 작성된 메인 매니저 클래스
├── AntiDebuggingModule.h               # C/Objective-C 함수들의 헤더 파일
├── AntiDebuggingModule.m               # C/Objective-C로 구현된 저수준 안티디버깅 기법들
├── ContentView.swift                   # 사용자 인터페이스 및 결과 표시
└── AntiDebuggingApp-Bridging-Header.h  # Swift와 Objective-C 연결을 위한 브리징 헤더
```

## 구현된 안티디버깅 기법들

### 1. ptrace() 방식
**파일 위치**: `AntiDebuggingModule.m` 39-45줄

```objective-c
void debugger_ptrace() {
    void* handle = dlopen(0, RTLD_GLOBAL | RTLD_NOW);
    ptrace_ptr_t ptrace_ptr = dlsym(handle, "ptrace");
    ptrace_ptr(PT_DENY_ATTACH, 0, 0, 0);
    dlclose(handle);
}
```

**동작 원리**:
- `PT_DENY_ATTACH` 플래그를 사용해서 디버거가 프로세스에 attach하는 것을 차단
- `dlopen()`과 `dlsym()`을 사용해서 ptrace 함수를 동적으로 불러와서 후킹을 우회

**왜 이렇게 하는가**:
- 직접 `ptrace()` 함수를 호출하면 해커가 쉽게 후킹할 수 있음
- 동적 링킹을 사용하면 후킹하기 더 어려워짐

### 2. sysctl() 방식  
**파일 위치**: `AntiDebuggingModule.m` 52-79줄

```objective-c
bool debugger_sysctl(void) {
    int mib[4];
    struct kinfo_proc info;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();
    
    sysctl(mib, 4, &info, &info_size, NULL, 0);
    
    return ((info.kp_proc.p_flag & P_TRACED) != 0);
}
```

**동작 원리**:
- 시스템에서 현재 프로세스의 정보를 가져옴
- `P_TRACED` 플래그가 설정되어 있으면 디버거가 붙어있다는 뜻

**언제 사용하는가**:
- ptrace와 달리 앱을 종료시키지 않고 탐지만 함
- 디버깅 상태를 지속적으로 모니터링할 때 유용

### 3. 직접 syscall 방식
**파일 위치**: `AntiDebuggingModule.m` 85-111줄

```objective-c
void debugger_syscall(void) {
    #ifdef __arm64__
    __asm__ volatile (
        "mov x0, #31\n"        // PT_DENY_ATTACH
        "mov x1, #0\n"         // pid (0 = 현재 프로세스)
        "mov x2, #0\n"         // addr
        "mov x3, #0\n"         // data
        "mov x16, #26\n"       // ptrace 시스템 콜 번호
        "svc #128\n"           // 시스템 콜 실행
    );
    #endif
}
```

**동작 원리**:
- C 라이브러리를 거치지 않고 직접 커널의 시스템 콜을 호출
- ARM64 어셈블리 코드를 사용해서 레지스터에 직접 값을 설정

**왜 이 방식이 강력한가**:
- 라이브러리 함수 후킹을 완전히 우회
- 해커가 막기 가장 어려운 방식 중 하나

### 4. Exception Ports 확인 방식
**파일 위치**: `AntiDebuggingModule.m` 119-147줄

```objective-c
bool check_exception_ports(void) {
    struct ios_execp_info *info = malloc(sizeof(struct ios_execp_info));
    
    task_get_exception_ports(mach_task_self(), EXC_MASK_ALL,
                           info->masks, &info->count,
                           info->ports, info->behaviors,
                           info->flavors);
    
    // exception port가 설정되어 있으면 디버거가 있다는 뜻
    for (int i = 0; i < info->count; i++) {
        if (info->ports[i] != 0) {
            return true; // 디버거 감지됨
        }
    }
    return false;
}
```

**동작 원리**:
- LLDB 같은 디버거는 앱의 예외(크래시 등)를 처리하기 위해 exception port를 설정함
- 이 포트가 설정되어 있으면 디버거가 붙어있다고 판단

### 5. 터미널 환경 탐지 방식
**파일 위치**: `AntiDebuggingModule.m` 154-173줄

```objective-c
// isatty 방식
bool check_isatty(void) {
    return isatty(1); // 표준 출력이 터미널인지 확인
}

// ioctl 방식  
bool check_ioctl(void) {
    return !ioctl(1, TIOCGWINSZ); // 터미널 창 크기 정보가 있는지 확인
}
```

**동작 원리**:
- 앱이 터미널 환경에서 실행되고 있는지 확인
- LLDB로 디버깅할 때는 터미널 환경이므로 이를 탐지

## Swift 매니저 클래스 구현

### AntiDebuggingManager.swift 핵심 부분

```swift
class AntiDebuggingManager: ObservableObject {
    // 각 기법을 개별적으로 켜고 끌 수 있음
    private let enabledMethods = [
        "ptrace": false,      // 앱 종료시키므로 테스트할 때는 false
        "sysctl": true,       // 안전하게 탐지만 함
        "syscall": false,     // 앱 종료시키므로 주의
        "exception_ports": true,
        "isatty": true,
        "ioctl": true
    ]
    
    func startMonitoring() {
        // 1초마다 모든 탐지 기법 실행
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.performAllChecks()
        }
    }
    
    private func performAllChecks() {
        // 활성화된 기법들만 실행
        if enabledMethods["sysctl"] == true {
            let isDebugged = debugger_sysctl()
            // 결과를 UI에 표시
        }
    }
}
```

**중요한 점들**:
- `enabledMethods`에서 각 기법을 개별적으로 제어 가능
- `ptrace`와 `syscall`은 앱을 종료시키므로 프로덕션에서만 사용
- Timer로 지속적으로 모니터링

## 설정 및 연결 방법

### 1. 브리징 헤더 설정
**파일**: `AntiDebuggingApp-Bridging-Header.h`
```objective-c
#import "AntiDebuggingModule.h"
```
이 파일이 있어야 Swift에서 C/Objective-C 함수들을 호출할 수 있습니다.

### 2. Xcode 프로젝트 설정
- Build Settings에서 "Objective-C Bridging Header" 항목에 브리징 헤더 파일 경로 설정
- Swift Compiler - General에서 설정 가능

### 3. 헤더 파일 작성 규칙
```objective-c
#ifdef __cplusplus
extern "C" {
#endif

// 함수 선언들
void debugger_ptrace(void);
bool debugger_sysctl(void);

#ifdef __cplusplus
}
#endif
```
C++과의 호환성을 위해 `extern "C"` 블록으로 감싸야 합니다.

## 실제 사용 방법

### 1. 개발/테스트 단계
```swift
// 앱을 종료시키지 않는 안전한 기법들만 활성화
private let enabledMethods = [
    "ptrace": false,
    "syscall": false,
    "sysctl": true,
    "exception_ports": true,
    "isatty": true,
    "ioctl": true
]
```

### 2. 프로덕션 배포 단계
```swift
// 모든 기법 활성화 (강력한 보호)
private let enabledMethods = [
    "ptrace": true,      // 디버거 감지시 앱 종료
    "syscall": true,     // 가장 강력한 보호
    "sysctl": true,
    "exception_ports": true,
    "isatty": true,
    "ioctl": true
]
```

## 주의사항

1. **테스트할 때 주의**: `ptrace`와 `syscall` 기법은 디버거가 감지되면 앱을 강제 종료시킵니다.

2. **앱스토어 심사**: 안티디버깅 기법들은 앱스토어 심사에서 문제가 될 수 있으니 주의하세요.

3. **성능 고려**: Timer 간격을 너무 짧게 하면 배터리 소모가 늘어납니다.

4. **iOS 버전 호환성**: 이 코드는 iOS 16 이상에서 테스트되었습니다.

## 디버깅 및 문제 해결

### 컴파일 에러가 날 때
1. 브리징 헤더 파일 경로가 올바른지 확인
2. 헤더 파일에 `#import "AntiDebuggingModule.h"` 추가되었는지 확인
3. Target Membership에서 모든 파일이 올바른 타겟에 포함되었는지 확인

### 함수가 호출되지 않을 때
1. enabledMethods에서 해당 기법이 true로 설정되었는지 확인
2. Swift에서 C 함수 호출 문법이 올바른지 확인
3. 콘솔 로그에서 NSLog 메시지가 출력되는지 확인
