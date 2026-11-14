#ifndef RUNNER_AUDIO_OUTPUT_PROBE_H_
#define RUNNER_AUDIO_OUTPUT_PROBE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

#include <endpointvolume.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <memory>

// Reports the default WASAPI render endpoint, its master volume and its mute
// flag, and posts a window message whenever one of them changes.
//
// Dart only reacts to the wake-up: it re-reads through the same method channel,
// so the event path and the polling fallback can never disagree (see
// docs/design/audio_preflight_check_design.md §4.2.2, §4.3.1).
class AudioOutputProbe : public IMMNotificationClient,
                         public IAudioEndpointVolumeCallback {
 public:
  // Posted to the notification window on the platform thread when the output
  // state may have changed.
  static constexpr UINT kChangedMessage = WM_APP + 0x51;

  AudioOutputProbe(flutter::BinaryMessenger* messenger, HWND notification_window);
  ~AudioOutputProbe() override;

  AudioOutputProbe(const AudioOutputProbe&) = delete;
  AudioOutputProbe& operator=(const AudioOutputProbe&) = delete;

  // Pushes a wake-up to Dart. Must be called on the platform thread.
  void NotifyChanged();

  // IUnknown. The instance is owned by FlutterWindow and outlives every
  // registration, so the counts never free it.
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void** object) override;
  ULONG STDMETHODCALLTYPE AddRef() override;
  ULONG STDMETHODCALLTYPE Release() override;

  // IMMNotificationClient
  HRESULT STDMETHODCALLTYPE OnDeviceStateChanged(LPCWSTR device_id,
                                                 DWORD new_state) override;
  HRESULT STDMETHODCALLTYPE OnDeviceAdded(LPCWSTR device_id) override;
  HRESULT STDMETHODCALLTYPE OnDeviceRemoved(LPCWSTR device_id) override;
  HRESULT STDMETHODCALLTYPE OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                                   LPCWSTR device_id) override;
  HRESULT STDMETHODCALLTYPE OnPropertyValueChanged(LPCWSTR device_id,
                                                   const PROPERTYKEY key) override;

  // IAudioEndpointVolumeCallback
  HRESULT STDMETHODCALLTYPE OnNotify(PAUDIO_VOLUME_NOTIFICATION_DATA data) override;

 private:
  // Registers the notifications; called when Dart starts listening.
  void Subscribe();
  void Unsubscribe();
  void RenewEndpointVolume();

  // Fills |out| with the current reading. Returns false when even the endpoint
  // could not be resolved, which Dart treats as "unknown".
  bool ReadState(flutter::EncodableMap* out);

  HWND notification_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator_;
  Microsoft::WRL::ComPtr<IAudioEndpointVolume> endpoint_volume_;
  bool subscribed_ = false;
};

#endif  // RUNNER_AUDIO_OUTPUT_PROBE_H_
