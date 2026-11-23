//
//  ShareViewController.swift
//  NexusTalk Share Extension
//
//  Self-contained share extension that does not depend on the
//  receive_sharing_intent package. It saves shared media to the app group
//  UserDefaults (key "ShareKey") and opens the host app via the
//  "ShareMedia-<bundleId>:share" URL scheme, which is the exact format the
//  receive_sharing_intent plugin reads on the host side.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices
import Photos
import AVFoundation

// MARK: - Data model (must match receive_sharing_intent's SharedMediaFile)

private let kUserDefaultsKey = "ShareKey"
private let kSchemePrefix = "ShareMedia"
private let kAppGroupId = "group.im.nyx.app"
private let kHostAppBundleId = "im.nyx.app"

private enum SharedMediaType: String, Codable, CaseIterable {
    case image, video, text, file, url

    var utTypeIdentifier: String {
        if #available(iOS 14.0, *) {
            switch self {
            case .image: return UTType.image.identifier
            case .video: return UTType.movie.identifier
            case .text:  return UTType.text.identifier
            case .file:  return UTType.fileURL.identifier
            case .url:   return UTType.url.identifier
            }
        }
        switch self {
        case .image: return "public.image"
        case .video: return "public.movie"
        case .text:  return "public.text"
        case .file:  return "public.file-url"
        case .url:   return "public.url"
        }
    }
}

private struct SharedMediaFile: Codable {
    var path: String
    var mimeType: String?
    var thumbnail: String?
    var duration: Double?
    var message: String?
    var type: SharedMediaType

    init(path: String, mimeType: String? = nil, thumbnail: String? = nil,
         duration: Double? = nil, message: String? = nil, type: SharedMediaType) {
        self.path = path
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.message = message
        self.type = type
    }
}

// MARK: - Share Extension view controller

class ShareViewController: UIViewController {
    private var sharedMedia: [SharedMediaFile] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processSharedContent()
    }

    // MARK: - Process attachments

    private func processSharedContent() {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = content.attachments else {
            completeRequest()
            return
        }

        let group = DispatchGroup()
        for (index, attachment) in attachments.enumerated() {
            for mediaType in SharedMediaType.allCases {
                if attachment.hasItemConformingToTypeIdentifier(mediaType.utTypeIdentifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: mediaType.utTypeIdentifier) { [weak self] data, error in
                        defer { group.leave() }
                        guard let self = self, error == nil else { return }
                        self.handleAttachment(data: data, type: mediaType, index: index)
                    }
                    break
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.saveAndRedirect()
        }
    }

    private func handleAttachment(data: NSSecureCoding?, type: SharedMediaType, index: Int) {
        switch type {
        case .text:
            if let text = data as? String {
                sharedMedia.append(SharedMediaFile(path: text, mimeType: "text/plain", type: .text))
            }
        case .url:
            if let url = data as? URL {
                sharedMedia.append(SharedMediaFile(path: url.absoluteString, type: .url))
            }
        case .image:
            if let url = data as? URL {
                handleFile(url: url, type: .image)
            } else if let image = data as? UIImage {
                handleUIImage(image)
            }
        case .video:
            if let url = data as? URL {
                handleFile(url: url, type: .video)
            }
        case .file:
            if let url = data as? URL {
                handleFile(url: url, type: .file)
            }
        }
    }

    // MARK: - File handling

    private func handleUIImage(_ image: UIImage) {
        let fileName = UUID().uuidString + ".png"
        guard let containerURL = appGroupContainerURL() else { return }
        let destURL = containerURL.appendingPathComponent(fileName)
        guard let pngData = image.pngData() else { return }
        do {
            try pngData.write(to: destURL)
            sharedMedia.append(SharedMediaFile(
                path: destURL.absoluteString.removingPercentEncoding ?? destURL.absoluteString,
                mimeType: "image/png",
                type: .image
            ))
        } catch {
            print("[Share] Cannot write temp image: \(error)")
        }
    }

    private func handleFile(url: URL, type: SharedMediaType) {
        let fileName = url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent
        guard let containerURL = appGroupContainerURL() else { return }
        let destURL = containerURL.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            let path = destURL.absoluteString.removingPercentEncoding ?? destURL.absoluteString

            if type == .video {
                if let info = videoInfo(from: url) {
                    sharedMedia.append(SharedMediaFile(
                        path: path,
                        mimeType: url.mimeType(),
                        thumbnail: info.thumbnail?.removingPercentEncoding,
                        duration: info.duration,
                        type: .video
                    ))
                } else {
                    sharedMedia.append(SharedMediaFile(path: path, mimeType: url.mimeType(), type: .video))
                }
            } else {
                sharedMedia.append(SharedMediaFile(path: path, mimeType: url.mimeType(), type: type))
            }
        } catch {
            print("[Share] Cannot copy file \(url) to \(destURL): \(error)")
        }
    }

    // MARK: - Video thumbnail & duration

    private func videoInfo(from url: URL) -> (thumbnail: String?, duration: Double)? {
        let asset = AVAsset(url: url)
        let duration = (CMTimeGetSeconds(asset.duration) * 1000).rounded()
        guard let containerURL = appGroupContainerURL() else { return nil }
        let thumbName = Data(url.lastPathComponent.utf8).base64EncodedString()
            .replacingOccurrences(of: "==", with: "") + ".jpg"
        let thumbURL = containerURL.appendingPathComponent(thumbName)
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            return (thumbURL.absoluteString, duration)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        do {
            let cgImage = try generator.copyCGImage(
                at: CMTimeMakeWithSeconds(1, preferredTimescale: 1), actualTime: nil)
            try UIImage(cgImage: cgImage).pngData()?.write(to: thumbURL)
            return (thumbURL.absoluteString, duration)
        } catch {
            return nil
        }
    }

    // MARK: - Save & redirect

    private func saveAndRedirect() {
        guard !sharedMedia.isEmpty else {
            completeRequest()
            return
        }
        let defaults = UserDefaults(suiteName: kAppGroupId)
        if let data = try? JSONEncoder().encode(sharedMedia) {
            defaults?.set(data, forKey: kUserDefaultsKey)
            defaults?.synchronize()
        }
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        guard let url = URL(string: "\(kSchemePrefix)-\(kHostAppBundleId):share") else {
            completeRequest()
            return
        }
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = current.next
        }
        completeRequest()
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - Helpers

    private func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: kAppGroupId)
    }
}

// MARK: - URL MIME type helper

private extension URL {
    func mimeType() -> String {
        if #available(iOS 14.0, *) {
            if let mime = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
                return mime
            }
        } else {
            if let uti = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassFilenameExtension, pathExtension as NSString, nil)?.takeRetainedValue(),
               let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mime as String
            }
        }
        return "application/octet-stream"
    }
}
