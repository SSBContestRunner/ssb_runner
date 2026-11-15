import Cocoa
import CoreAudio
import FlutterMacOS

/// Reports the default output device, its volume and its mute flag, and pushes
/// a wake-up whenever one of those properties changes.
///
/// Dart only needs the notification itself: it re-reads the state through the
/// same method channel, so the event path and the polling fallback can never
/// disagree (see docs/design/audio_preflight_check_design.md §4.2.2, §4.3.1).
///
/// Deliberately uses CoreAudio instead of `osascript`: release builds run inside
/// the App Sandbox, where spawning helper processes is unreliable.
final class AudioOutputProbe: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private let queue = DispatchQueue(label: "ssb.runner.audio-output")
  private var systemListener: AudioObjectPropertyListenerBlock?
  private var deviceListener: AudioObjectPropertyListenerBlock?
  private var observedDevice = AudioDeviceID(0)

  /// `kAudioHardwareServiceDeviceProperty_VirtualMasterVolume` ("vmvc").
  ///
  /// The constant is no longer exported by the current macOS SDK, but devices
  /// that only expose a virtual master control still answer to this selector.
  private static let virtualMasterVolumeSelector: AudioObjectPropertySelector =
    0x766D_7663

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "ssb_runner/audio_output",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "ssb_runner/audio_output/events",
      binaryMessenger: messenger
    )
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "read":
        result(self.readState())
      case "openSoundSettings":
        self.openSoundSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    eventChannel.setStreamHandler(self)
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    installListeners()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    removeListeners()
    return nil
  }

  // MARK: - Readings

  private func readState() -> [String: Any] {
    guard let device = defaultOutputDevice() else {
      return ["hasDevice": false]
    }

    var state: [String: Any] = ["hasDevice": true]
    if let name = deviceName(device) {
      state["deviceName"] = name
    }
    if let volume = outputVolume(device) {
      state["volume"] = Double(volume)
    }
    if let muted = outputMuted(device) {
      state["muted"] = muted
    }
    return state
  }

  /// Opens System Settings › Sound.
  ///
  /// Uses `NSWorkspace` instead of spawning `open`: release builds are
  /// sandboxed and cannot launch helper processes.
  private func openSoundSettings(result: @escaping FlutterResult) {
    let url = URL(
      string: "x-apple.systempreferences:com.apple.Sound-Settings.extension"
    )!
    if NSWorkspace.shared.open(url) {
      result(nil)
    } else {
      result(
        FlutterError(
          code: "open-failed",
          message: "The system sound settings could not be opened.",
          details: nil
        )
      )
    }
  }

  private func defaultOutputDevice() -> AudioDeviceID? {
    var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &device
    )
    guard status == noErr, device != 0 else { return nil }
    return device
  }

  /// Prefers the device-wide volume. Devices that only expose per-channel
  /// controls fall back to channel 1, then to the virtual master volume; a
  /// device with none of them stays `unknown` instead of guessing.
  private func outputVolume(_ device: AudioDeviceID) -> Float? {
    for address in [
      propertyAddress(kAudioDevicePropertyVolumeScalar),
      propertyAddress(kAudioDevicePropertyVolumeScalar, element: 1),
      propertyAddress(Self.virtualMasterVolumeSelector),
    ] {
      if let value = readFloat(device, address) {
        return value
      }
    }
    return nil
  }

  private func outputMuted(_ device: AudioDeviceID) -> Bool? {
    for address in [
      propertyAddress(kAudioDevicePropertyMute),
      propertyAddress(kAudioDevicePropertyMute, element: 1),
    ] {
      var mutableAddress = address
      guard AudioObjectHasProperty(device, &mutableAddress) else { continue }
      var muted = UInt32(0)
      var size = UInt32(MemoryLayout<UInt32>.size)
      let status = AudioObjectGetPropertyData(
        device,
        &mutableAddress,
        0,
        nil,
        &size,
        &muted
      )
      if status == noErr {
        return muted != 0
      }
    }
    return nil
  }

  private func readFloat(
    _ device: AudioDeviceID,
    _ address: AudioObjectPropertyAddress
  ) -> Float? {
    var mutableAddress = address
    guard AudioObjectHasProperty(device, &mutableAddress) else { return nil }
    var value = Float(0)
    var size = UInt32(MemoryLayout<Float>.size)
    let status = AudioObjectGetPropertyData(
      device,
      &mutableAddress,
      0,
      nil,
      &size,
      &value
    )
    return status == noErr ? value : nil
  }

  private func deviceName(_ device: AudioDeviceID) -> String? {
    var address = propertyAddress(
      kAudioObjectPropertyName,
      scope: kAudioObjectPropertyScopeGlobal
    )
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
      device,
      &address,
      0,
      nil,
      &size,
      &name
    )
    guard status == noErr, let value = name?.takeRetainedValue() else {
      return nil
    }
    return value as String
  }

  private func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
  ) -> AudioObjectPropertyAddress {
    return AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: element
    )
  }

  // MARK: - Change notifications

  private func installListeners() {
    removeListeners()

    let systemListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.notifyChange()
    }
    var systemAddress = propertyAddress(
      kAudioHardwarePropertyDefaultOutputDevice,
      scope: kAudioObjectPropertyScopeGlobal
    )
    AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &systemAddress,
      queue,
      systemListener
    )
    self.systemListener = systemListener

    observedDevice = defaultOutputDevice() ?? 0
    addDeviceListeners(observedDevice)
  }

  private func addDeviceListeners(_ device: AudioDeviceID) {
    guard device != 0 else { return }

    let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.notifyChange()
    }

    for address in [
      propertyAddress(kAudioDevicePropertyVolumeScalar),
      propertyAddress(kAudioDevicePropertyVolumeScalar, element: 1),
      propertyAddress(Self.virtualMasterVolumeSelector),
      propertyAddress(kAudioDevicePropertyMute),
      propertyAddress(kAudioDevicePropertyMute, element: 1),
    ] {
      var mutableAddress = address
      guard AudioObjectHasProperty(device, &mutableAddress) else { continue }
      AudioObjectAddPropertyListenerBlock(
        device,
        &mutableAddress,
        queue,
        listener
      )
    }

    deviceListener = listener
  }

  private func notifyChange() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      // The default device itself can change; its properties need new
      // listeners before the next read.
      let current = self.defaultOutputDevice() ?? 0
      if current != self.observedDevice {
        self.removeDeviceListeners(self.observedDevice)
        self.observedDevice = current
        self.addDeviceListeners(current)
      }
      self.eventSink?(["changed": true])
    }
  }

  private func removeDeviceListeners(_ device: AudioDeviceID) {
    guard device != 0, let listener = deviceListener else { return }
    for address in [
      propertyAddress(kAudioDevicePropertyVolumeScalar),
      propertyAddress(kAudioDevicePropertyVolumeScalar, element: 1),
      propertyAddress(Self.virtualMasterVolumeSelector),
      propertyAddress(kAudioDevicePropertyMute),
      propertyAddress(kAudioDevicePropertyMute, element: 1),
    ] {
      var mutableAddress = address
      AudioObjectRemovePropertyListenerBlock(
        device,
        &mutableAddress,
        queue,
        listener
      )
    }
    deviceListener = nil
  }

  private func removeListeners() {
    if let listener = systemListener {
      var address = propertyAddress(
        kAudioHardwarePropertyDefaultOutputDevice,
        scope: kAudioObjectPropertyScopeGlobal
      )
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        queue,
        listener
      )
      systemListener = nil
    }
    removeDeviceListeners(observedDevice)
    observedDevice = 0
  }
}
