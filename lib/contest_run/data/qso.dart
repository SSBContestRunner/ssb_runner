import 'package:equatable/equatable.dart';

class Qso extends Equatable {
  final String call;
  final String exchange;

  const Qso({required this.call, required this.exchange});

  @override
  List<Object?> get props => [call, exchange];

  Qso copyWith({String? call, String? exchange}) {
    return Qso(call: call ?? this.call, exchange: exchange ?? this.exchange);
  }
}
