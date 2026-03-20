import Flutter
import UIKit
import AVFoundation
import Photos
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Проверяем сетевые настройки
    print("🌐 ========== NETWORK CONFIGURATION CHECK ==========")
    if let atsDict = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any] {
      print("✅ NSAppTransportSecurity found in Info.plist")
      if let allowsArbitraryLoads = atsDict["NSAllowsArbitraryLoads"] as? Bool {
        print("🌐 NSAllowsArbitraryLoads: \(allowsArbitraryLoads)")
      }
      if let exceptionDomains = atsDict["NSExceptionDomains"] as? [String: Any] {
        print("🌐 NSExceptionDomains count: \(exceptionDomains.count)")
        for (domain, config) in exceptionDomains {
          print("🌐 Exception domain: \(domain)")
          if let domainConfig = config as? [String: Any] {
            print("   - NSExceptionAllowsInsecureHTTPLoads: \(domainConfig["NSExceptionAllowsInsecureHTTPLoads"] ?? "not set")")
          }
        }
      }
    } else {
      print("❌ NSAppTransportSecurity NOT FOUND in Info.plist!")
    }
    
    // Проверяем доступность сети
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { path in
      if path.status == .satisfied {
        print("✅ Network is available")
        print("   - Uses WiFi: \(path.usesInterfaceType(.wifi))")
        print("   - Uses Cellular: \(path.usesInterfaceType(.cellular))")
        print("   - Uses Ethernet: \(path.usesInterfaceType(.wiredEthernet))")
      } else {
        print("❌ Network is NOT available")
      }
    }
    let queue = DispatchQueue(label: "NetworkMonitor")
    monitor.start(queue: queue)
    
    // Настраиваем аудио сессию для записи/воспроизведения.
    // Ранее .playback + bluetooth options давали -50 (invalid parameter) на некоторых iOS версиях.
    do {
      let audioSession = AVAudioSession.sharedInstance()
      // .playAndRecord нужна для голосовых (record) + прослушивания (playback).
      // Минимальный набор опций, который стабильно не падает с -50.
      try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
      try audioSession.setActive(true)
      print("✅ Audio session configured for playback")
    } catch {
      print("❌ Failed to configure audio session: \(error)")
    }
    
    // Настраиваем канал для запроса разрешений из Flutter
    let controller = window?.rootViewController as! FlutterViewController
    let permissionChannel = FlutterMethodChannel(
      name: "com.vvedenskii.messenger/permissions",
      binaryMessenger: controller.binaryMessenger
    )
    
    permissionChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "requestMicrophonePermission":
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          DispatchQueue.main.async {
            print("🎤 Native microphone permission request result: \(granted)")
            result(granted)
          }
        }
      case "requestCameraPermission":
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async {
            print("📷 Native camera permission request result: \(granted)")
            result(granted)
          }
        }
      case "requestPhotoLibraryPermission":
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
          DispatchQueue.main.async {
            let granted = status == .authorized || status == .limited
            print("📸 Native photo library permission request result: \(granted), status: \(status.rawValue)")
            result(granted)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Проверяем наличие ключей разрешений в Info.plist
    if let microphoneDesc = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String {
      print("✅ NSMicrophoneUsageDescription found: \(microphoneDesc)")
    } else {
      print("❌ NSMicrophoneUsageDescription NOT FOUND in Info.plist!")
    }
    
    if let cameraDesc = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String {
      print("✅ NSCameraUsageDescription found: \(cameraDesc)")
    } else {
      print("❌ NSCameraUsageDescription NOT FOUND in Info.plist!")
    }
    
    if let photoDesc = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String {
      print("✅ NSPhotoLibraryUsageDescription found: \(photoDesc)")
    } else {
      print("❌ NSPhotoLibraryUsageDescription NOT FOUND in Info.plist!")
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
