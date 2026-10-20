import SwiftUI
import ReplayKit
import UserNotifications
let sharedStore = UserDefaults(suiteName: AppConfiguration.appGroup)!
@main struct ReelProofApp: App { var body: some Scene { WindowGroup { ContentView() } } }
struct ContentView: View {
    @AppStorage("serverURL", store: sharedStore) var endpoint = "https://reelproof-evidence.vercel.app"
    @AppStorage("serverToken", store: sharedStore) var token = ""
    @State var message = "AI 대본 문체는 기기에서 분석합니다. 원문 사실 검증에는 서버 접근 키가 필요합니다."
    @State var showPicker = false
    let green = Color(red: 0.10, green: 0.29, blue: 0.23)
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            Text("▶  ReelProof").font(.title2.bold()).foregroundStyle(green)
            Text("넘기기 전에,\n한 번 더 확인.").font(.system(size: 36, weight: .semibold)).foregroundStyle(green)
            Text("음성·화면 자막에서 주장을 선별하고, 원문 근거를 확인합니다.").font(.subheadline).foregroundStyle(.secondary)
            TextField("검증 서버 HTTPS 주소", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder)
            SecureField("검증 서버 접근 키", text: $token).textFieldStyle(.roundedBorder)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Text("Gemini API 키는 서버의 비밀 설정에 등록하세요. 이 앱에는 별도로 발급된 검증 서버 접근 키를 입력합니다.").font(.footnote).foregroundStyle(.secondary)
            Button("탐지 준비") {
                guard let url = URL(string: endpoint), url.scheme == "https" else { message = "실제 검증 서버 HTTPS 주소가 필요합니다."; return }
                guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroup) != nil else { message = "공유 설정 권한을 확인하지 못했습니다. 앱과 방송 확장의 App Group을 유지해 함께 서명해야 합니다."; return }
                sharedStore.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "serverURL")
                sharedStore.set(token, forKey: "serverToken")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in DispatchQueue.main.async { showPicker = true; message = granted ? "아래 녹화 버튼에서 ReelProof를 선택해 방송을 시작한 뒤 릴스 앱으로 이동하세요." : "알림이 꺼져 있어 다른 앱 위에 결과를 알릴 수 없습니다." } }
            }.frame(maxWidth: .infinity).padding().background(green).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 16))
            if showPicker { HStack { BroadcastPicker().frame(width: 64, height: 64); Text("시스템 녹화 시작\nReelProof 선택").font(.subheadline) } }
            Text("화면 녹화 동의는 iOS의 필수 단계입니다. 제어 센터의 녹화를 중지하면 탐지도 종료됩니다. 원본 앱이 캡처를 막으면 추출할 수 없습니다.").font(.footnote).foregroundStyle(.secondary)
            Text("서버 접근 키가 없으면 자막의 AI 대본 문체만 기기에서 분석합니다. 이 알림은 실험 신호이며 영상 제작 출처나 진위를 확정하지 않습니다. 실제 릴스 성능은 평가하지 않았습니다.").font(.footnote).foregroundStyle(.secondary)
        }.padding(28) }.background(Color(red: 0.96, green: 0.97, blue: 0.95)).onOpenURL { _ in message = "검증 서버 설정을 확인한 뒤 탐지를 준비하세요." }
    }
}
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView { let view = RPSystemBroadcastPickerView(frame: .zero); view.preferredExtension = AppConfiguration.broadcastExtension; view.showsMicrophoneButton = false; return view }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
