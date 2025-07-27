import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/common/constants.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:toastification/toastification.dart';

class _Options {
  final String modeId;
  final int durationInMinutes;

  _Options({required this.modeId, required this.durationInMinutes});

  _Options copyWith({String? modeId, int? durationInMinutes}) {
    return _Options(
      modeId: modeId ?? this.modeId,
      durationInMinutes: durationInMinutes ?? this.durationInMinutes,
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
}

class OptionsSetting extends StatelessWidget {
  final _modeController = TextEditingController();
  final _durationController = TextEditingController();

  OptionsSetting({super.key});

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
              TextField(
                controller: _modeController,
                readOnly: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Mode',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
              ),
              TextField(
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
  }
}
