import UIKit
import UniformTypeIdentifiers

// 副标题样式的列表 cell（默认 .default 样式不显示 detailTextLabel）
final class SubtitleCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// 云盘主界面：文件列表 + 分类 + 搜索 + 容量 + 北京时间 + 音乐入口
final class CloudViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate, UIDocumentPickerDelegate {

    // 存储目录：沙盒 Documents（UIFileSharingEnabled 让电脑能直接拖入）
    private var storageDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var allFiles: [URL] = []      // 当前目录下所有文件
    private var displayFiles: [URL] = []  // 经分类/搜索过滤后显示的

    // 分类（顺序即显示顺序）
    private struct Category {
        let key: String
        let name: String
        let exts: Set<String>
    }
    private let categories: [Category] = [
        Category(key: "all",   name: "全部",   exts: []),
        Category(key: "audio", name: "音乐",   exts: ["mp3","flac","m4a","wav","aac","aiff","aif","ogg","wma","mid","midi"]),
        Category(key: "video", name: "视频",   exts: ["mp4","mov","m4v","avi","mkv","wmv","flv","3gp","webm"]),
        Category(key: "image", name: "图片",   exts: ["jpg","jpeg","png","gif","bmp","webp","heic","svg","tiff","ico"]),
        Category(key: "ipa",   name: "IPA",    exts: ["ipa"]),
        Category(key: "apk",   name: "APK",    exts: ["apk"]),
        Category(key: "archive", name: "压缩包", exts: ["zip","rar","7z","tar","gz","bz2","xz","iso"]),
        Category(key: "doc",   name: "文档",   exts: ["txt","md","pdf","doc","docx","xls","xlsx","ppt","pptx","csv","pages","numbers","key"]),
        Category(key: "other", name: "其他",   exts: []),
    ]
    private var currentCategoryKey = "all"

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let infoBar = UIView()          // 顶部信息条：北京时间 + 容量
    private let timeLabel = UILabel()
    private let storageLabel = UILabel()
    private let categoryScroll = UIScrollView()
    private var categoryButtons: [UIButton] = []
    private var clockTimer: Timer?

    private var audioExts = Set(["mp3","flac","m4a","wav","aac","aiff","aif","ogg","wma","mid","midi"])

