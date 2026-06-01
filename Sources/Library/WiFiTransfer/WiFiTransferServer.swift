//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumGCDWebServer

/// A lightweight HTTP server that serves a file-upload web page.
/// Users on the same WiFi network can open the displayed URL in a browser
/// and drag-and-drop files to transfer them to the app's Documents directory.
final class WiFiTransferServer {
    private var server: ReadiumGCDWebServer?

    /// Called on the main thread when a file has been uploaded successfully.
    /// The parameter is the file URL in the Documents directory.
    var onFileUploaded: ((URL) -> Void)?

    // MARK: - Public

    /// Starts the server on a random available port.
    /// Returns the URL string to display to the user (e.g. "http://192.168.1.5:8080").
    @discardableResult
    func start() throws -> String {
        if let server, server.isRunning {
            return displayURL(port: server.port) ?? ""
        }

        let webServer = ReadiumGCDWebServer()

        // GET / → serve the upload HTML page
        webServer.addHandler(
            forMethod: "GET",
            path: "/",
            request: ReadiumGCDWebServerRequest.self,
            processBlock: { [weak self] _ in
                guard let self else { return nil }
                return ReadiumGCDWebServerDataResponse(html: self.uploadPageHTML())
            }
        )

        // POST /upload → receive multipart file uploads
        webServer.addHandler(
            forMethod: "POST",
            path: "/upload",
            request: ReadiumGCDWebServerMultiPartFormRequest.self,
            processBlock: { [weak self] request in
                self?.handleUpload(request: request)
            }
        )

        try webServer.start(options: [
            ReadiumGCDWebServerOption_Port: 0,
            ReadiumGCDWebServerOption_BonjourName: "PagePilot",
            ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false,
        ])

        self.server = webServer
        return displayURL(port: webServer.port) ?? ""
    }

    func stop() {
        server?.stop()
        server = nil
    }

    var isRunning: Bool {
        server?.isRunning ?? false
    }

    var serverURL: String? {
        guard let server, server.isRunning else { return nil }
        return displayURL(port: server.port)
    }

    // MARK: - Upload handling

    private func handleUpload(request: ReadiumGCDWebServerRequest?) -> ReadiumGCDWebServerResponse? {
        guard let multipart = request as? ReadiumGCDWebServerMultiPartFormRequest else {
            let response = ReadiumGCDWebServerDataResponse(
                data: Data("{\"error\":\"Invalid request\"}".utf8),
                contentType: "application/json"
            )
            response.statusCode = 400
            return response
        }

        var uploadedFiles: [String] = []
        var failedFiles: [String] = []

        for file in multipart.files {
            let originalName = file.fileName
            let tempPath = file.temporaryPath

            let sanitized = originalName.sanitizedPathComponent
            let destURL = Paths.documents.appendingUniquePathComponent(sanitized).url

            do {
                try FileManager.default.moveItem(
                    atPath: tempPath,
                    toPath: destURL.path
                )
                uploadedFiles.append(originalName)

                DispatchQueue.main.async { [weak self] in
                    self?.onFileUploaded?(destURL)
                }
            } catch {
                do {
                    try FileManager.default.copyItem(
                        atPath: tempPath,
                        toPath: destURL.path
                    )
                    uploadedFiles.append(originalName)

                    DispatchQueue.main.async { [weak self] in
                        self?.onFileUploaded?(destURL)
                    }
                } catch {
                    print("WiFiTransfer: failed to save \(originalName): \(error)")
                    failedFiles.append(originalName)
                }
            }
        }

        let successJSON = uploadedFiles.map { "\"\($0)\"" }.joined(separator: ",")
        let failedJSON = failedFiles.map { "\"\($0)\"" }.joined(separator: ",")
        let json = "{\"success\":true,\"uploaded\":[\(successJSON)],\"failed\":[\(failedJSON)]}"
        let response = ReadiumGCDWebServerDataResponse(
            data: Data(json.utf8),
            contentType: "application/json"
        )
        response.statusCode = 200
        return response
    }

    // MARK: - Helpers

    private func displayURL(port: UInt) -> String? {
        guard let ip = WiFiTransferServer.wifiIPAddress() else { return nil }
        return "http://\(ip):\(port)"
    }

