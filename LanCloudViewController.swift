import UIKit
import UniformTypeIdentifiers

// 电脑云盘：通过局域网把文件传到电脑硬盘（容量 = 电脑硬盘大小）
final class LanCloudViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate, UIDocumentPickerDelegate {

    private let token = "cb-7f3a9x-2046"
    private let defaultServer = "192.168.10.9:8899"

    private var server: String {
        get { UserDefaults.standard.string(forKey: "lanServer") ?? defaultServer }
        set { UserDefaults.standard.set(newValue, forKey: "lanServer") }
    }
    private var baseURL: String { "http://" + server }

    private struct RemoteFile {
        let name: String
        let size: Int64
        let mtime: Double
    }
    private var allFiles: [RemoteFile] = []
    private var displayFiles: [RemoteFile] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let infoBar = UIView()
    private let serverLabel = UILabel()
    private let capacityLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 600
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refresh()
    }

    // MARK: - UI
    private func setupUI() {
        title = "电脑云盘"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(uploadTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "服务器", style: .plain, target: self, action: #selector(serverTapped))

        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.backgroundColor = .secondarySystemBackground
        view.addSubview(infoBar)

        serverLabel.translatesAutoresizingMaskIntoConstraints = false
        serverLabel.font = .systemFont(ofSize: 13)
        serverLabel.text = server
        infoBar.addSubview(serverLabel)

        capacityLabel.translatesAutoresizingMaskIntoConstraints = false
        capacityLabel.font = .systemFont(ofSize: 12)
        capacityLabel.textColor = .secondaryLabel
        capacityLabel.textAlignment = .right
        capacityLabel.text = "连接中…"
        infoBar.addSubview(capacityLabel)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "搜索服务器上的文件"
        searchBar.searchBarStyle = .minimal
        view.addSubview(searchBar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            infoBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 34),

            serverLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 14),
            serverLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),

            capacityLabel.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -14),
            capacityLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            capacityLabel.leadingAnchor.constraint(greaterThanOrEqualTo: serverLabel.trailingAnchor, constant: 12),

            searchBar.topAnchor.constraint(equalTo: infoBar.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
        ])
    }

    // MARK: - 网络
    private func request(_ path: String, method: String) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(token, forHTTPHeaderField: "X-Token")
        return r
    }

    private func setBusy(_ busy: Bool, _ text: String = "") {
        DispatchQueue.main.async {
            if busy { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
            self.statusLabel.text = text
        }
    }

    @objc private func refresh() {
        serverLabel.text = server
        guard let r = request("/api/status", method: "GET"),
              let r2 = request("/api/list", method: "GET") else { return }
        setBusy(true, "连接服务器…")
        session.dataTask(with: r) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let data = data,
               let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let free = (d["free"] as? NSNumber)?.int64Value ?? 0
                let total = (d["total"] as? NSNumber)?.int64Value ?? 0
                let used = (d["used"] as? NSNumber)?.int64Value ?? 0
                DispatchQueue.main.async {
                    self.capacityLabel.text = "云盘 \(self.fmt(used)) · 剩余 \(self.fmt(free)) / 总 \(self.fmt(total))"
                }
            }
            self.session.dataTask(with: r2) { data2, _, err2 in
                defer { self.setBusy(false) }
                guard let data2 = data2,
                      let arr = try? JSONSerialization.jsonObject(with: data2) as? [[String: Any]] else {
                    self.setBusy(false, "连不上服务器：\(err2?.localizedDescription ?? "检查电脑是否开机、是否同一 WiFi")")
                    DispatchQueue.main.async { self.capacityLabel.text = "离线" }
                    return
                }
                self.allFiles = arr.map {
                    RemoteFile(name: $0["name"] as? String ?? "?",
                               size: ( $0["size"] as? NSNumber)?.int64Value ?? 0,
                               mtime: ($0["mtime"] as? NSNumber)?.doubleValue ?? 0)
                }
                DispatchQueue.main.async { self.applyFilter() }
            }.resume()
        }.resume()
    }

    private func fmt(_ b: Int64) -> String {
        let gb = Double(b) / 1024 / 1024 / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1024 / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(b) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(b) B"
    }

    // MARK: - 上传
    @objc private func uploadTapped() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        uploadNext(urls)
    }

    private func uploadNext(_ urls: [URL]) {
        guard let src = urls.first else {
            setBusy(false)
            refresh()
            return
        }
        let rest = Array(urls.dropFirst())
        let accessing = src.startAccessingSecurityScopedResource()
        defer { if accessing { src.stopAccessingSecurityScopedResource() } }
        // 先拷到临时位置（uploadTask 需要可持久访问的文件）
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(src.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: tmp.path) {
                try FileManager.default.removeItem(at: tmp)
            }
            try FileManager.default.copyItem(at: src, to: tmp)
        } catch {
            setBusy(false, "读取文件失败：\(error.localizedDescription)")
            return
        }
        let enc = src.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? src.lastPathComponent
        guard var r = request("/upload/" + enc, method: "PUT") else { return }
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        setBusy(true, "上传 \(src.lastPathComponent)…")
        session.uploadTask(with: r, fromFile: tmp) { [weak self] _, resp, err in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: tmp)
            if let err = err {
                self.setBusy(false, "上传失败：\(err.localizedDescription)")
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                self.setBusy(true, "上传完成")
                self.uploadNext(rest)
            } else {
                self.setBusy(false, "上传被拒（HTTP \(code)）")
            }
        }.resume()
    }

    // MARK: - 下载
    private func download(_ f: RemoteFile) {
        let enc = f.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.name
        guard let r = request("/download/" + enc, method: "GET") else { return }
        setBusy(true, "下载 \(f.name)…")
        session.downloadTask(with: r) { [weak self] loc, _, err in
            guard let self = self else { return }
            guard let loc = loc else {
                self.setBusy(false, "下载失败：\(err?.localizedDescription ?? "")")
                return
            }
            let dst = self.documentsDir.appendingPathComponent(f.name)
            do {
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.moveItem(at: loc, to: dst)
            } catch {
                self.setBusy(false, "保存失败：\(error.localizedDescription)")
                return
            }
            self.setBusy(false, "已下载到「手机云盘」")
            DispatchQueue.main.async {
                let vc = UIActivityViewController(activityItems: [dst], applicationActivities: nil)
                if let pop = vc.popoverPresentationController {
                    pop.sourceView = self.view
                    pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                }
                self.present(vc, animated: true)
            }
        }.resume()
    }

    // MARK: - 服务器设置
    @objc private func serverTapped() {
        let alert = UIAlertController(title: "服务器地址", message: "格式 IP:端口（电脑和 phone 需同一 WiFi）", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.server
            tf.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let t = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces), !t.isEmpty {
                self.server = t
                self.refresh()
            }
        })
        present(alert, animated: true)
    }

    // MARK: - 搜索
    private func applyFilter() {
        let q = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        displayFiles = q.isEmpty ? allFiles : allFiles.filter { $0.name.lowercased().contains(q) }
        tableView.reloadData()
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { applyFilter() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    // MARK: - table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { displayFiles.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let f = displayFiles[indexPath.row]
        c.textLabel?.text = f.name
        c.textLabel?.font = .systemFont(ofSize: 15)
        c.textLabel?.lineBreakMode = .byTruncatingMiddle
        let ext = (f.name as NSString).pathExtension.uppercased()
        c.detailTextLabel?.text = (ext.isEmpty ? "文件" : ext) + " · " + fmt(f.size)
        return c
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        download(displayFiles[indexPath.row])
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let f = displayFiles[indexPath.row]
        let enc = f.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? f.name
        guard let r = request("/delete/" + enc, method: "DELETE") else { return }
        setBusy(true, "删除 \(f.name)…")
        session.dataTask(with: r) { [weak self] _, _, _ in
            self?.refresh()
        }.resume()
    }
}
