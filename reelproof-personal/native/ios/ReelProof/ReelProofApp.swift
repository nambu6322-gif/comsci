import SwiftUI
import ReplayKit
import UserNotifications
import UIKit
// Keep the settings screen usable when a signing tool removed shared rights.
// Local preferences are never used as an extension-sharing substitute.
let sharedStore = AppConfiguration.sharedDefaults ?? .standard
@main struct ReelProofApp: App { var body: some Scene { WindowGroup { ContentView() } } }
struct ContentView: View {
    @AppStorage("serverURL", store: sharedStore) var endpoint = "https://reelproof-evidence.vercel.app"
    @AppStorage("serverToken", store: sharedStore) var token = ""
    @State private var message = "AI 대본 문체는 기기에서 분석합니다. 원문 사실 검증에는 서버 접근 키가 필요합니다."
    @State private var showPicker = false
    @State private var setupError = ""
    @State private var showSetupError = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case endpoint, token }
    let green = Color(red: 0.10, green: 0.29, blue: 0.23)
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                Text("▶  ReelProof").font(.title2.bold()).foregroundStyle(green)
                Text("넘기기 전에,\n한 번 더 확인.").font(.system(size: 36, weight: .semibold)).foregroundStyle(green)
                Text("음성·화면 자막에서 주장을 선별하고, 원문 근거를 확인합니다.").font(.subheadline).foregroundStyle(.secondary)
                TextField("검증 서버 HTTPS 주소", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .endpoint)
                    .accessibilityIdentifier("serverEndpoint")
                SecureField("검증 서버 접근 키", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .token)
                Text("Gemini API 키는 서버의 비밀 설정에 등록하세요. 이 앱에는 별도로 발급된 검증 서버 접근 키를 입력합니다.").font(.footnote).foregroundStyle(.secondary)
                Button(action: prepareDetection) {
                    Text("탐지 준비").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).background(green).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("prepareDetection")
                VStack(alignment: .leading, spacing: 12) {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("preparationStatus")
                    if showPicker {
                        HStack {
                            BroadcastPicker().frame(width: 64, height: 64)
                            Text("시스템 녹화 시작\nReelProof 선택").font(.subheadline)
                        }.accessibilityIdentifier("broadcastControls")
                        Text("준비만으로 탐지가 시작되지는 않습니다. 위의 시스템 녹화 버튼에서 방송 시작을 눌러주세요.").font(.footnote)
                    }
                }.id("preparationStatus")
                Text("화면 녹화 동의는 iOS의 필수 단계입니다. 제어 센터의 녹화를 중지하면 탐지도 종료됩니다. 원본 앱이 캡처를 막으면 추출할 수 없습니다.").font(.footnote).foregroundStyle(.secondary)
                Text("서버 접근 키가 없으면 자막의 AI 대본 문체만 기기에서 분석합니다. 이 알림은 실험 신호이며 영상 제작 출처나 진위를 확정하지 않습니다. 실제 릴스 성능은 평가하지 않았습니다.").font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("공유 권한 진단") {
                    Text(AppConfiguration.sharingDiagnostics).font(.caption).textSelection(.enabled)
                    Button("권한 진단 복사") { UIPasteboard.general.string = AppConfiguration.sharingDiagnostics }
                }.font(.footnote)
                Text("개인 테스트 0.4.4 (7)").font(.caption2).foregroundStyle(.secondary)
            }.padding(28) }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: showPicker) { ready in
                if ready { withAnimation { proxy.scrollTo("preparationStatus", anchor: .center) } }
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.95))
        .alert("탐지 준비 확인", isPresented: $showSetupError) {
            Button("확인", role: .cancel) { }
        } message: { Text(setupError) }
        .onOpenURL { _ in message = "검증 서버 설정을 확인한 뒤 탐지를 준비하세요." }
    }
    private func failSetup(_ reason: String) {
        message = reason; setupError = reason; showSetupError = true
    }
    private func prepareDetection() {
        focusedField = nil
        showPicker = false
        message = "준비 중 · 설정을 확인하고 있습니다."
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedEndpoint), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else {
            failSetup("검증 서버 주소를 확인하세요. https://reelproof-evidence.vercel.app 형식의 HTTPS 주소가 필요합니다.")
            return
        }
        guard let store = AppConfiguration.sharedDefaults else {
            failSetup("공유 설정 권한을 확인하지 못했습니다.\n\n\(AppConfiguration.sharingDiagnostics)\n\nApp Group이 실제로 허용된 프로필로 앱과 방송 확장을 함께 서명해야 합니다. iPhone의 마이크·알림 허용으로 추가되는 권한은 아닙니다.")
            return
        }
        store.set(normalizedEndpoint, forKey: "serverURL")
        store.set(token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "serverToken")
        showPicker = true
        message = "준비되었습니다. 시스템 녹화 버튼에서 ReelProof 방송을 시작한 뒤 릴스 앱으로 이동하세요."
        // The system picker is available immediately; notification authorization
        // is a separate asynchronous step and must not gate its appearance.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if !granted {
                    message = error == nil ? "녹화 버튼은 준비되었습니다. 결과 알림을 받으려면 설정 → 알림 → ReelProof Test에서 알림을 허용하세요." : "녹화 버튼은 준비되었습니다. 알림 권한을 확인하지 못했습니다. iPhone 설정에서 알림을 확인하세요."
                }
            }
        }
    }
}
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: .zero)
        view.preferredExtension = AppConfiguration.broadcastExtension
        view.showsMicrophoneButton = false
        return view
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
