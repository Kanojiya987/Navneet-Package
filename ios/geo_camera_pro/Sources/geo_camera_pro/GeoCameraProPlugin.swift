import Flutter
import CoreLocation
import UIKit

public class GeoCameraProPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CLLocationManagerDelegate {
  private static let latestLocationKey = "geo_camera_pro.latest_location"
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?
  private var pendingStartResult: FlutterResult?
  private var tracking = false
  private var requestedAlwaysAuthorization = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "geo_camera_pro", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(
      name: "geo_camera_pro/location_events",
      binaryMessenger: registrar.messenger()
    )
    let instance = GeoCameraProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
  }

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "startTracking":
      startTracking(call, result: result)
    case "stopTracking":
      if let pendingResult = pendingStartResult {
        pendingStartResult = nil
        pendingResult(FlutterError(
          code: "tracking_cancelled",
          message: "Location tracking start was cancelled.",
          details: nil
        ))
      }
      locationManager.stopUpdatingLocation()
      locationManager.allowsBackgroundLocationUpdates = false
      locationManager.showsBackgroundLocationIndicator = false
      tracking = false
      result(nil)
    case "isTracking":
      result(tracking)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if let location = UserDefaults.standard.dictionary(forKey: Self.latestLocationKey) {
      events(location)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func startTracking(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if tracking {
      result(nil)
      return
    }

    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(
        code: "location_unavailable",
        message: "Location services are disabled on this device.",
        details: nil
      ))
      return
    }

    guard let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String],
          backgroundModes.contains("location") else {
      result(FlutterError(
        code: "background_mode_not_configured",
        message: "Add the location value to the host app's UIBackgroundModes.",
        details: nil
      ))
      return
    }

    let arguments = call.arguments as? [String: Any]
    let distanceFilter = (arguments?["distanceFilterMeters"] as? NSNumber)?.doubleValue ?? 0
    locationManager.distanceFilter = max(0, distanceFilter)
    locationManager.activityType = .other
    locationManager.pausesLocationUpdatesAutomatically = false

    switch locationManager.authorizationStatus {
    case .notDetermined:
      pendingStartResult = result
      requestedAlwaysAuthorization = true
      locationManager.requestAlwaysAuthorization()
    case .authorizedWhenInUse:
      pendingStartResult = result
      requestedAlwaysAuthorization = true
      locationManager.requestAlwaysAuthorization()
    case .authorizedAlways:
      beginLocationUpdates(result: result)
    case .denied, .restricted:
      result(FlutterError(
        code: "location_permission_denied",
        message: "Always location permission is required for background tracking.",
        details: nil
      ))
    @unknown default:
      result(FlutterError(
        code: "location_permission_denied",
        message: "The location authorization status is unknown.",
        details: nil
      ))
    }
  }

  private func beginLocationUpdates(result: @escaping FlutterResult) {
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.showsBackgroundLocationIndicator = true
    locationManager.startUpdatingLocation()
    tracking = true
    result(nil)
  }

  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let result = pendingStartResult else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways:
      pendingStartResult = nil
      requestedAlwaysAuthorization = false
      beginLocationUpdates(result: result)
    case .denied, .restricted:
      pendingStartResult = nil
      requestedAlwaysAuthorization = false
      result(FlutterError(
        code: "location_permission_denied",
        message: "Always location permission was denied.",
        details: nil
      ))
    case .authorizedWhenInUse:
      if requestedAlwaysAuthorization {
        pendingStartResult = nil
        requestedAlwaysAuthorization = false
        result(FlutterError(
          code: "location_permission_denied",
          message: "Change location access to Always in Settings to track in the background.",
          details: nil
        ))
      }
    case .notDetermined:
      break
    @unknown default:
      pendingStartResult = nil
      result(FlutterError(
        code: "location_permission_denied",
        message: "The location authorization status is unknown.",
        details: nil
      ))
    }
  }

  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
    let event: [String: Any] = [
      "type": "location",
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
      "timestamp": Int64(location.timestamp.timeIntervalSince1970 * 1000)
    ]
    UserDefaults.standard.set(event, forKey: Self.latestLocationKey)
    eventSink?(event)
  }

  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    let locationError = error as? CLError
    let code = locationError?.code == .denied
      ? "location_permission_denied"
      : "location_unavailable"
    if locationError?.code == .denied {
      tracking = false
      locationManager.stopUpdatingLocation()
      locationManager.allowsBackgroundLocationUpdates = false
      locationManager.showsBackgroundLocationIndicator = false
    }
    eventSink?([
      "type": "error",
      "code": code,
      "message": error.localizedDescription
    ])
  }
}