    static func wifiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            guard addrFamily == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            address = String(cString: hostname)
        }
        return address
    }

    // MARK: - HTML

    private struct LocalizedStrings {
        let lang: String
        let title: String
        let subtitle: String
        let dropText: String
        let formats: String
        let uploading: String
        let done: String
        let failed: String
        let unknown: String
        let tip: String
    }

    private static let localizedStrings: [String: LocalizedStrings] = [
        "zh": LocalizedStrings(
            lang: "zh-CN",
            title: "WiFi 传书",
            subtitle: "将文件从电脑传输到 PagePilot",
            dropText: "拖拽文件到这里，或点击选择文件",
            formats: "支持 EPUB、PDF、CBZ、TXT 等格式",
            uploading: "上传中...",
            done: "✓ 完成",
            failed: "✗ 失败",
            unknown: "✗ 未知",
            tip: "💡 提示：请确保电脑和手机连接同一个 WiFi 网络。传输完成后文件会自动出现在书架中。"
        ),
        "en": LocalizedStrings(
            lang: "en",
            title: "WiFi Transfer",
            subtitle: "Transfer files from your computer to PagePilot",
            dropText: "Drag files here, or click to select",
            formats: "Supports EPUB, PDF, CBZ, TXT and more",
            uploading: "Uploading...",
            done: "✓ Done",
            failed: "✗ Failed",
            unknown: "✗ Unknown",
            tip: "💡 Tip: Make sure your computer and device are on the same WiFi network. Files will appear on your bookshelf after transfer."
        ),
    ]

    private func uploadPageHTML() -> String {
        let preferredLang = AppAppearancePreferences.language.rawValue.prefix(2).lowercased()
        let strings = Self.localizedStrings[String(preferredLang)] ?? Self.localizedStrings["en"]!

        return """
        <!DOCTYPE html>
        <html lang="\(strings.lang)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PagePilot - \(strings.title)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    background: #f5f5f7;
                    color: #1d1d1f;
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 20px;
                }
                .container {
                    background: white;
                    border-radius: 20px;
                    padding: 40px;
                    max-width: 560px;
                    width: 100%;
                    box-shadow: 0 4px 24px rgba(0,0,0,0.08);
                }
                h1 { font-size: 24px; font-weight: 700; margin-bottom: 8px; }
                .subtitle { color: #86868b; font-size: 15px; margin-bottom: 32px; }
                .drop-zone {
                    border: 2px dashed #d2d2d7;
                    border-radius: 16px;
                    padding: 48px 24px;
                    text-align: center;
                    cursor: pointer;
                    transition: all 0.2s;
                    margin-bottom: 20px;
                }
                .drop-zone:hover, .drop-zone.dragover {
                    border-color: #007aff;
                    background: #f0f7ff;
                }
                .drop-zone .icon { font-size: 48px; margin-bottom: 12px; }
                .drop-zone p { color: #86868b; font-size: 15px; }
                .drop-zone .formats { font-size: 13px; color: #aeaeb2; margin-top: 8px; }
                input[type="file"] { display: none; }
                .file-list { list-style: none; margin-top: 16px; }
                .file-list li {
                    padding: 12px 16px;
                    background: #f5f5f7;
                    border-radius: 10px;
                    margin-bottom: 8px;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    font-size: 14px;
                }
                .file-list li .name { flex: 1; word-break: break-all; }
                .file-list li .status { margin-left: 12px; font-size: 13px; white-space: nowrap; }
                .status.uploading { color: #007aff; }
                .status.done { color: #34c759; }
                .status.error { color: #ff3b30; }
                .tip {
                    margin-top: 24px;
                    padding: 16px;
                    background: #f0f7ff;
                    border-radius: 12px;
                    font-size: 13px;
                    color: #555;
                    line-height: 1.5;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📚 \(strings.title)</h1>
                <p class="subtitle">\(strings.subtitle)</p>
                <div class="drop-zone" id="dropZone">
                    <div class="icon">📁</div>
                    <p>\(strings.dropText)</p>
                    <p class="formats">\(strings.formats)</p>
                </div>
                <input type="file" id="fileInput" multiple
                       accept=".epub,.pdf,.cbz,.lcpdf,.webpub,.audiobook,.lcpa,.lcpl,.zip,.txt">
                <ul class="file-list" id="fileList"></ul>
                <div class="tip">
                    \(strings.tip)
                </div>
            </div>
            <script>
                const L10N = {
                    uploading: '\(strings.uploading)',
                    done: '\(strings.done)',
                    failed: '\(strings.failed)',
                    unknown: '\(strings.unknown)'
                };
                const dropZone = document.getElementById('dropZone');
                const fileInput = document.getElementById('fileInput');
                const fileList = document.getElementById('fileList');
                dropZone.addEventListener('click', () => fileInput.click());
                dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('dragover'); });
                dropZone.addEventListener('dragleave', () => { dropZone.classList.remove('dragover'); });
                dropZone.addEventListener('drop', (e) => { e.preventDefault(); dropZone.classList.remove('dragover'); handleFiles(e.dataTransfer.files); });
                fileInput.addEventListener('change', () => { handleFiles(fileInput.files); fileInput.value = ''; });
                function handleFiles(files) { for (const file of files) { uploadFile(file); } }
                function uploadFile(file) {
                    const li = document.createElement('li');
                    li.innerHTML = '<span class="name">' + file.name + '</span><span class="status uploading">' + L10N.uploading + '</span>';
                    fileList.prepend(li);
                    const status = li.querySelector('.status');
                    const formData = new FormData();
                    formData.append('files', file, file.name);
                    fetch('/upload', { method: 'POST', body: formData })
                        .then(r => r.json())
                        .then(data => {
                            if (data.failed && data.failed.includes(file.name)) {
                                status.textContent = L10N.failed;
                                status.className = 'status error';
                            } else if (data.uploaded && data.uploaded.includes(file.name)) {
                                status.textContent = L10N.done;
                                status.className = 'status done';
                            } else {
                                status.textContent = L10N.unknown;
                                status.className = 'status error';
                            }
                        })
                        .catch(() => { status.textContent = L10N.failed; status.className = 'status error'; });
                }
            </script>
        </body>
        </html>
        """
    }
}
