import 'package:flutter_bloc/flutter_bloc.dart';

class MainPageCubit extends Cubit<bool> {
  MainPageCubit() : super(false);

  void showKeyTips() {
    emit(true);
  }

  void hideKeyTips() {
    emit(false);
  }
}
