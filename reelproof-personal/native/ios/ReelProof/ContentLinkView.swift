import SwiftUI
import UIKit
import UserNotifications

@MainActor final class ContentLinkModel: ObservableObject {
    struct ClaimResult: Identifiable {
        let id = UUID()
        let claim: String, verdict: String, reason: String
        let evidence: [[String: String]]
    }
    @Published var busy = false
    @Published var status = "링크의 내용을 읽고 사실 주장을 최대 3개 찾아 검증합니다."
    @Published var notificationNotice = ""
    @Published var sourceTitle = ""
    @Published var scope = ""
    @Published var excerpt = ""
    @Published var claims: [String] = []
    @Published var results: [ClaimResult] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    func start(url: String, offset: String, endpoint: String, token: String) {
        guard !busy else { return }
        let input = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: input), parsed.scheme?.lowercased() == "https", parsed.host != nil else { status = "공개 HTTPS 영상 또는 기사 링크를 입력하세요."; return }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "저장된 연결이 없습니다. 기본 화면의 연결 설정을 확인하세요."; return }
        let base = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let api = URL(string: base + "/v1/content/stream"), api.scheme == "https", api.host != nil, api.user == nil, api.password == nil else { status = "검증 서버 주소를 확인하세요."; return }
        var payload: [String: Any] = ["url": input, "duration_seconds": 60]
        if !offset.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let seconds = Int(offset), seconds >= 0, seconds <= 43200 else { status = "영상 시작 위치는 0~43200 사이의 초 단위 숫자로 입력하세요."; return }
            payload["start_seconds"] = seconds
        }
        let run = UUID(); generation = run
        busy = true; sourceTitle = ""; scope = ""; excerpt = ""; claims = []; results = []
        status = "영상·기사 내용을 추출하고 있습니다. 이 화면을 열어 두세요."
        task = Task {
            defer { if self.generation == run { self.busy = false; self.task = nil } }
            do {
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
                self.notificationNotice = granted ? "" : "알림 권한이 없어 결과는 이 화면에 표시합니다."
                var request = URLRequest(url: api); request.httpMethod = "POST"; request.timeoutInterval = 210
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer " + token.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (bytes, response) = try await BroadcastHTTPClient.session.bytes(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, response.mimeType == "application/x-ndjson" else {
                    throw VerificationStream.Failure(status: code, message: code == 401 || code == 403 ? "저장된 서버 연결이 만료됐습니다. 연결 설정을 확인하세요." : "내용 추출 서버에 연결하지 못했습니다. HTTP \(code)")
                }
                var stream = VerificationStream()
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard self.generation == run else { return }
                    guard let event = try stream.consume(line) else { continue }
                    switch event {
                    case .content(let value):
                        self.sourceTitle = value["title"] as? String ?? "검증 대상"
                        self.scope = value["scope"] as? String ?? ""
                        self.excerpt = value["excerpt"] as? String ?? ""
                        self.claims = (value["claims"] as? [[String: Any]] ?? []).compactMap { $0["claim"] as? String }
                        self.status = self.claims.isEmpty ? "검증할 사실 주장을 찾지 못했습니다." : "주장 \(self.claims.count)개를 찾았습니다. 원문 근거와 대조하고 있습니다."
                    case .result(let value):
                        if value["status"] as? String == "skipped" {
                            self.status = value["message"] as? String ?? "검증할 주장이 없습니다."
                        } else {
                            for item in value["claims"] as? [[String: Any]] ?? [] {
                                let result = ClaimResult(claim: item["claim"] as? String ?? "", verdict: item["verdict"] as? String ?? "NOT_ENOUGH_INFO", reason: item["reason"] as? String ?? "근거 부족", evidence: item["evidence"] as? [[String: String]] ?? [])
                                self.results.append(result)
                                let content = UNMutableNotificationContent()
                                content.title = Self.verdictLabel(result.verdict)
                                content.body = String(result.claim.prefix(90)) + "\n" + String(result.reason.prefix(140))
                                do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: result.id.uuidString, content: content, trigger: nil)) }
                                catch { self.notificationNotice = "알림을 요청하지 못했습니다. 이 화면에서 결과를 확인하세요." }
                            }
                        }
                    case .done:
                        if !self.results.isEmpty { self.status = "\(self.results.count)개 주장 확인 완료 · 영상·기사 전체의 진위 판정은 아닙니다." }
                    }
                    if stream.finished { break }
                }
                guard stream.finished else { throw VerificationStream.Failure(status: 502, message: "연결이 중간에 끊겼습니다. 이미 표시된 결과는 해당 주장에 대한 판정입니다.") }
            } catch is CancellationError {
                if self.generation == run { self.status = "요청을 중단했습니다." }
            } catch {
                if self.generation == run { self.status = (error as? VerificationStream.Failure)?.message ?? "요청을 완료하지 못했습니다. \(error.localizedDescription)" }
            }
        }
    }
    static func verdictLabel(_ value: String) -> String {
        value == "SUPPORTS" ? "원문 근거가 뒷받침함" : value == "REFUTES" ? "원문 근거와 충돌함" : "근거 부족 · 판별 불가"
    }
}

