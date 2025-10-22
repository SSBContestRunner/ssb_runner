import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:toastification/toastification.dart';

class _Options {
  final String modeId;
  final int durationInMinutes;
  final PhonicType phonicType;

  _Options({
    required this.modeId,
    required this.durationInMinutes,
    required this.phonicType,
  });

  _Options copyWith({
    String? modeId,
    int? durationInMinutes,
    PhonicType? phonicType,
  }) {
    return _Options(
      modeId: modeId ?? this.modeId,
      durationInMinutes: durationInMinutes ?? this.durationInMinutes,
      phonicType: phonicType ?? this.phonicType,
    );
  }
}

class _OptionsSettingCubit extends Cubit<_Options> {
  final AppSettings _appSettings;

  _OptionsSettingCubit({required AppSettings appSettings})
    : _appSettings = appSettings,
      super(
        _Options(
          modeId: appSettings.contestModeId,
          durationInMinutes: appSettings.contestDuration,
          phonicType: appSettings.phonicType,
        ),
      );

  void changeMode(String modeId) {
    _appSettings.contestModeId = modeId;
    emit(state.copyWith(modeId: modeId));
  }

  void changeDuration(String modeString) {
    final durationInMinutes = int.tryParse(modeString) ?? 0;

    if (durationInMinutes > maxDurationInMinutesPerRun) {
      toastification.show(
        title: Text('Max duration is $maxDurationInMinutesPerRun minutes'),
        autoCloseDuration: Duration(seconds: 2),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
      );
      emit(state.copyWith(durationInMinutes: maxDurationInMinutesPerRun));
      return;
    }

    _appSettings.contestDuration = durationInMinutes;
  }

  void changePhonicType(PhonicType? phonicType) {
    if (phonicType != null) {
      _appSettings.phonicType = phonicType;
      emit(state.copyWith(phonicType: phonicType));
    }
  }
}

class OptionsSetting extends StatefulWidget {
  const OptionsSetting({super.key});

  @override
  State<StatefulWidget> createState() {
    return _OptionsSettingState();
  }
}

class _OptionsSettingState extends State<OptionsSetting> {
  final _modeController = TextEditingController();
  final _durationController = TextEditingController();
  final _phonicTypeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = _OptionsSettingCubit(appSettings: context.read());
        _updateState(cubit.state);
        return cubit;
      },
      child: BlocConsumer<_OptionsSettingCubit, _Options>(
        listener: (context, options) {
          _updateState(options);
        },
        builder: (context, state) {
          return Flex(
            direction: Axis.vertical,
            spacing: 20,
            children: [
              Flex(
                direction: Axis.horizontal,
                spacing: 13,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _modeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Mode',
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _durationController,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        final cubit = context.read<_OptionsSettingCubit>();
                        cubit.changeDuration(value);
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Duration',
                        suffix: Text('min'),
                      ),
                    ),
                  ),
                ],
              ),
              DropdownMenu(
                expandedInsets: EdgeInsets.zero,
                controller: _phonicTypeController,
                label: Text('Phonic Type'),
                onSelected: (value) {
                  final cubit = context.read<_OptionsSettingCubit>();
                  cubit.changePhonicType(value);
                },
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: PhonicType.standard,
                    label: 'Standard',
                  ),

                  DropdownMenuEntry(
                    value: PhonicType.location,
                    label: 'Location',
                  ),
                  DropdownMenuEntry(value: PhonicType.mixed, label: 'Mixed'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _updateState(_Options options) {
    _modeController.text = options.modeId;
    _durationController.text = options.durationInMinutes.toString();
    _durationController.selection = TextSelection.fromPosition(
      TextPosition(offset: _durationController.text.length),
    );
    _phonicTypeController.text = _parsePhonicType(options.phonicType);
  }

  String _parsePhonicType(PhonicType phonicType) {
    switch (phonicType) {
      case PhonicType.standard:
        return 'Standard';
      case PhonicType.location:
        return 'Location';
      case PhonicType.mixed:
        return 'Mixed';
    }
  }

  @override
  void dispose() {
    _modeController.dispose();
    _durationController.dispose();
    _phonicTypeController.dispose();
    super.dispose();
  }
}
