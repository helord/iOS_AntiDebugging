import SwiftUI

@main
struct AntiDebuggingApp: App {
    
    init() {
        // 앱 시작 시 즉시 안티디버깅 활성화
        setupAntiDebugging()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func setupAntiDebugging() {
        // 필요한 안티디버깅 기법들을 여기서 활성화
        // 각 라인을 주석 처리하여 개별 테스트 가능
        
        print("[AntiDebug] 안티디버깅 시스템 초기화 중...")
        
        // 1. ptrace 방식 (주석 해제하면 즉시 디버거 차단)
//         debugger_ptrace()
        
        // 2. syscall 방식 (주석 해제하면 즉시 디버거 차단)
//         debugger_syscall()

        print("[AntiDebug] 안티디버깅 시스템 초기화 완료")
    }
}