    // MARK: - lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        reloadFiles()
        startClock()
    }

    deinit {
        clockTimer?.invalidate()
    }

    // MARK: - UI
    private func setupUI() {
        title = "云盘"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "音乐", style: .plain, target: self, action: #selector(openMusic)),
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(importTapped)),
        ]

        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.backgroundColor = .secondarySystemBackground
        view.addSubview(infoBar)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeLabel.text = "--:--:--"
        infoBar.addSubview(timeLabel)

        storageLabel.translatesAutoresizingMaskIntoConstraints = false
        storageLabel.font = .systemFont(ofSize: 12)
        storageLabel.textColor = .secondaryLabel
        storageLabel.textAlignment = .right
        storageLabel.text = "容量 --"
        infoBar.addSubview(storageLabel)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "搜索文件名"
        searchBar.searchBarStyle = .minimal
        view.addSubview(searchBar)

        categoryScroll.translatesAutoresizingMaskIntoConstraints = false
        categoryScroll.showsHorizontalScrollIndicator = false
        view.addSubview(categoryScroll)

        var buttons: [UIButton] = []
        for (i, c) in categories.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(c.name, for: .normal)
            b.tag = i
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            b.layer.cornerRadius = 15
            b.clipsToBounds = true
            b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            buttons.append(b)
            categoryScroll.addSubview(b)
        }
        categoryButtons = buttons
        styleCategoryButtons()

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            infoBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 34),

            timeLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 14),
            timeLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),

            storageLabel.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -14),
            storageLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            storageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 12),

            searchBar.topAnchor.constraint(equalTo: infoBar.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            categoryScroll.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            categoryScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryScroll.heightAnchor.constraint(equalToConstant: 40),

            tableView.topAnchor.constraint(equalTo: categoryScroll.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        layoutCategoryButtons()
    }

    private func layoutCategoryButtons() {
        var x: CGFloat = 10
        for b in categoryButtons {
            b.sizeToFit()
            let w = b.frame.width
            b.frame = CGRect(x: x, y: 4, width: w, height: 32)
            x += w + 10
        }
        categoryScroll.contentSize = CGSize(width: x + 10, height: 40)
    }

    private func styleCategoryButtons() {
        for b in categoryButtons {
            let selected = categories[b.tag].key == currentCategoryKey
            if selected {
                b.backgroundColor = .systemBlue
                b.setTitleColor(.white, for: .normal)
            } else {
                b.backgroundColor = .tertiarySystemFill
                b.setTitleColor(.label, for: .normal)
            }
        }
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        currentCategoryKey = categories[sender.tag].key
        styleCategoryButtons()
        applyFilter()
    }

    // MARK: - clock (北京时间)
    private func startClock() {
        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
    }

    private func updateClock() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        timeLabel.text = "北京时间 " + fmt.string(from: Date())
    }

    // MARK: - files
    private func reloadFiles() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDir.path) {
            try? fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }
        let files = (try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        allFiles = files
            .filter { $0.pathExtension.lowercased() != "" || !$0.hasDirectoryPath }
            .sorted { ($0.lastPathComponent as String).localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        updateStorage()
        applyFilter()
    }

    private func updateStorage() {
        let fm = FileManager.default
        var used: Int64 = 0
        for f in allFiles {
            if let sz = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize { used += Int64(sz) }
        }
        var total: Int64 = 0
        var avail: Int64 = 0
        if let vals = try? storageDir.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            total = Int64(vals.volumeTotalCapacity ?? 0)
            avail = Int64(vals.volumeAvailableCapacity ?? 0)
        }
        storageLabel.text = "云盘 \(formatBytes(used)) · 剩余 \(formatBytes(avail)) / 总 \(formatBytes(total))"
    }

    private func formatBytes(_ b: Int64) -> String {
        let gb = Double(b) / 1024 / 1024 / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1024 / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(b) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(b) B"
    }

    // MARK: - filter (category + search)
    private func applyFilter() {
        let query = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        displayFiles = allFiles.filter { url in
            let ext = url.pathExtension.lowercased()
            var inCat = true
            if currentCategoryKey != "all" {
                if currentCategoryKey == "other" {
                    // 其他：不属于任何显式分类
                    inCat = !categories.contains { $0.key != "all" && $0.key != "other" && $0.exts.contains(ext) }
                } else if let c = categories.first(where: { $0.key == currentCategoryKey }) {
                    inCat = c.exts.contains(ext)
                }
            }
            if !inCat { return false }
            if query.isEmpty { return true }
            return url.lastPathComponent.lowercased().contains(query.lowercased())
        }
        tableView.reloadData()
    }

    // MARK: - search
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter()
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - import (文件 App 导入)
    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item, UTType.data, UTType.content])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let fm = FileManager.default
        for src in urls {
            let dst = storageDir.appendingPathComponent(src.lastPathComponent)
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                let accessing = src.startAccessingSecurityScopedResource()
                try fm.copyItem(at: src, to: dst)
                if accessing { src.stopAccessingSecurityScopedResource() }
            } catch {
                print("copy error: \(error)")
            }
        }
        reloadFiles()
    }

    // MARK: - music entry
    @objc private func openMusic() {
        let player = MusicViewController()
        navigationController?.pushViewController(player, animated: true)
    }

    // MARK: - table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayFiles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let url = displayFiles[indexPath.row]
        c.textLabel?.text = url.lastPathComponent
        c.textLabel?.font = .systemFont(ofSize: 15)
        c.textLabel?.lineBreakMode = .byTruncatingMiddle
        let ext = url.pathExtension.uppercased()
        var sizeText = ""
        if let sz = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            sizeText = " · " + formatBytes(Int64(sz))
        }
        c.detailTextLabel?.text = (ext.isEmpty ? "文件" : ext) + sizeText
        return c
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = displayFiles[indexPath.row]
        // 音频点击直接进播放器播放
        if audioExts.contains(url.pathExtension.lowercased()) {
            let player = MusicViewController(initialURL: url)
            navigationController?.pushViewController(player, animated: true)
            return
        }
        // 其他文件弹分享/导出
        share(url)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let url = displayFiles[indexPath.row]
            try? FileManager.default.removeItem(at: url)
            reloadFiles()
        }
    }

    private func share(_ url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(vc, animated: true)
    }
}