struct ContentLinkView: View {
    let endpoint: String, token: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ContentLinkModel()
    @State private var link = ""
    @State private var offset = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("유튜브 영상·뉴스 기사") {
                    TextField("공개 HTTPS 링크", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("contentURL")
                    Button("클립보드 링크 붙여넣기") { link = UIPasteboard.general.string ?? "" }
                    TextField("유튜브 시작 위치 · 초 (선택)", text: $offset).keyboardType(.numberPad)
                    Text("영상은 지정 위치부터 60초 구간을 읽습니다. 위치를 비우면 링크의 시작 시각을 사용합니다. 기사는 추출한 본문에서 주장을 찾습니다. 로그인·유료·캡처 보호 콘텐츠는 읽지 못할 수 있습니다.").font(.caption)
                    Button(model.busy ? "내용 추출·검증 중…" : "내용에서 주장 찾고 검증") { model.start(url: link, offset: offset, endpoint: endpoint, token: token) }.disabled(model.busy).accessibilityIdentifier("verifyContentLink")
                    if model.busy { Button("요청 중단") { model.cancel(); model.status = "요청을 중단했습니다." } }
                }
                Section("진행 상태") {
                    Text(model.status).font(.footnote).accessibilityIdentifier("contentLinkStatus")
                    if !model.notificationNotice.isEmpty { Text(model.notificationNotice).font(.caption) }
                }
                if !model.sourceTitle.isEmpty {
                    Section("추출한 내용") {
                        Text(model.sourceTitle).font(.headline)
                        Text(model.scope).font(.caption)
                        Text(model.excerpt).font(.footnote).textSelection(.enabled)
                        ForEach(Array(model.claims.enumerated()), id: \.offset) { item in Text("\(item.offset + 1). \(item.element)").font(.footnote) }
                    }
                }
                ForEach(model.results) { result in
                    Section(ContentLinkModel.verdictLabel(result.verdict)) {
                        Text(result.claim).font(.headline)
                        Text(result.reason).font(.footnote)
                        ForEach(Array(result.evidence.enumerated()), id: \.offset) { item in
                            Text(item.element["quote"] ?? "").font(.footnote).textSelection(.enabled)
                            if let source = item.element["source"], let url = URL(string: source), url.scheme == "https" { Link("검증 근거 원문 보기", destination: url) }
                        }
                    }
                }
                Section { Text("결과는 선별한 개별 주장에 대한 검증입니다. 입력한 기사 자체를 근거로 다시 확인하지 않습니다. 검색·모델 사용 한도나 원문 부족으로 판별하지 못할 수 있습니다.").font(.caption) }
            }
            .navigationTitle("영상·기사 링크 검증")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { model.cancel(); dismiss() } } }
            .onDisappear { model.cancel() }
        }
    }
}
