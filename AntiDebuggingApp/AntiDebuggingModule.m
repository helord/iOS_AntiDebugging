import Foundation
import SwiftUI

struct DebugResult {
    let method: String
    let isDebugged: Bool
}

class AntiDebuggingManager: ObservableObject {
    @Published var debugResults: [DebugResult] = []
    private var timer: Timer?
    
    // 각 안티디버깅 기법을 개별적으로 활성화/비활성화
    private let enabledMethods = [
        "ptrace": false, //감지하고 attach 안됨
        "sysctl": false, //감지함
        "syscall": true, // 감지하고 attach 안됨
        "exception_ports": false, //감지함
        "isatty": false, //감지한다고 하는데 안되는듯..?
        "ioctl": false, //안되는거 같은데..?
        "asm": false // 감지하고 attach 안됨
    ]
    
    func startMonitoring() {
        // 초기 실행
        performAllChecks()
        
        // 1초마다 디버깅 상태 확인 (필요에 따라 조정)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.performAllChecks()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func performAllChecks() {
        var results: [DebugResult] = []
        
        // 1. ptrace 방식 (주석 해제하면 활성화)
        if enabledMethods["ptrace"] == true {
             debugger_ptrace() // 실제 앱에서는 주석 해제
            results.append(DebugResult(method: "ptrace", isDebugged: false))
        }
        
        // 2. sysctl 방식
        if enabledMethods["sysctl"] == true {
            let isDebugged = debugger_sysctl()
            results.append(DebugResult(method: "sysctl", isDebugged: isDebugged))
        }
        
        // 3. syscall 방식 (주석 해제하면 활성화)
        if enabledMethods["syscall"] == true {
            debugger_syscall()
            results.append(DebugResult(method: "syscall", isDebugged: false))
        }
        
        // 4. exception ports 방식
        if enabledMethods["exception_ports"] == true {
            let isDebugged = check_exception_ports()
            results.append(DebugResult(method: "exception_ports", isDebugged: isDebugged))
        }
        
        // 5. isatty 방식
        if enabledMethods["isatty"] == true {
            let isDebugged = check_isatty()
            results.append(DebugResult(method: "isatty", isDebugged: isDebugged))
        }
        
        // 6. ioctl 방식
        if enabledMethods["ioctl"] == true {
            let isDebugged = check_ioctl()
            results.append(DebugResult(method: "ioctl", isDebugged: isDebugged))
        }
        
        DispatchQueue.main.async {
            self.debugResults = results
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
