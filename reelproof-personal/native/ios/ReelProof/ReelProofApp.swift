import SwiftUI
import ReplayKit
import UserNotifications
import UIKit

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
final class BroadcastSessionStatus: ObservableObject {
    enum Phase: Equatable { case idle, waiting, detecting, stopped }
    @Published private(set) var phase = Phase.idle
    private var session: String?
    private let observer = BroadcastEvents.Observer()
    func wait(for session: String) {
        self.session = session; phase = .waiting
        observer.listen(session: session) { [weak self] event in
            switch event {
            case .connected: self?.phase = .detecting
            case .stopped: self?.phase = .stopped
            case .statusRequest: break
            }
        }
    }
    func reset() { observer.stop(); session = nil; phase = .idle }
    func refresh(recording: Bool) {
        guard let session = session else { return }
        guard recording else { observer.stop(); self.session = nil; phase = .stopped; return }
        phase = .waiting
        BroadcastEvents.post(session: session, event: .statusRequest)
    }
}
@main struct ReelProofApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) var delegate
    var body: some Scene { WindowGroup { ContentView() } }
}
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("serverURL", store: sharedStore) var endpoint = "https://reelproof-evidence.vercel.app"
    @AppStorage("serverToken", store: sharedStore) var token = ""
    @StateObject private var broadcast = BroadcastSessionStatus()
    @State private var message = "탐지 준비를 누르고 iOS에서 방송 시작을 확인하세요. 탐지 중으로 바뀌면 릴스를 시청하면 됩니다."
    @State private var showPicker = false
    @State private var pickerRequest = 0
    @State private var preparing = false
    @State private var pairing: BroadcastPairing?
    @State private var setupError = ""
    @State private var showSetupError = false
    @State private var needsNotificationSettings = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case endpoint, token }
    let green = Color(red: 0.10, green: 0.29, blue: 0.23)
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                Text("▶  ReelProof").font(.title2.bold()).foregroundStyle(green)
                Text("준비하고,\n릴스를 시청하세요.").font(.system(size: 34, weight: .semibold)).foregroundStyle(green)
                Text("음성·자막의 주장을 원문과 대조하고, 근거가 뒷받침하는지·충돌하는지·부족한지 알립니다.").font(.subheadline).foregroundStyle(.secondary)
                TextField("검증 서버 HTTPS 주소", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .endpoint)
                    .accessibilityIdentifier("serverEndpoint")
                SecureField("검증 서버 접근 키", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .token)
                Text("처음에만 서버 접근 키를 설정합니다. Gemini API 키는 서버에 등록합니다.").font(.footnote).foregroundStyle(.secondary)
                if broadcast.phase != .detecting {
                    Button(action: prepareDetection) {
                        Text(showPicker ? "방송 시작 창 다시 열기" : "탐지 준비").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).background(green).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("prepareDetection").disabled(preparing)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if broadcast.phase == .detecting {
                        Label("탐지 중 · 릴스를 시청하세요", systemImage: "waveform.circle.fill")
                            .font(.headline).foregroundStyle(green).accessibilityIdentifier("detectionActive")
                    }
                    Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("preparationStatus")
                    if preparing { ProgressView("탐지 시작을 준비하고 있습니다.") }
                    if let pairing = pairing, let image = pairing.qrImage() {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if context.date.timeIntervalSince1970 < pairing.acceptUntil {
                                Text("자동 연결 중").font(.subheadline.bold())
                                Image(uiImage: UIImage(cgImage: image)).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth: 240).padding(16).background(.white)
                                    .accessibilityLabel("자동 연결 정보").accessibilityIdentifier("broadcastPairingQR")
                                Text("직접 스캔할 필요가 없습니다. 방송 시작 후 ‘탐지 중’으로 바뀔 때까지 이 화면을 유지하세요.").font(.footnote)
                            } else {
                                Text("연결 대기 시간이 끝났습니다. 탐지 준비를 다시 눌러주세요.").font(.footnote)
                            }
                        }
                    }
                    if showPicker {
                        HStack {
                            BroadcastPicker(request: pickerRequest) {
                                message = "iOS 방송 창을 자동으로 열지 못했습니다. 아래 시스템 녹화 버튼에서 방송 시작을 눌러주세요."
                            }.frame(width: 64, height: 64)
                            Text("iOS 방송 시작 확인\n자동으로 열리지 않으면 왼쪽 버튼").font(.subheadline)
                        }.accessibilityIdentifier("broadcastControls")
                    }
                }.id("preparationStatus")
                Text("iOS의 방송 시작 확인은 필수입니다. 탐지는 제어 센터의 화면 녹화 중지로 종료합니다. 캡처가 보호된 영상은 추출할 수 없습니다.").font(.footnote).foregroundStyle(.secondary)
                Text("근거가 부족하면 판별 불가로 알립니다. AI 대본 문체 알림은 참고 신호이며 영상의 AI 제작 여부를 확정하지 않습니다.").font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("공유 저장소 진단 · 자동 연결과 별도") {
                    Text(AppConfiguration.sharingDiagnostics).font(.caption).textSelection(.enabled)
                    Button("권한 진단 복사") { UIPasteboard.general.string = AppConfiguration.sharingDiagnostics }
                }.font(.footnote)
                Text("개인 테스트 0.4.7 (10)").font(.caption2).foregroundStyle(.secondary)
            }.padding(28) }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: showPicker) { ready in
                if ready { withAnimation { proxy.scrollTo("preparationStatus", anchor: .center) } }
            }
            .onChange(of: broadcast.phase) { phase in
                if phase == .detecting {
                    pairing = nil; showPicker = false
                    message = "릴스·쇼츠 앱으로 이동하세요. 음성·자막에서 검증할 주장을 골라 분석하고 결과를 알립니다."
                    withAnimation { proxy.scrollTo("preparationStatus", anchor: .center) }
                } else if phase == .stopped {
                    pairing = nil; showPicker = false
                    message = "탐지가 중지되었습니다. 다시 시작하려면 탐지 준비를 누르세요."
                }
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.95))
        .alert("탐지 준비 확인", isPresented: $showSetupError) {
            if needsNotificationSettings {
                Button("알림 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
            Button("확인", role: .cancel) { }
        } message: { Text(setupError) }
        .onChange(of: scenePhase) { phase in
            if phase == .active, broadcast.phase == .detecting { broadcast.refresh(recording: UIScreen.main.isCaptured) }
        }
    }
    private func failSetup(_ reason: String) {
        broadcast.reset(); showPicker = false; pairing = nil
        message = reason; setupError = reason; showSetupError = true
    }
    private func prepareDetection() {
        focusedField = nil
        if showPicker, pairing.map({ $0.acceptUntil > Date().timeIntervalSince1970 }) ?? true {
            pickerRequest += 1; return
        }
        broadcast.reset(); showPicker = false; pairing = nil; needsNotificationSettings = false
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedEndpoint), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else {
            failSetup("검증 서버 주소를 확인하세요. HTTPS 주소가 필요합니다."); return
        }
        let appKey = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appKey.isEmpty else { failSetup("검증 결과를 받으려면 검증 서버 접근 키를 먼저 입력하세요."); return }
        guard AppConfiguration.broadcastExtension != nil else { failSetup("방송 확장이 없습니다. 확장을 유지해 앱과 함께 설치하세요."); return }
        preparing = true; message = "탐지 시작에 필요한 연결과 알림을 준비합니다."
        Task { @MainActor in
            defer { preparing = false }
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    needsNotificationSettings = true
                    failSetup("릴스 시청 중 검증 결과를 받으려면 iPhone 설정에서 ReelProof 알림을 허용하세요."); return
                }
                let session = BroadcastEvents.sessionID()
                do {
                    _ = try AppConfiguration.saveConnection(endpoint: normalizedEndpoint, token: appKey, sessionID: session)
                    broadcast.wait(for: session)
                } catch {
                    guard BroadcastPairing.isProductionServer(normalizedEndpoint) else {
                        throw BroadcastPairing.PairingError(reason: "자동 연결은 https://reelproof-evidence.vercel.app 서버를 지원합니다.")
                    }
                    var request = URLRequest(url: URL(string: BroadcastPairing.productionEndpoint + "/v1/device-session")!)
                    request.httpMethod = "POST"; request.timeoutInterval = 45
                    request.setValue("Bearer " + appKey, forHTTPHeaderField: "Authorization")
                    let (data, response) = try await BroadcastHTTPClient.session.data(for: request)
                    guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        throw BroadcastPairing.PairingError(reason: status == 401 || status == 403 ? "검증 서버 접근 키가 올바르지 않거나 만료되었습니다. 원본 앱 접근 키를 확인하세요." : "검증 서버에 연결하지 못했습니다. (\(status))")
                    }
                    guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = result["token"] as? String else { throw BroadcastPairing.PairingError(reason: "서버 연결 응답 형식 오류") }
                    let value = try BroadcastPairing.create(token: token)
                    pairing = value; broadcast.wait(for: value.nonce)
                }
                message = "iOS에서 ‘방송 시작’을 확인하세요. 자동 연결 후 ‘탐지 중’으로 바뀌면 릴스를 시청하세요."
                showPicker = true; pickerRequest += 1
            } catch { failSetup("탐지 준비 실패 · \(error.localizedDescription)") }
        }
    }
}
struct BroadcastPicker: UIViewRepresentable {
    let request: Int
    var unavailable: () -> Void
    final class Coordinator {
        let action = BroadcastPickerAction()
        var requested = 0
        func present(_ view: RPSystemBroadcastPickerView, request: Int, unavailable: @escaping () -> Void) {
            guard request > 0, request != requested else { return }
            requested = request
            func attempt(_ remaining: Int) {
                guard self.requested == request else { return }
                if self.action.open(view, request: request) { return }
                if view.window == nil, remaining > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt(remaining - 1) } }
                else { unavailable() }
            }
            DispatchQueue.main.async { attempt(10) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: .zero)
        view.preferredExtension = AppConfiguration.broadcastExtension; view.showsMicrophoneButton = false
        return view
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        context.coordinator.present(uiView, request: request, unavailable: unavailable)
    }
}
