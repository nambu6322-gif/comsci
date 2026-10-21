import ReplayKit
import Vision
import UserNotifications
import AVFoundation
final class SampleHandler: RPBroadcastSampleHandler {
    var connection: ServerConnection?
    var statusObserver: BroadcastEvents.Observer?
    var sessionExpiry: TimeInterval?
    var pairingDeadline = 0.0
    var validatingPairing = false
    var lastPairingAttempt = 0.0
    let queue = DispatchQueue(label: "ReelProof.analysis")
    let frameLock = NSLock()
    var frameQueued = false
    var selector: TextModel?; var modernStyle: TextModel?; var lastStyleAlert = 0.0; var lastFrame = 0.0; var lastText = ""; var analyzingFrame = false; var requesting = false; var active = false
    var writer: AVAssetWriter?; var audioInput: AVAssetWriterInput?; var audioURL: URL?; var audioStart = CMTime.zero
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        queue.async {
            self.connection = (try? AppConfiguration.loadConnection()).flatMap { $0.valid ? $0 : nil }
            self.sessionExpiry = nil
            self.pairingDeadline = Date().timeIntervalSince1970 + 45
            self.selector = try? TextModel(filename: "selector-model")
            self.modernStyle = try? TextModel(filename: "modern-ai-text-model")
            self.active = true
            if self.connection != nil { self.announceConnection() }
        }
    }
    override func broadcastPaused() { queue.async { self.active = false; self.discardAudio() } }
    override func broadcastResumed() { queue.async { self.active = true; if self.connection != nil { self.announceConnection() } } }
    override func broadcastFinished() { queue.async { BroadcastEvents.post(session: self.connection?.sessionID, event: .stopped); self.statusObserver = nil; self.active = false; self.connection = nil; self.discardAudio() } }
    func discardAudio() { writer?.cancelWriting(); if let url = audioURL { try? FileManager.default.removeItem(at: url) }; writer = nil; audioInput = nil; audioURL = nil }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video || sampleBufferType == .audioApp else { return }
        if sampleBufferType == .video {
            frameLock.lock()
            if frameQueued { frameLock.unlock(); return }
            frameQueued = true; frameLock.unlock()
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            defer {
                if sampleBufferType == .video { self.frameLock.lock(); self.frameQueued = false; self.frameLock.unlock() }
            }
            self.process(sampleBuffer, type: sampleBufferType)
        }
    }
    private func process(_ sampleBuffer: CMSampleBuffer, type sampleBufferType: RPSampleBufferType) {
        guard active else { return }
        let now = Date().timeIntervalSince1970
        if let expiry = sessionExpiry, now >= expiry {
            stop("방송 연결 키가 만료되었습니다. ReelProof에서 탐지 준비를 다시 누르고 방송을 시작하세요."); return
        }
        if connection == nil {
            guard now < pairingDeadline else {
                stop("자동 연결을 완료하지 못했습니다. ReelProof에서 탐지 준비를 다시 누르고 ‘탐지 중’이 표시될 때까지 앱 화면을 유지하세요."); return
            }
            guard sampleBufferType == .video, !validatingPairing, now - lastFrame >= 0.5,
                  now - lastPairingAttempt >= 3, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lastFrame = now
            readPairing(buffer)
            return // No audio, OCR, style analysis or content upload before authentication.
        }
        if sampleBufferType == .audioApp { if !(connection?.token ?? "").isEmpty { processAudio(sampleBuffer) }; return }
        guard sampleBufferType == .video, !analyzingFrame, Date().timeIntervalSince1970 - lastFrame >= 2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date().timeIntervalSince1970; analyzingFrame = true
        do {
            defer { self.analyzingFrame = false }
            let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["ko-KR", "en-US"]; request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.018
            do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]); let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                if text.count > 15, text != self.lastText { self.lastText = text; self.analyzeStyle(text); if let model = self.selector, model.score(text) >= model.threshold { self.send(path: "/v1/analyze", data: try JSONSerialization.data(withJSONObject: ["text": text, "source": "screen"]), type: "application/json") } }
            } catch { self.notify("자막 판별 불가", "화면 문자 인식 또는 보호된 화면 오류입니다.") }
        }
    }
    private func readPairing(_ buffer: CVPixelBuffer) {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        guard (try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])) != nil,
              let value = (request.results ?? []).compactMap({ result -> BroadcastPairing? in
                  guard let text = result.payloadStringValue else { return nil }
                  return try? BroadcastPairing.decode(text)
              }).first,
              let pending = try? value.validated() else { return }
        lastPairingAttempt = Date().timeIntervalSince1970; validatingPairing = true
        var check = URLRequest(url: URL(string: BroadcastPairing.productionEndpoint + "/v1/device-session")!)
        check.timeoutInterval = 20; check.setValue("Bearer " + pending.token, forHTTPHeaderField: "Authorization")
        BroadcastHTTPClient.session.dataTask(with: check) { [weak self] data, response, error in
            guard let self = self else { return }
            self.queue.async {
                self.validatingPairing = false
                guard self.active, self.connection == nil else { return }
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data = data,
                      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], result["valid"] as? Bool == true,
                      result["scope"] as? String == "analyze", let expiry = result["expires_at"] as? Double,
                      expiry == value.sessionExpiry, (try? value.validated()) != nil else {
                    self.notify("방송 연결 확인 실패", "원본 접근 키와 서버 연결을 확인하고, 탐지 준비를 다시 눌러 새 QR을 만드세요."); return
                }
                self.connection = pending; self.sessionExpiry = expiry
                self.lastText = ""; self.lastFrame = Date().timeIntervalSince1970
                self.announceConnection()
                self.notify("탐지 시작 · 릴스를 시청하세요", "음성·자막에서 검증할 주장을 골라 원문과 대조하고 결과를 알립니다.")
            }
        }.resume()
    }
    private func stop(_ message: String) {
        BroadcastEvents.post(session: connection?.sessionID, event: .stopped)
        statusObserver = nil
        active = false; connection = nil; discardAudio()
        finishBroadcastWithError(NSError(domain: "ReelProof", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
    }
    private func announceConnection() {
        guard let session = connection?.sessionID else { return }
        let observer = BroadcastEvents.Observer()
        observer.listen(session: session) { [weak self] event in
            guard event == .statusRequest, let self = self else { return }
            self.queue.async {
                guard self.connection?.sessionID == session else { return }
                BroadcastEvents.post(session: session, event: self.active ? .connected : .stopped)
            }
        }
        statusObserver = observer
        BroadcastEvents.post(session: session, event: .connected)
    }
    func analyzeStyle(_ text: String) {
        guard text.count >= 80, text.split(whereSeparator: { $0.isWhitespace }).count >= 12, text.unicodeScalars.filter({ $0.value >= 0xAC00 && $0.value <= 0xD7A3 }).count >= 20, Date().timeIntervalSince1970 - lastStyleAlert >= 30, let model = modernStyle, model.score(text) >= model.threshold else { return }
        lastStyleAlert = Date().timeIntervalSince1970
        notify("AI 대본 문체와 유사 · 실험 신호", "기기 내 텍스트 모델의 참고 신호입니다. 영상의 AI 제작 여부나 주장 진위를 확정하지 않습니다.")
    }
    func processAudio(_ sample: CMSampleBuffer) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer == nil {
            guard let description = CMSampleBufferGetFormatDescription(sample), let audio = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            guard let created = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audio.mSampleRate, AVNumberOfChannelsKey: Int(audio.mChannelsPerFrame), AVEncoderBitRateKey: 64000], sourceFormatHint: description)
            input.expectsMediaDataInRealTime = true; guard created.canAdd(input) else { return }; created.add(input); guard created.startWriting() else { return }; created.startSession(atSourceTime: timestamp)
            writer = created; audioInput = input; audioStart = timestamp; audioURL = url
        }
        guard let current = writer, let input = audioInput, current.status == .writing else { discardAudio(); return }
        if input.isReadyForMoreMediaData { _ = input.append(sample) }
        if CMTimeGetSeconds(CMTimeSubtract(timestamp, audioStart)) >= 8 {
            let url = audioURL; input.markAsFinished(); writer = nil; audioInput = nil; audioURL = nil
            current.finishWriting { [weak self] in
                guard let self = self, let url = url else { return }
                self.queue.async {
                    defer { try? FileManager.default.removeItem(at: url) }
                    if self.active, current.status == .completed, let data = try? Data(contentsOf: url) { self.send(path: "/v1/audio", data: data, type: "audio/mp4") }
                }
            }
        }
    }
    func send(path: String, data: Data, type: String) {
        guard active, !requesting, !(connection?.token ?? "").isEmpty, let base = connection?.endpoint, let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path), url.scheme == "https" else { return }
        requesting = true; var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = data; request.timeoutInterval = 140; request.setValue(type, forHTTPHeaderField: "Content-Type"); request.setValue("Bearer " + (connection?.token ?? ""), forHTTPHeaderField: "Authorization")
        BroadcastHTTPClient.session.dataTask(with: request) { [weak self] body, response, error in
            guard let self = self else { return }
            self.queue.async {
            defer { self.requesting = false }; guard self.active else { return }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let body = body, let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { self.notify("판별 불가 · 서버 연결 확인", "오디오·주장 검증 서버에서 정상 응답을 받지 못했습니다."); return }
            if value["status"] as? String == "skipped" { return }
            let verdict = value["verdict"] as? String ?? "NOT_ENOUGH_INFO"
            self.notify(verdict == "REFUTES" ? "원문 근거와 충돌합니다" : verdict == "SUPPORTS" ? "원문 근거가 뒷받침합니다" : "판별 불가 · 근거 부족", value["message"] as? String ?? "확인할 근거가 부족합니다.")
            }
        }.resume()
    }
    func notify(_ title: String, _ message: String) { let content = UNMutableNotificationContent(); content.title = title; content.body = message; UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
}
