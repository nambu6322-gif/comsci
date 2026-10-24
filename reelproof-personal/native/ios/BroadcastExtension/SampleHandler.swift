import ReplayKit
import Vision
import UserNotifications
import AVFoundation

final class SampleHandler: RPBroadcastSampleHandler {
    var connection: ServerConnection?
    var statusObserver: BroadcastEvents.Observer?
    var sessionExpiry: TimeInterval?
    var pairingDeadline = 0.0, lastPairingAttempt = 0.0
    var validatingPairing = false, active = false
    let queue = DispatchQueue(label: "ReelProof.analysis")
    let frameLock = NSLock()
    var frameQueued = false
    var selector: TextModel?, modernStyle: TextModel?
    var lastStyleAlert = 0.0, lastFrame = 0.0, lastText = ""
    let work = VerificationWorkQueue()
    var tasks: [VerificationWorkQueue.Lane: Task<Void, Never>] = [:]
    var diagnostics: [String: BroadcastEvents.Event] = [:]
    var eventTimes: [BroadcastEvents.Event: TimeInterval] = [:], noticeTimes: [String: TimeInterval] = [:]
    var watchdog: DispatchSourceTimer?
    var firstRequestAt: TimeInterval?, connectedAt: TimeInterval?
    var sawFrame = false, sawAudio = false, sawText = false, warnedNoInput = false, announced = false
    var writer: AVAssetWriter?, audioInput: AVAssetWriterInput?, audioURL: URL?
    var audioStart = CMTime.zero
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.async {
            self.connection = (try? AppConfiguration.loadConnection()).flatMap { $0.valid ? $0 : nil }
            self.sessionExpiry = nil; self.pairingDeadline = Date().timeIntervalSince1970 + 45
            do { self.selector = try TextModel(filename: "selector-model") }
            catch { self.record(.modelFailed) }
            self.modernStyle = try? TextModel(filename: "modern-ai-text-model")
            self.active = true
            if self.connection != nil { self.announceConnection() }
        }
    }
    override func broadcastPaused() { queue.async { self.active = false; self.clearWork(); self.discardAudio() } }
    override func broadcastResumed() { queue.async { self.active = true; if self.connection != nil { self.announceConnection() } } }
    override func broadcastFinished() { queue.async { self.disconnect() } }
    private func clearWork() { tasks.values.forEach { $0.cancel() }; tasks = [:]; work.reset() }
    private func disconnect() {
        BroadcastEvents.post(session: connection?.sessionID, event: .stopped)
        active = false; statusObserver = nil; watchdog?.cancel(); watchdog = nil
        clearWork(); discardAudio(); connection = nil
    }
    private func stop(_ message: String) {
        disconnect()
        finishBroadcastWithError(NSError(domain: "ReelProof", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
    }
    func discardAudio() {
        writer?.cancelWriting(); if let url = audioURL { try? FileManager.default.removeItem(at: url) }
        writer = nil; audioInput = nil; audioURL = nil
    }
    override func processSampleBuffer(_ buffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video || sampleBufferType == .audioApp else { return }
        if sampleBufferType == .video {
            frameLock.lock(); if frameQueued { frameLock.unlock(); return }; frameQueued = true; frameLock.unlock()
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            defer { if sampleBufferType == .video { self.frameLock.lock(); self.frameQueued = false; self.frameLock.unlock() } }
            self.process(buffer, type: sampleBufferType)
        }
    }
    private func process(_ sample: CMSampleBuffer, type: RPSampleBufferType) {
        guard active else { return }
        if let expiry = sessionExpiry, Date().timeIntervalSince1970 >= expiry { stop("방송 연결 키가 만료되었습니다. 앱에서 탐지 준비를 다시 눌러주세요."); return }
        if connection == nil {
            guard Date().timeIntervalSince1970 < pairingDeadline else { stop("자동 연결을 완료하지 못했습니다. 앱에서 탐지 준비를 다시 누르고 ‘탐지 중’이 될 때까지 화면을 유지하세요."); return }
            guard type == .video, !validatingPairing, now - lastFrame >= 0.5, now - lastPairingAttempt >= 3,
                  let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
            lastFrame = now; readPairing(pixels); return
        }
        if type == .audioApp { processAudio(sample); return }
        guard type == .video, now - lastFrame >= 2, let pixels = CMSampleBufferGetImageBuffer(sample) else { return }
        lastFrame = now; sawFrame = true; record(.videoFrames)
        let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["ko-KR", "en-US"]
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.018
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard text.count >= 5 else { record(.noText); return }
            sawText = true; record(.textRead)
            if text != lastText { lastText = text; analyzeStyle(text) }
            guard let selector = selector else { record(.modelFailed); return }
            let claims = selector.selectedClaims(in: text)
            guard !claims.isEmpty else { record(.noClaim); return }
            record(.claimSelected)
            let selected = claims.joined(separator: "\n")
            let body = try JSONSerialization.data(withJSONObject: ["text": selected, "source": "screen"])
            submit(VerificationWorkQueue.Work(lane: .screen, data: body, preview: claims[0], identity: Data(selected.utf8)))
        } catch { record(.noText) }
    }
    private func readPairing(_ pixels: CVPixelBuffer) {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        guard (try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])) != nil,
              let value = (request.results ?? []).compactMap({ result -> BroadcastPairing? in
                  guard let text = result.payloadStringValue else { return nil }; return try? BroadcastPairing.decode(text)
              }).first, let pending = try? value.validated() else { return }
        lastPairingAttempt = now; validatingPairing = true
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
                    self.notice(key: "pairing", title: "방송 연결 확인 실패", message: "서버 접근 키와 연결을 확인하고 탐지 준비를 다시 눌러주세요.", interval: 15); return
                }
                self.connection = pending; self.sessionExpiry = expiry; self.lastText = ""; self.lastFrame = self.now
                self.announceConnection()
            }
        }.resume()
    }
    private func announceConnection() {
        guard let session = connection?.sessionID else { return }
        let observer = BroadcastEvents.Observer()
        observer.listen(session: session) { [weak self] event in
            guard event == .statusRequest, let self = self else { return }
            self.queue.async {
                guard self.connection?.sessionID == session else { return }
                BroadcastEvents.post(session: session, event: self.active ? .connected : .stopped)
                for event in self.diagnostics.values { BroadcastEvents.post(session: session, event: event) }
            }
        }
        statusObserver = observer; BroadcastEvents.post(session: session, event: .connected)
        if !announced {
            announced = true; connectedAt = now
            notify("탐지 시작 · 릴스를 시청하세요", "음성·자막에서 검증할 주장을 선별합니다. 근거가 부족하면 판별 불가로 알립니다.")
            let timer = DispatchSource.makeTimerSource(queue: queue); timer.schedule(deadline: .now() + 15, repeating: 15)
            timer.setEventHandler { [weak self] in self?.checkNoInput() }; watchdog = timer; timer.resume()
        }
    }
    private func checkNoInput() {
        guard active, connection != nil, !warnedNoInput, firstRequestAt == nil else { return }
        warnedNoInput = true
        let reason = !sawFrame && !sawAudio ? "녹화는 시작됐지만 화면·앱 음성 샘플을 받지 못했습니다." : !sawText && !sawAudio ? "화면은 받았지만 읽을 수 있는 자막·앱 음성을 찾지 못했습니다." : selector == nil ? "기기 내 주장 선별 모델을 읽지 못했습니다." : "인식한 내용에서 검증할 주장으로 선별된 문장이 없습니다."
        notice(key: "no-input", title: "아직 검증을 시작하지 못했습니다", message: reason + " 앱의 ‘탐지 진행 확인’에서 단계를 확인하세요.", interval: 45)
    }
    private func record(_ event: BroadcastEvents.Event) {
        if let progress = event.progress { diagnostics[progress.category] = event }
        guard now - (eventTimes[event] ?? -.infinity) >= 2 else { return }
        eventTimes[event] = now; BroadcastEvents.post(session: connection?.sessionID, event: event)
    }
    func analyzeStyle(_ text: String) {
        guard text.count >= 80, text.split(whereSeparator: { $0.isWhitespace }).count >= 12,
              text.unicodeScalars.filter({ $0.value >= 0xAC00 && $0.value <= 0xD7A3 }).count >= 20,
              now - lastStyleAlert >= 30, let model = modernStyle, model.score(text) >= model.threshold else { return }
        lastStyleAlert = now
        notify("AI 대본 문체와 유사 · 실험 신호", "문체의 참고 신호이며 영상의 AI 제작 여부나 주장 진위를 확정하지 않습니다.")
    }
    func processAudio(_ sample: CMSampleBuffer) {
        sawAudio = true; record(.audioCapturing)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer == nil {
            guard let description = CMSampleBufferGetFormatDescription(sample), let audio = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { record(.audioFailed); return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            do {
                let created = try AVAssetWriter(outputURL: url, fileType: .m4a)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:audio.mSampleRate,AVNumberOfChannelsKey:Int(audio.mChannelsPerFrame),AVEncoderBitRateKey:64000], sourceFormatHint: description)
                input.expectsMediaDataInRealTime = true
                guard created.canAdd(input) else { record(.audioFailed); return };created.add(input)
                guard created.startWriting() else { record(.audioFailed); return };created.startSession(atSourceTime: timestamp)
                writer = created; audioInput = input; audioStart = timestamp; audioURL = url
            } catch { record(.audioFailed); return }
        }
        guard let current = writer, let input = audioInput, current.status == .writing else { record(.audioFailed); discardAudio(); return }
        if input.isReadyForMoreMediaData, !input.append(sample) { record(.audioFailed); discardAudio(); return }
        if CMTimeGetSeconds(CMTimeSubtract(timestamp, audioStart)) >= 8 {
            let url = audioURL;input.markAsFinished();writer = nil;audioInput = nil;audioURL = nil
            current.finishWriting { [weak self] in
                guard let self = self, let url = url else { return }
                self.queue.async {
                    defer { try? FileManager.default.removeItem(at: url) }
                    guard self.active else { return }
                    guard current.status == .completed, let data = try? Data(contentsOf: url) else { self.record(.audioFailed); return }
                    self.submit(VerificationWorkQueue.Work(lane: .audio, data: data, preview: "최근 8초의 앱 음성"))
                }
            }
        }
    }
    private func submit(_ item: VerificationWorkQueue.Work) {
        guard active, !(connection?.token ?? "").isEmpty else { return }
        switch work.offer(item, now: now) {
        case .start: start(item)
        case .queued: record(item.lane == .screen ? .screenQueued : .audioQueued)
        case .duplicate: break
        }
    }
    private func start(_ item: VerificationWorkQueue.Work) {
        guard active, let connection = connection, connection.valid else { return }
        let path = item.lane == .screen ? "/v1/analyze/stream" : "/v1/audio/stream"
        guard let url = URL(string: connection.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { return }
        if let expiry = sessionExpiry, Date().timeIntervalSince1970 >= expiry { stop("방송 연결 키가 만료되었습니다. 탐지 준비를 다시 눌러주세요."); return }
        if firstRequestAt == nil { firstRequestAt = now }
        record(item.lane == .screen ? .screenSent : .audioSent)
        var request = URLRequest(url: url);request.httpMethod = "POST";request.httpBody = item.data;request.timeoutInterval = 140
        request.setValue(item.lane == .screen ? "application/json" : "audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self, self.active, self.work.active[item.lane]?.id == item.id else { return }
            self.notice(key: "progress", title: "검증 중 · 아직 판정 없음", message: String(item.preview.prefix(80)) + "\n서버 응답을 기다리고 있습니다. 결과는 이 주장에 대한 알림으로 전달합니다.", interval: 20)
        }
        let task = Task { [weak self] in
            guard let self = self else { return }
            var status = 0
            do {
                let (bytes, response) = try await BroadcastHTTPClient.session.bytes(for: request)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, response.mimeType == "application/x-ndjson" else {
                    throw VerificationStream.Failure(status: status, message: "검증 연결 응답 오류")
                }
                var stream = VerificationStream()
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard let event = try stream.consume(line) else { continue }
                    switch event {
                    case .result(let value):
                        let accepted: Bool = await withCheckedContinuation { continuation in
                            self.queue.async {
                                guard self.active, self.work.active[item.lane]?.id == item.id else { continuation.resume(returning: false); return }
                                continuation.resume(returning: self.handle(value, item: item))
                            }
                        }
                        guard accepted else { throw VerificationStream.Failure(status: 502, message: "검증 결과 형식 오류") }
                    case .done: break
                    }
                    if stream.finished { break }
                }
                guard stream.finished else { throw VerificationStream.Failure(status: 502, message: "검증 응답 연결이 중간에 끊겼습니다.") }
                self.queue.async { self.complete(item, success: true, status: status, error: nil) }
            } catch {
                let code = (error as? VerificationStream.Failure)?.status ?? status
                self.queue.async { self.complete(item, success: false, status: code, error: error) }
            }
        }
        tasks[item.lane] = task
    }
    private func complete(_ item: VerificationWorkQueue.Work, success: Bool, status: Int, error: Error?) {
        guard active, work.active[item.lane]?.id == item.id else { return }
        tasks[item.lane] = nil
        if !success {
            record(item.lane == .screen ? .screenFailed : .audioRequestFailed)
            let reason = status == 401 || status == 403 ? "검증 서버 연결이 만료되었습니다. 앱에서 탐지 준비를 다시 눌러주세요." : (error as? URLError)?.code == .timedOut || status == 504 ? "서버 응답 시간이 초과됐습니다. 아직 완료하지 못한 주장이 있습니다." : "검증 응답이 완료되지 않았습니다. HTTP \(status). 이미 받은 알림은 해당 주장에 대한 결과입니다."
            notice(key: "server-error", title: "검증 요청을 완료하지 못했습니다", message: String(item.preview.prefix(60)) + "\n" + reason, interval: 20)
        }
        if let next = work.finish(item, success: success, now: now), active { start(next) }
    }
    private func handle(_ value: [String:Any]?, item: VerificationWorkQueue.Work) -> Bool {
        guard let value = value else { return false }
        if value["status"] as? String == "skipped" {
            record(item.lane == .screen ? .screenSkipped : .audioSkipped)
            notice(key: "skipped-" + item.lane.rawValue, title: "검증 대상 없음 · " + (item.lane == .screen ? "자막" : "음성"), message: value["message"] as? String ?? "검증할 주장이 선별되지 않았습니다.", interval: 45)
            return true
        }
        guard value["status"] as? String == "analyzed", let verdict = value["verdict"] as? String,
              ["SUPPORTS","REFUTES","NOT_ENOUGH_INFO"].contains(verdict) else { return false }
        record(item.lane == .screen ? .screenDone : .audioDone)
        let claims = value["claims"] as? [[String:Any]] ?? []
        let claim = (claims.first(where: { $0["verdict"] as? String == verdict })?["claim"] as? String) ?? claims.first?["claim"] as? String ?? item.preview
        let title = verdict == "REFUTES" ? "원문 근거와 충돌합니다" : verdict == "SUPPORTS" ? "원문 근거가 뒷받침합니다" : "판별 불가 · 근거 부족"
        notice(key: "verdict-" + verdict + "-" + claim, title: title, message: "“" + String(claim.prefix(80)) + "”\n" + String((value["message"] as? String ?? "원문 근거를 확인하세요.").prefix(200)), interval: 90)
        return true
    }
    private func notice(key: String, title: String, message: String, interval: TimeInterval) {
        guard now - (noticeTimes[key] ?? -.infinity) >= interval else { return };noticeTimes[key] = now
        if noticeTimes.count > 256, let oldest = noticeTimes.min(by: { $0.value < $1.value })?.key { noticeTimes[oldest] = nil }
        notify(title, message)
    }
    func notify(_ title: String, _ message: String) {
        let content = UNMutableNotificationContent();content.title = title;content.body = message
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { [weak self] error in
            guard let self = self else { return }
            self.queue.async { self.record(error == nil ? .notificationSubmitted : .notificationFailed) }
        }
    }
}
