import SwiftUI
import ReplayKit
import UserNotifications
import UIKit
// Keep the settings screen usable when a signing tool removed shared rights.
// Local preferences are never used as an extension-sharing substitute.
let sharedStore = AppConfiguration.sharedDefaults ?? .standard
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
@main struct ReelProofApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) var delegate
    var body: some Scene { WindowGroup { ContentView() } }
}
struct ContentView: View {
    @AppStorage("serverURL", store: sharedStore) var endpoint = "https://reelproof-evidence.vercel.app"
    @AppStorage("serverToken", store: sharedStore) var token = ""
    @State private var message = "AI 대본 문체는 기기에서 분석합니다. 원문 사실 검증에는 서버 접근 키가 필요합니다."
    @State private var showPicker = false
    @State private var preparing = false
    @State private var pairing: BroadcastPairing?
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
                .disabled(preparing)
                VStack(alignment: .leading, spacing: 12) {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("preparationStatus")
                    if preparing { ProgressView("서버에서 방송 연결 키를 발급하고 있습니다.") }
                    if let pairing = pairing, let image = pairing.qrImage() {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = Int(ceil(pairing.acceptUntil - context.date.timeIntervalSince1970))
                            if remaining > 0 {
                                Image(uiImage: UIImage(cgImage: image)).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth: 240).padding(16).background(.white)
                                    .accessibilityLabel("방송 확장 연결 QR").accessibilityIdentifier("broadcastPairingQR")
                                Text("연결 QR 유효 시간 \(remaining)초 · 방송 시작 후 이 화면에 머무르세요.").font(.footnote)
                            } else {
                                Text("연결 QR이 만료되었습니다. 탐지 준비를 다시 누르세요.").font(.footnote)
                            }
                        }
                        Text("카메라로 스캔하지 않습니다. 아래에서 방송을 시작하면 확장이 이 화면의 QR을 읽습니다. ‘방송 연결 완료’ 알림이 온 뒤 릴스 앱으로 이동하세요. QR은 검증 전용 임시 키이므로 다른 사람에게 공유하지 마세요.").font(.footnote)
                    }
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
                DisclosureGroup("연결 권한 진단") {
                    Text(AppConfiguration.sharingDiagnostics).font(.caption).textSelection(.enabled)
                    Button("권한 진단 복사") { UIPasteboard.general.string = AppConfiguration.sharingDiagnostics }
                }.font(.footnote)
                Text("공유 권한이 없으면 화면 QR로 연결합니다. 카메라·App Group 권한은 이 연결에 필요하지 않습니다.").font(.footnote).foregroundStyle(.secondary)
                Text("개인 테스트 0.4.6 (9)").font(.caption2).foregroundStyle(.secondary)
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
        pairing = nil
        message = "준비 중 · 설정을 확인하고 있습니다."
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedEndpoint), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else {
            failSetup("검증 서버 주소를 확인하세요. https://reelproof-evidence.vercel.app 형식의 HTTPS 주소가 필요합니다.")
            return
        }
        do {
            guard AppConfiguration.broadcastExtension != nil else {
                failSetup("방송 확장이 없습니다. Sideloadly에서 확장을 유지해 앱과 함께 설치하세요."); return
            }
            let method = try AppConfiguration.saveConnection(endpoint: normalizedEndpoint, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
            message = method
        } catch {
            preparePairing(endpoint: normalizedEndpoint)
            return
        }
        showPicker = true
        message = "준비되었습니다. 시스템 녹화 버튼에서 ReelProof 방송을 시작한 뒤 릴스 앱으로 이동하세요."
        // The system picker is available immediately; notification authorization
        // is a separate asynchronous step and must not gate its appearance.
        requestNotifications()
    }
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if !granted {
                    message += "\n결과·연결 알림을 받으려면 설정 → 알림 → ReelProof Test에서 알림을 허용하세요."
                }
            }
        }
    }
    private func preparePairing(endpoint: String) {
        guard BroadcastPairing.isProductionServer(endpoint) else {
            failSetup("공유 권한 없는 QR 연결은 https://reelproof-evidence.vercel.app 서버만 지원합니다."); return
        }
        let appKey = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appKey.isEmpty else {
            failSetup("공유 권한 없이 QR로 연결할 수 있습니다. 먼저 검증 서버 접근 키를 입력하고 탐지 준비를 다시 누르세요."); return
        }
        preparing = true
        message = "공유 권한 대신 화면 QR 연결을 준비합니다."
        Task { @MainActor in
            defer { preparing = false }
            do {
                var request = URLRequest(url: URL(string: BroadcastPairing.productionEndpoint + "/v1/device-session")!)
                request.httpMethod = "POST"; request.timeoutInterval = 45
                request.setValue("Bearer " + appKey, forHTTPHeaderField: "Authorization")
                let (data, response) = try await BroadcastHTTPClient.session.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw BroadcastPairing.PairingError(reason: status == 401 || status == 403 ? "검증 서버 접근 키가 올바르지 않거나 만료되었습니다. 원본 앱 접근 키를 확인하세요." : "방송 연결 키를 발급하지 못했습니다. 서버 연결을 확인하세요. (\(status))")
                }
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let session = result["token"] as? String else {
                    throw BroadcastPairing.PairingError(reason: "방송 연결 키 응답 형식 오류")
                }
                pairing = try BroadcastPairing.create(token: session)
                showPicker = true
                message = "QR 연결 준비 완료. 아래 시스템 녹화에서 방송 시작을 누르고, 연결 완료 알림까지 이 화면을 유지하세요. 방송 연결 키는 최대 30분 동안 유효합니다."
                requestNotifications()
            } catch { failSetup("QR 연결 준비 실패 · \(error.localizedDescription)") }
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
