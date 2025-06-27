import 'package:equatable/equatable.dart';

class DxccPrefix extends Equatable {
  final String call;
  final int dxccId;
  final String continent;

  const DxccPrefix({required this.call, required this.dxccId, required this.continent});

  @override
  List<Object?> get props => [call, dxccId, continent];
}
