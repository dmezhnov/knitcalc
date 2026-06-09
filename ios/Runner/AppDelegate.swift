import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Same channel name as Android (knitcalc/android_update); here it only serves
  // saveImageToGallery, which writes a photo into the iOS photo library.
  private let channelName = "knitcalc/android_update"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "KnitCalcPhotoSave")?.messenger()
    {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "saveImageToGallery" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let data = (args["bytes"] as? FlutterStandardTypedData)?.data
        else {
          result(FlutterError(code: "bad_args", message: "Missing image bytes", details: nil))
          return
        }
        self?.saveImageToGallery(data, result: result)
      }
    }
  }

  /// Saves [data] (a JPEG) into the photo library after requesting add-only
  /// permission. Calls [result] with whether the save succeeded, on the main
  /// thread.
  private func saveImageToGallery(_ data: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: data) else {
      result(false)
      return
    }

    func performSave() {
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      } completionHandler: { success, _ in
        DispatchQueue.main.async { result(success) }
      }
    }

    let granted: (PHAuthorizationStatus) -> Void = { status in
      // .limited exists only on iOS 14+, so it must stay behind #available
      // even though the add-only request below already implies iOS 14.
      let allowed: Bool
      if #available(iOS 14, *) {
        allowed = status == .authorized || status == .limited
      } else {
        allowed = status == .authorized
      }
      if allowed {
        performSave()
      } else {
        DispatchQueue.main.async { result(false) }
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: granted)
    } else {
      PHPhotoLibrary.requestAuthorization(granted)
    }
  }
}
