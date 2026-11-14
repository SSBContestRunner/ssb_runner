#include "audio_output_probe.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <functiondiscoverykeys_devpkey.h>
#include <propvarutil.h>

#include <string>

#include "utils.h"

namespace {

constexpr char kMethodChannelName[] = "ssb_runner/audio_output";
constexpr char kEventChannelName[] = "ssb_runner/audio_output/events";

std::string DeviceName(IMMDevice* device) {
  Microsoft::WRL::ComPtr<IPropertyStore> properties;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &properties))) {
    return std::string();
  }

  PROPVARIANT value;
  PropVariantInit(&value);
  std::string name;
  if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &value)) &&
      value.vt == VT_LPWSTR && value.pwszVal != nullptr) {
    name = Utf8FromUtf16(value.pwszVal);
  }
  PropVariantClear(&value);
  return name;
}

}  // namespace

AudioOutputProbe::AudioOutputProbe(flutter::BinaryMessenger* messenger,
                                   HWND notification_window)
    : notification_window_(notification_window) {
  method_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "read") {
          result->NotImplemented();
          return;
        }

        flutter::EncodableMap state;
        // A failed read answers with an empty map: every field stays unknown
        // and Dart shows no badge instead of guessing.
        if (ReadState(&state)) {
          result->Success(flutter::EncodableValue(state));
        } else {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{}));
        }
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        event_sink_ = std::move(events);
        Subscribe();
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        event_sink_.reset();
        Unsubscribe();
        return nullptr;
      });
  event_channel_->SetStreamHandler(std::move(handler));
}

AudioOutputProbe::~AudioOutputProbe() {
  Unsubscribe();
}

void AudioOutputProbe::NotifyChanged() {
  if (event_sink_) {
    event_sink_->Success(flutter::EncodableValue());
  }
}

// IUnknown -----------------------------------------------------------------

HRESULT AudioOutputProbe::QueryInterface(REFIID riid, void** object) {
  if (object == nullptr) {
    return E_POINTER;
  }
  if (riid == __uuidof(IUnknown) || riid == __uuidof(IMMNotificationClient)) {
    *object = static_cast<IMMNotificationClient*>(this);
    AddRef();
    return S_OK;
  }
  if (riid == __uuidof(IAudioEndpointVolumeCallback)) {
    *object = static_cast<IAudioEndpointVolumeCallback*>(this);
    AddRef();
    return S_OK;
  }
  *object = nullptr;
  return E_NOINTERFACE;
}

ULONG AudioOutputProbe::AddRef() {
  // FlutterWindow owns this instance for the process lifetime, so the count is
  // pinned: no callback release can ever free it.
  return 1;
}

ULONG AudioOutputProbe::Release() {
  return 1;
}

// IMMNotificationClient ----------------------------------------------------

HRESULT AudioOutputProbe::OnDeviceStateChanged(LPCWSTR device_id,
                                               DWORD new_state) {
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

HRESULT AudioOutputProbe::OnDeviceAdded(LPCWSTR device_id) {
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

HRESULT AudioOutputProbe::OnDeviceRemoved(LPCWSTR device_id) {
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

HRESULT AudioOutputProbe::OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                                 LPCWSTR device_id) {
  if (flow != eRender || role != eConsole) {
    return S_OK;
  }
  RenewEndpointVolume();
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

HRESULT AudioOutputProbe::OnPropertyValueChanged(LPCWSTR device_id,
                                                 const PROPERTYKEY key) {
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

// IAudioEndpointVolumeCallback ---------------------------------------------

HRESULT AudioOutputProbe::OnNotify(PAUDIO_VOLUME_NOTIFICATION_DATA data) {
  PostMessage(notification_window_, kChangedMessage, 0, 0);
  return S_OK;
}

// Registration -------------------------------------------------------------

void AudioOutputProbe::Subscribe() {
  if (subscribed_) {
    return;
  }
  subscribed_ = true;

  if (!enumerator_ &&
      FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator_)))) {
    enumerator_.Reset();
    return;
  }

  enumerator_->RegisterEndpointNotificationCallback(this);
  RenewEndpointVolume();
}

void AudioOutputProbe::Unsubscribe() {
  if (!subscribed_) {
    return;
  }
  subscribed_ = false;

  if (endpoint_volume_) {
    endpoint_volume_->UnregisterControlChangeNotify(this);
    endpoint_volume_.Reset();
  }
  if (enumerator_) {
    enumerator_->UnregisterEndpointNotificationCallback(this);
    enumerator_.Reset();
  }
}

void AudioOutputProbe::RenewEndpointVolume() {
  if (endpoint_volume_) {
    endpoint_volume_->UnregisterControlChangeNotify(this);
    endpoint_volume_.Reset();
  }
  if (!enumerator_ || !subscribed_) {
    return;
  }

  Microsoft::WRL::ComPtr<IMMDevice> device;
  if (FAILED(enumerator_->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    return;
  }
  if (SUCCEEDED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                                 nullptr, &endpoint_volume_))) {
    endpoint_volume_->RegisterControlChangeNotify(this);
  }
}

// Reading ------------------------------------------------------------------

bool AudioOutputProbe::ReadState(flutter::EncodableMap* out) {
  Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&enumerator)))) {
    return false;
  }

  Microsoft::WRL::ComPtr<IMMDevice> device;
  HRESULT result = enumerator->GetDefaultAudioEndpoint(eRender, eConsole,
                                                       &device);
  if (result == E_NOTFOUND) {
    out->insert({flutter::EncodableValue("hasDevice"),
                 flutter::EncodableValue(false)});
    return true;
  }
  if (FAILED(result)) {
    return false;
  }

  out->insert(
      {flutter::EncodableValue("hasDevice"), flutter::EncodableValue(true)});

  const std::string name = DeviceName(device.Get());
  if (!name.empty()) {
    out->insert(
        {flutter::EncodableValue("deviceName"), flutter::EncodableValue(name)});
  }

  Microsoft::WRL::ComPtr<IAudioEndpointVolume> volume;
  if (FAILED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                              nullptr, &volume))) {
    return true;
  }

  float level = 0.0f;
  if (SUCCEEDED(volume->GetMasterVolumeLevelScalar(&level))) {
    out->insert({flutter::EncodableValue("volume"),
                 flutter::EncodableValue(static_cast<double>(level))});
  }

  BOOL muted = FALSE;
  if (SUCCEEDED(volume->GetMute(&muted))) {
    out->insert({flutter::EncodableValue("muted"),
                 flutter::EncodableValue(muted != FALSE)});
  }
  return true;
}
