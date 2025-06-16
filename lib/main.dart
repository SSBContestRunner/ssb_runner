import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_contest_runner/main_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Initialize the player.
  await SoLoud.instance.init(channels: Channels.mono);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  HomePage({super.key});

  static final _regExp = RegExp(r'[a-zA-Z0-9/]');

  final _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home Page')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(96.0),
          child: BlocProvider(
            create: (context) => HomeCubit(),
            child: BlocBuilder<HomeCubit, bool>(
              builder: (context, isButtonEnabled) {
                return Column(
                  children: [
                    TextField(
                      controller: _textController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(_regExp),
                      ],
                      onChanged: (value) {
                        final upperCased = value.toUpperCase();
                        _textController.value = _textController.value.copyWith(
                          text: upperCased,
                        );
                        context.read<HomeCubit>().onTextChange(
                          upperCased,
                        );
                      },
                    ),
                    SizedBox(height: 30.0),
                    ElevatedButton(
                      onPressed: isButtonEnabled
                          ? () {
                              context.read<HomeCubit>().play(
                                _textController.value.text,
                              );
                            }
                          : null,
                      child: Text('播放'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
