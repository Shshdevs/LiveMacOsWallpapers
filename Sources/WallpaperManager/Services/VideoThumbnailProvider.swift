import AVFoundation
import AppKit

final class VideoThumbnailProvider {
    private let library: PlaylistLibrary
    private var images: [UUID: NSImage] = [:]
    private var generators: [UUID: AVAssetImageGenerator] = [:]
    private var pendingCallbacks: [UUID: [(NSImage?) -> Void]] = [:]
    private var remainingFrames: [UUID: Int] = [:]

    init(library: PlaylistLibrary) {
        self.library = library
    }

    func cachedImage(for playlist: WallpaperPlaylist) -> NSImage? {
        images[playlist.id]
    }

    func loadImage(for playlist: WallpaperPlaylist, completion: @escaping (NSImage?) -> Void) {
        if let image = images[playlist.id] {
            completion(image)
            return
        }
        pendingCallbacks[playlist.id, default: []].append(completion)
        if generators[playlist.id] != nil {
            return
        }
        guard let firstVideo = library.videos(in: playlist).first else {
            finish(playlist.id, image: nil)
            return
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: firstVideo))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)
        generators[playlist.id] = generator
        let times = [
            NSValue(time: CMTime(seconds: 0.5, preferredTimescale: 600)),
            NSValue(time: .zero)
        ]
        remainingFrames[playlist.id] = times.count
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, frame, _, result, _ in
            DispatchQueue.main.async {
                guard let self, self.generators[playlist.id] === generator else { return }
                if result == .succeeded, let frame {
                    let image = NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
                    self.generators[playlist.id]?.cancelAllCGImageGeneration()
                    self.finish(playlist.id, image: image)
                } else {
                    let remaining = (self.remainingFrames[playlist.id] ?? 1) - 1
                    self.remainingFrames[playlist.id] = remaining
                    if remaining <= 0 {
                        self.finish(playlist.id, image: nil)
                    }
                }
            }
        }
    }

    private func finish(_ playlistID: UUID, image: NSImage?) {
        if let image {
            images[playlistID] = image
        }
        generators[playlistID] = nil
        remainingFrames[playlistID] = nil
        let callbacks = pendingCallbacks.removeValue(forKey: playlistID) ?? []
        callbacks.forEach { $0(image) }
    }

    func invalidate(_ playlistID: UUID) {
        generators[playlistID]?.cancelAllCGImageGeneration()
        generators[playlistID] = nil
        remainingFrames[playlistID] = nil
        pendingCallbacks[playlistID] = nil
        images[playlistID] = nil
    }
}
