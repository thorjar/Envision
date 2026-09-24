import AVKit


extension PlaybackEngine: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pipController === controller else { return }
        isPiPActive = true
        playbackWarning = nil
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard pipController === controller else { return }
        isPiPActive = false
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        playbackWarning = "Picture in Picture could not start: \(error.localizedDescription)"
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true) // Playback page stays mounted while PiP is active.
    }
}
