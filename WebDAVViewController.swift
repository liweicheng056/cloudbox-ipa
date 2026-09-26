import UIKit
import UniformTypeIdentifiers

// WebDAV 网盘：直连坚果云/TeraCloud 等支持 WebDAV 的网盘
final class WebDAVViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate,
    UISearchBarDelegate, UIDocumentPickerDelegate {

    private var davURL: String {
        get { UserDefaults.standard.string(forKey: "webdavURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "webdavURL") }
    }
    private var davUser: String {
        get { UserDefaults.standard.string(forKey: "webdavUser") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "webdavUser") }
    }
    private var davPass: String {
        get { UserDefaults.standard.string(forKey: "webdavPass") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "webdavPass") }
    }

    private struct RemoteFile {
        let name: String
        let href: String
        let size: Int64
    }
    private var allFiles: [RemoteFile] = []
    private var displayFiles: [RemoteFile] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let infoBar = UIView()
    private let serverLabel = UILabel()
    private let countLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 3600
        return URLSession(configuration: c)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        if davURL.isEmpty {
            statusLabel.text = "先点左上角「设置」填 WebDAV 地址和账号"
        } else {
            refresh()
        }
    }

    // MARK: - UI
    private func setupUI() {
        title = "WebDAV 网盘"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(uploadTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "设置", style: .plain, target: self, action: #selector(settingsTapped))

        infoBar.translatesAutoresizingMaskIntoConstraints = false
        infoBar.backgroundColor = .secondarySystemBackground
        view.addSubview(infoBar)

        serverLabel.translatesAutoresizingMaskIntoConstraints = false
        serverLabel.font = .systemFont(ofSize: 13)
        serverLabel.text = davURL.isEmpty ? "未配置" : davURL
        serverLabel.lineBreakMode = .byTruncatingMiddle
        infoBar.addSubview(serverLabel)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right
        infoBar.addSubview(countLabel)

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "搜索网盘文件"
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
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            infoBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 34),

            serverLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 14),
            serverLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            serverLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -10),

            countLabel.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -14),
            countLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),

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

    // MARK: - 请求
    private func makeRequest(_ url: URL, method: String) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        if !davUser.isEmpty {
            let auth = Data((davUser + ":" + davPass).utf8).base64EncodedString()
            r.setValue("Basic " + auth, forHTTPHeaderField: "Authorization")
        }
        return r
    }

    private func setBusy(_ busy: Bool, _ text: String = "") {
        DispatchQueue.main.async {
            if busy { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
            self.statusLabel.text = text
        }
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

    // MARK: - 列表（PROPFIND）
    @objc private func refresh() {
        guard !davURL.isEmpty, let url = URL(string: davURL) else {
            statusLabel.text = "先点左上角「设置」填 WebDAV 地址和账号"
            return
        }
        var r = makeRequest(url, method: "PROPFIND")
        r.setValue("1", forHTTPHeaderField: "Depth")
        r.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
          <D:prop><D:displayname/><D:getcontentlength/><D:resourcetype/></D:prop>
        </D:propfind>
        """
        r.httpBody = body.data(using: .utf8)
        setBusy(true, "读取网盘列表…")
        session.dataTask(with: r) { [weak self] data, resp, err in
            guard let self = self else { return }
            guard let data = data, err == nil else {
                self.setBusy(false, "连接失败：\(err?.localizedDescription ?? "")")
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 207 || code == 200 else {
                self.setBusy(false, "服务器返回 HTTP \(code)（检查地址/账号/应用密码）")
                return
            }
            let parser = MultiStatusParser()
            parser.parse(data: data)
            let basePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.allFiles = parser.items.compactMap { item in
                if item.isCollection { return nil }
                let decoded = item.href.removingPercentEncoding ?? item.href
                let itemPath = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if itemPath == basePath { return nil }  // 自己
                var name = item.displayName
                if name.isEmpty { name = String(itemPath.split(separator: "/").last ?? "?") }
                return RemoteFile(name: name, href: item.href, size: item.size)
            }
            DispatchQueue.main.async {
                self.countLabel.text = "\(self.allFiles.count) 个文件"
                self.applyFilter()
            }
            self.setBusy(false)
        }.resume()
    }

    // MARK: - 上传
    @objc private func uploadTapped() {
        guard !davURL.isEmpty else {
            statusLabel.text = "先点左上角「设置」"
            return
        }
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
        let base = davURL.hasSuffix("/") ? davURL : davURL + "/"
        guard let url = URL(string: base + enc) else {
            setBusy(false, "地址拼接失败")
            return
        }
        var r = makeRequest(url, method: "PUT")
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
            if (200..<300).contains(code) {
                self.setBusy(true, "上传完成")
                self.uploadNext(rest)
            } else {
                self.setBusy(false, "上传被拒（HTTP \(code)）")
            }
        }.resume()
    }

    // MARK: - 下载
    private func download(_ f: RemoteFile) {
        guard let url = URL(string: f.href, relativeTo: URL(string: davURL))?.absoluteURL
                ?? URL(string: f.href) else { return }
        let r = makeRequest(url, method: "GET")
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

    // MARK: - 设置
    @objc private func settingsTapped() {
        let alert = UIAlertController(title: "WebDAV 设置",
                                      message: "坚果云示例：\n地址 https://dav.jianguoyun.com/dav/\n账号=邮箱，密码=应用密码（网页端 安全设置 里生成）",
                                      preferredStyle: .alert)
        alert.addTextField { tf in tf.placeholder = "地址（https://.../dav/）"; tf.text = self.davURL; tf.keyboardType = .URL }
        alert.addTextField { tf in tf.placeholder = "账号"; tf.text = self.davUser }
        alert.addTextField { tf in tf.placeholder = "密码/应用密码"; tf.text = self.davPass; tf.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let tfs = alert.textFields ?? []
            self.davURL = (tfs[safe: 0]?.text ?? "").trimmingCharacters(in: .whitespaces)
            self.davUser = (tfs[safe: 1]?.text ?? "").trimmingCharacters(in: .whitespaces)
            self.davPass = tfs[safe: 2]?.text ?? ""
            self.serverLabel.text = self.davURL
            self.refresh()
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
        guard let url = URL(string: f.href, relativeTo: URL(string: davURL))?.absoluteURL
                ?? URL(string: f.href) else { return }
        let r = makeRequest(url, method: "DELETE")
        setBusy(true, "删除 \(f.name)…")
        session.dataTask(with: r) { [weak self] _, _, _ in
            self?.refresh()
        }.resume()
    }
}

// multistatus XML 解析（兼容任意命名空间前缀）
final class MultiStatusParser: NSObject, XMLParserDelegate {
    struct Item {
        var href = ""
        var displayName = ""
        var size: Int64 = 0
        var isCollection = false
    }
    private(set) var items: [Item] = []
    private var current: Item?
    private var text = ""

    func parse(data: Data) {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    private func local(_ name: String) -> String {
        name.components(separatedBy: ":").last ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let e = local(elementName)
        if e == "response" { current = Item() }
        if e == "collection" { current?.isCollection = true }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let e = local(elementName)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch e {
        case "href":
            if current?.href.isEmpty ?? false { current?.href = t }
        case "displayname":
            current?.displayName = t
        case "getcontentlength":
            current?.size = Int64(t) ?? 0
        case "response":
            if let c = current { items.append(c) }
            current = nil
        default:
            break
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
