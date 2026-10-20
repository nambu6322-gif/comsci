import ReplayKit
import Vision
import UserNotifications
import AVFoundation
final class SampleHandler: RPBroadcastSampleHandler {
    var connection: ServerConnection?
    let queue = DispatchQueue(label: "ReelProof.analysis")
    var selector: TextModel?; var modernStyle: TextModel?; var lastStyleAlert = 0.0; var lastFrame = 0.0; var lastText = ""; var analyzingFrame = false; var requesting = false; var active = false
    var writer: AVAssetWriter?; var audioInput: AVAssetWriterInput?; var audioURL: URL?; var audioStart = CMTime.zero
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        do {
            connection = try AppConfiguration.loadConnection()
            guard let value = connection, value.valid else { throw ConnectionKeychain.StorageError(status: -25300) }
        } catch {
            finishBroadcastWithError(NSError(domain: "ReelProof", code: 1, userInfo: [NSLocalizedDescriptionKey: "설정을 읽지 못했습니다. 앱에서 탐지 준비를 다시 누르세요. \(error.localizedDescription)\n\(AppConfiguration.sharingDiagnostics)"]))
            return
        }
        selector = try? TextModel(filename: "selector-model"); modernStyle = try? TextModel(filename: "modern-ai-text-model"); active = true
    }
    override func broadcastPaused() { active = false; discardAudio() }
    override func broadcastResumed() { active = true }
    override func broadcastFinished() { active = false; discardAudio() }
    func discardAudio() { writer?.cancelWriting(); if let url = audioURL { try? FileManager.default.removeItem(at: url) }; writer = nil; audioInput = nil; audioURL = nil }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard active else { return }
        if sampleBufferType == .audioApp { if !(connection?.token ?? "").isEmpty { processAudio(sampleBuffer) }; return }
        guard sampleBufferType == .video, !analyzingFrame, Date().timeIntervalSince1970 - lastFrame >= 2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date().timeIntervalSince1970; analyzingFrame = true
        queue.async { [weak self] in
            guard let self = self else { return }; defer { self.analyzingFrame = false }
            let request = VNRecognizeTextRequest(); request.recognitionLanguages = ["ko-KR", "en-US"]; request.recognitionLevel = .accurate; request.usesLanguageCorrection = false; request.minimumTextHeight = 0.018
            do { try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request]); let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                if text.count > 15, text != self.lastText { self.lastText = text; self.analyzeStyle(text); if let model = self.selector, model.score(text) >= model.threshold { self.send(path: "/v1/analyze", data: try JSONSerialization.data(withJSONObject: ["text": text, "source": "screen"]), type: "application/json") } }
            } catch { self.notify("자막 판별 불가", "화면 문자 인식 또는 보호된 화면 오류입니다.") }
        }
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
            current.finishWriting { [weak self] in guard let self = self, let url = url else { return }; defer { try? FileManager.default.removeItem(at: url) }; if self.active, current.status == .completed, let data = try? Data(contentsOf: url) { self.send(path: "/v1/audio", data: data, type: "audio/mp4") } }
        }
    }
    func send(path: String, data: Data, type: String) {
        guard active, !requesting, !(connection?.token ?? "").isEmpty, let base = connection?.endpoint, let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path), url.scheme == "https" else { return }
        requesting = true; var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = data; request.timeoutInterval = 140; request.setValue(type, forHTTPHeaderField: "Content-Type"); request.setValue("Bearer " + (connection?.token ?? ""), forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { [weak self] body, response, error in
            guard let self = self else { return }; defer { self.requesting = false }; guard self.active else { return }
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let body = body, let value = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { self.notify("판별 불가 · 서버 연결 확인", "오디오·주장 검증 서버에서 정상 응답을 받지 못했습니다."); return }
            if value["status"] as? String == "skipped" { return }
            let verdict = value["verdict"] as? String ?? "NOT_ENOUGH_INFO"
            self.notify(verdict == "REFUTES" ? "원문 근거와 충돌합니다" : verdict == "SUPPORTS" ? "원문 근거가 뒷받침합니다" : "판별 불가 · 근거 부족", value["message"] as? String ?? "확인할 근거가 부족합니다.")
        }.resume()
    }
    func notify(_ title: String, _ message: String) { let content = UNMutableNotificationContent(); content.title = title; content.body = message; UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
}
