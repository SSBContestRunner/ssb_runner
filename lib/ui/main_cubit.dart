import 'package:flutter_bloc/flutter_bloc.dart';

class MainCubit extends Cubit<bool> {
  MainCubit() : super(false);

  void showKeyTips() {
    emit(true);
  }

  void hideKeyTips() {
    emit(false);
  }
}
