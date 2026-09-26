import UIKit
import AVFoundation
import MediaPlayer
import CoreMedia

// 音乐播放器：播放「内置歌曲」+「云盘 Documents 里的音乐文件」
final class MusicViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {

    private let audioExts = ["mp3", "m4a", "wav", "aac", "flac", "caf", "aiff", "aif", "mp4", "mov", "ogg"]
    private var tracks: [URL] = []
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var currentIndex = -1

    private var lyricLines: [(time: Double, text: String)]?
    private var lyricLineRanges: [NSRange] = []
    private var lyricsPlain: String?
    private var currentLyricIndex = -1

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let nowPlayingBar = UIView()
    private let titleLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let prevButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()

    private let lyricsView = UIView()
    private let lyricsTextView = UITextView()
    private let lyricsHint = UILabel()
    private let pasteButton = UIButton(type: .system)

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // 可选：从云盘点某首音乐直接跳进来
    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
        super.init(nibName: nil, bundle: nil)
    }
    private let initialURL: URL?
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupRemoteCommands()
        scanTracks()
        if let u = initialURL, let idx = tracks.firstIndex(of: u) {
            play(index: idx)
        }
    }

    // MARK: - UI
    private func setupUI() {
        title = "音乐"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "导入", style: .plain, target: self, action: #selector(importTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "词", style: .plain, target: self, action: #selector(toggleLyrics))

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)

        nowPlayingBar.translatesAutoresizingMaskIntoConstraints = false
        nowPlayingBar.backgroundColor = .secondarySystemBackground
        view.addSubview(nowPlayingBar)

        prevButton.setTitle("⏮", for: .normal)
        playPauseButton.setTitle("▶️", for: .normal)
        nextButton.setTitle("⏭", for: .normal)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        [prevButton, playPauseButton, nextButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.titleLabel?.font = .systemFont(ofSize: 22)
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = "还没有歌曲"

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabel
        timeLabel.text = "00:00"
        timeLabel.textAlignment = .right

        let stack = UIStackView(arrangedSubviews: [prevButton, playPauseButton, nextButton])
        stack.axis = .horizontal
        stack.spacing = 26
        stack.translatesAutoresizingMaskIntoConstraints = false

        nowPlayingBar.addSubview(titleLabel)
        nowPlayingBar.addSubview(stack)
        nowPlayingBar.addSubview(slider)
        nowPlayingBar.addSubview(timeLabel)

        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        lyricsView.backgroundColor = .systemBackground
        lyricsView.isHidden = true
        view.addSubview(lyricsView)

        lyricsTextView.translatesAutoresizingMaskIntoConstraints = false
        lyricsTextView.isEditable = false
        lyricsTextView.isScrollEnabled = true
        lyricsTextView.backgroundColor = .clear
        lyricsTextView.textAlignment = .center
        lyricsTextView.font = .systemFont(ofSize: 17)
        lyricsView.addSubview(lyricsTextView)

        lyricsHint.translatesAutoresizingMaskIntoConstraints = false
        lyricsHint.text = "暂无歌词 · 可把同名 .lrc 放进同目录，或点「粘贴歌词」"
        lyricsHint.font = .systemFont(ofSize: 12)
        lyricsHint.textColor = .secondaryLabel
        lyricsHint.textAlignment = .center
        lyricsHint.numberOfLines = 0
        lyricsView.addSubview(lyricsHint)

        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.setTitle("粘贴歌词", for: .normal)
        pasteButton.addTarget(self, action: #selector(pasteLyrics), for: .touchUpInside)
        lyricsView.addSubview(pasteButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: nowPlayingBar.topAnchor),

            lyricsView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            lyricsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: nowPlayingBar.topAnchor),

            lyricsTextView.topAnchor.constraint(equalTo: lyricsView.topAnchor, constant: 16),
            lyricsTextView.leadingAnchor.constraint(equalTo: lyricsView.leadingAnchor, constant: 16),
            lyricsTextView.trailingAnchor.constraint(equalTo: lyricsView.trailingAnchor, constant: -16),
            lyricsTextView.bottomAnchor.constraint(equalTo: pasteButton.topAnchor, constant: -12),

            pasteButton.centerXAnchor.constraint(equalTo: lyricsView.centerXAnchor),
            pasteButton.bottomAnchor.constraint(equalTo: lyricsView.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            lyricsHint.centerXAnchor.constraint(equalTo: lyricsView.centerXAnchor),
            lyricsHint.centerYAnchor.constraint(equalTo: lyricsView.centerYAnchor),
            lyricsHint.leadingAnchor.constraint(equalTo: lyricsView.leadingAnchor, constant: 24),
            lyricsHint.trailingAnchor.constraint(equalTo: lyricsView.trailingAnchor, constant: -24),

            nowPlayingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nowPlayingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nowPlayingBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            nowPlayingBar.heightAnchor.constraint(equalToConstant: 112),

            titleLabel.topAnchor.constraint(equalTo: nowPlayingBar.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: nowPlayingBar.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: nowPlayingBar.trailingAnchor, constant: -14),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            stack.centerXAnchor.constraint(equalTo: nowPlayingBar.centerXAnchor),

            slider.leadingAnchor.constraint(equalTo: nowPlayingBar.leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -10),
            slider.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),

            timeLabel.trailingAnchor.constraint(equalTo: nowPlayingBar.trailingAnchor, constant: -14),
            timeLabel.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 46),
        ])

        // 背景必须在所有 UI 颜色设定之后调用（否则会被覆盖）
        setupBackground()
    }

    // MARK: - 背景图（Bundle 内 bg.jpg + 28% 黑遮罩，白色文字）
    private func setupBackground() {
        guard let bgURL = Bundle.main.url(forResource: "bg", withExtension: "jpg"),
              let data = try? Data(contentsOf: bgURL),
              let img = UIImage(data: data) else { return }
        let bgView = UIImageView(image: img)
        bgView.contentMode = .scaleAspectFill
        bgView.frame = view.bounds
        bgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(bgView, at: 0)

        let dim = UIView(frame: view.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        view.insertSubview(dim, at: 1)

        // 各面板透明化 + 白色文字
        tableView.backgroundColor = .clear
        lyricsView.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        nowPlayingBar.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        titleLabel.textColor = .white
        titleLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        titleLabel.shadowOffset = CGSize(width: 0, height: 1)
        timeLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        lyricsTextView.textColor = .white
        lyricsHint.textColor = UIColor.white.withAlphaComponent(0.75)
        slider.tintColor = .white
    }

    // MARK: - scan (内置 songs + 云盘 Documents)
    private func scanTracks() {
        var result: [URL] = []
        if let songsDir = Bundle.main.resourceURL?.appendingPathComponent("songs"),
           let files = try? FileManager.default.contentsOfDirectory(at: songsDir, includingPropertiesForKeys: nil) {
            result += files.filter { audioExts.contains($0.pathExtension.lowercased()) }
        }
        if let files = try? FileManager.default.contentsOfDirectory(at: documentsDir, includingPropertiesForKeys: nil) {
            result += files.filter { audioExts.contains($0.pathExtension.lowercased()) }
        }
        tracks = result.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        tableView.reloadData()
        if tracks.isEmpty {
            titleLabel.text = "云盘里还没有音乐，点「导入」或去主界面添加"
        }
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    // MARK: - playback
    private func play(index: Int) {
        guard index >= 0, index < tracks.count else { return }
        currentIndex = index
        let url = tracks[index]
        let item = AVPlayerItem(url: url)
        if player == nil { player = AVPlayer() }
        player?.replaceCurrentItem(with: item)
        player?.play()
        playPauseButton.setTitle("⏸", for: .normal)
        titleLabel.text = url.deletingPathExtension().lastPathComponent
        loadLyrics(for: url)
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        removeTimeObserver()
        addTimeObserver()
        updateNowPlaying()
        refreshLyricsView()
    }

    @objc private func togglePlay() {
        guard let player = player else {
            if currentIndex >= 0 { play(index: currentIndex) }
            return
        }
        if player.timeControlStatus == .playing {
            player.pause(); playPauseButton.setTitle("▶️", for: .normal)
        } else {
            player.play(); playPauseButton.setTitle("⏸", for: .normal)
        }
    }

    @objc private func nextTapped() {
        guard !tracks.isEmpty else { return }
        let nxt = currentIndex + 1
        if nxt < tracks.count { play(index: nxt) } else { player?.pause(); playPauseButton.setTitle("▶️", for: .normal) }
    }

    @objc private func prevTapped() {
        guard !tracks.isEmpty else { return }
        let prev = currentIndex - 1
        if prev >= 0 {
            play(index: prev)
        } else {
            player?.seek(to: .zero); player?.play(); playPauseButton.setTitle("⏸", for: .normal)
        }
    }

    @objc private func sliderChanged() {
        guard let player = player, let dur = player.currentItem?.duration,
              dur.isValid, !dur.isIndefinite, dur.seconds > 0 else { return }
        let t = CMTime(seconds: Double(slider.value) * dur.seconds, preferredTimescale: dur.timescale)
        player.seek(to: t)
    }

    @objc private func itemDidEnd() { nextTapped() }

    // MARK: - time observer
    private func addTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.4, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in self?.updateProgress(time)
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken { player?.removeTimeObserver(token); timeObserverToken = nil }
    }

    private func updateProgress(_ time: CMTime) {
        guard let dur = player?.currentItem?.duration, dur.isValid, !dur.isIndefinite, dur.seconds > 0 else { return }
        let cur = time.seconds
        slider.value = Float(cur / dur.seconds)
        timeLabel.text = format(cur)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = cur
        info[MPMediaItemPropertyPlaybackDuration] = dur.seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateLyricHighlight(cur)
    }

    private func format(_ s: Double) -> String {
        let i = max(0, Int(s))
        return String(format: "%02d:%02d", i / 60, i % 60)
    }

    // MARK: - now playing / remote
    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = titleLabel.text ?? ""
        info[MPMediaItemPropertyArtist] = "云盘"
        if let dur = player?.currentItem?.duration, dur.isValid, !dur.isIndefinite {
            info[MPMediaItemPropertyPlaybackDuration] = dur.seconds
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { [weak self] _ in
            self?.player?.play(); self?.playPauseButton.setTitle("⏸", for: .normal); return .success
        }
        rc.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause(); self?.playPauseButton.setTitle("▶️", for: .normal); return .success
        }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlay(); return .success
        }
        rc.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTapped(); return .success
        }
        rc.previousTrackCommand.addTarget { [weak self] _ in
            self?.prevTapped(); return .success
        }
    }

    // MARK: - lyrics
    @objc private func toggleLyrics() { lyricsView.isHidden.toggle() }

    private func loadLyrics(for url: URL) {
        lyricLines = nil; lyricLineRanges = []; lyricsPlain = nil; currentLyricIndex = -1
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let lrcURL = dir.appendingPathComponent(base + ".lrc")
        if let text = try? String(contentsOf: lrcURL, encoding: .utf8) {
            lyricLines = parseLRC(text)
            if lyricLines == nil || lyricLines!.isEmpty { lyricsPlain = text }
            return
        }
        if let emb = extractEmbeddedLyrics(url) {
            lyricLines = parseLRC(emb)
            if lyricLines == nil || lyricLines!.isEmpty { lyricsPlain = emb }
            return
        }
    }

    @objc private func pasteLyrics() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            lyricsHint.text = "剪贴板为空"; return
        }
        lyricLines = parseLRC(text)
        if lyricLines == nil || lyricLines!.isEmpty { lyricsPlain = text }
        currentLyricIndex = -1
        refreshLyricsView()
    }

    private func parseLRC(_ text: String) -> [(Double, String)]? {
        var out: [(Double, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            var idx = trimmed.startIndex
            var times: [Double] = []
            while trimmed[idx] == "[" {
                guard let close = trimmed[idx..<trimmed.endIndex].firstIndex(of: "]") else { break }
                let inner = String(trimmed[trimmed.index(after: idx)..<close])
                if let t = parseLRCTime(inner) { times.append(t) }
                idx = trimmed.index(after: close)
            }
            let lyric = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
            if times.isEmpty { continue }
            for t in times { out.append((t, lyric)) }
        }
        return out.isEmpty ? nil : out.sorted { $0.0 < $1.0 }
    }

    private func parseLRCTime(_ s: String) -> Double? {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 2, let m = Double(parts[0]) else { return nil }
        let secParts = parts[1].components(separatedBy: ".")
        guard let sec = Double(secParts[0]) else { return nil }
        let frac = (secParts.count > 1) ? (Double("0." + secParts[1]) ?? 0) : 0
        return m * 60 + sec + frac
    }

    private func extractEmbeddedLyrics(_ url: URL) -> String? {
        let asset = AVURLAsset(url: url)
        for item in asset.metadata {
            if item.commonKey?.rawValue == "lyrics" {
                return item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let b = [UInt8](data)
        guard b.count > 4, b[0] == 0x66, b[1] == 0x4C, b[2] == 0x61, b[3] == 0x43 else { return nil } // fLaC
        var pos = 4
        while pos < b.count {
            let header = b[pos]; pos += 1
            let isLast = (header & 0x80) != 0
            let blockType = header & 0x7F
            let len = (Int(b[pos]) << 16) | (Int(b[pos + 1]) << 8) | Int(b[pos + 2]); pos += 3
            if blockType == 4 {
                let block = b[pos..<(pos + len)]
                var p = 0
                guard block.count >= 4 else { break }
                let vendor = Int(block[p]) | (Int(block[p + 1]) << 8) | (Int(block[p + 2]) << 16) | (Int(block[p + 3]) << 24)
                p += 4 + vendor
                guard block.count >= p + 4 else { break }
                let count = Int(block[p]) | (Int(block[p + 1]) << 8) | (Int(block[p + 2]) << 16) | (Int(block[p + 3]) << 24)
                p += 4
                for _ in 0..<count {
                    guard block.count >= p + 4 else { break }
                    let clen = Int(block[p]) | (Int(block[p + 1]) << 8) | (Int(block[p + 2]) << 16) | (Int(block[p + 3]) << 24)
                    p += 4
                    guard block.count >= p + clen else { break }
                    let comment = String(bytes: block[p..<(p + clen)], encoding: .utf8) ?? ""
                    p += clen
                    if let rng = comment.range(of: "=") {
                        let tag = comment[..<rng.lowerBound].lowercased()
                        if tag == "lyrics" {
                            return String(comment[rng.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                break
            } else {
                pos += len
            }
            if isLast { break }
        }
        return nil
    }

    private func refreshLyricsView() {
        if let lines = lyricLines {
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 8
            let builder = NSMutableAttributedString(); lyricLineRanges = []
            for (_, txt) in lines {
                let start = builder.length
                builder.append(NSAttributedString(string: txt + "\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 17),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: para,
                ]))
                lyricLineRanges.append(NSRange(location: start, length: txt.count))
            }
            lyricsTextView.attributedText = builder
            lyricsHint.isHidden = true
            currentLyricIndex = -1
            updateLyricHighlight(player?.currentTime().seconds ?? 0)
        } else if let plain = lyricsPlain {
            lyricsTextView.text = plain
            lyricsTextView.textAlignment = .center
            lyricsHint.isHidden = true
        } else {
            lyricsTextView.text = ""
            lyricsHint.isHidden = false
        }
    }

    private func updateLyricHighlight(_ currentTime: Double) {
        guard let lines = lyricLines, !lines.isEmpty else { return }
        var idx = -1
        for i in 0..<lines.count {
            if lines[i].time <= currentTime + 0.25 { idx = i } else { break }
        }
        if idx == currentLyricIndex { return }
        currentLyricIndex = idx
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 8
        let builder = NSMutableAttributedString()
        for (i, (_, txt)) in lines.enumerated() {
            let color: UIColor = (i == idx) ? .label : .secondaryLabel
            let font = (i == idx) ? UIFont.boldSystemFont(ofSize: 18) : UIFont.systemFont(ofSize: 17)
            builder.append(NSAttributedString(string: txt + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: para,
            ]))
        }
        lyricsTextView.attributedText = builder
        if idx >= 0, idx < lyricLineRanges.count {
            lyricsTextView.scrollRangeToVisible(lyricLineRanges[idx])
        }
    }

    // MARK: - table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tracks.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        c.textLabel?.text = tracks[indexPath.row].deletingPathExtension().lastPathComponent
        c.textLabel?.font = .systemFont(ofSize: 15)
        c.textLabel?.lineBreakMode = .byTruncatingMiddle
        c.backgroundColor = .clear
        c.textLabel?.textColor = .white
        c.textLabel?.shadowColor = UIColor.black.withAlphaComponent(0.6)
        c.textLabel?.shadowOffset = CGSize(width: 0, height: 1)
        return c
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        play(index: indexPath.row)
    }
}

extension MusicViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let fm = FileManager.default
        for src in urls {
            let dst = documentsDir.appendingPathComponent(src.lastPathComponent)
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                let accessing = src.startAccessingSecurityScopedResource()
                try fm.copyItem(at: src, to: dst)
                if accessing { src.stopAccessingSecurityScopedResource() }
            } catch { print("copy error: \(error)") }
        }
        scanTracks()
    }
}
