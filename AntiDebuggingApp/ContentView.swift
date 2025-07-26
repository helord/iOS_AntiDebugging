import SwiftUI

struct ContentView: View {
    @StateObject private var antiDebugManager = AntiDebuggingManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Anti-Debugging Test App")
                .font(.title)
                .padding()
            
            Text("앱이 실행 중입니다.")
                .font(.body)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("디버깅 상태:")
                    .font(.headline)
                
                ForEach(antiDebugManager.debugResults, id: \.method) { result in
                    HStack {
                        Circle()
                            .fill(result.isDebugged ? Color.red : Color.green)
                            .frame(width: 10, height: 10)
                        
                        Text("\(result.method): \(result.isDebugged ? "감지됨" : "정상")")
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            Spacer()
        }
        .padding()
        .onAppear {
            antiDebugManager.startMonitoring()
        }
    }
}
