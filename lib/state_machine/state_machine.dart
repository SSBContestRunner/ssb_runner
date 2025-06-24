import 'package:collection/collection.dart';

class StateMachine<S, T, E, Side> {
  StateMachine({
    required S initialState,
    required List<TransitionDefinition<S, E, Side>> transitionDefinitions,
    required List<TransitionListener<S, E, Side>> transitionListeners,
  }) : currentState = initialState,
       _transitionsDefinitions = transitionDefinitions,
       _transitionListeners = transitionListeners;

  S currentState;

  final List<TransitionDefinition<S, E, Side>> _transitionsDefinitions;

  final List<TransitionListener<S, E, Side>> _transitionListeners;

  S? transition(E event) {
    final currentStateVal = currentState;

    final validTransitionDefinition = _transitionsDefinitions.firstWhereOrNull(
      (element) =>
          element.event == event.runtimeType &&
          currentStateVal.runtimeType == element.from,
    );

    if (validTransitionDefinition == null) {
      final transition = Transition(event, currentStateVal);
      for (final listener in _transitionListeners) {
        listener.onTransition(transition);
      }
      return null;
    }

    final transitionValid = validTransitionDefinition.to.call(event);
    final toState = transitionValid.to;
    currentState = toState;
    
    for (final listener in _transitionListeners) {
      listener.onTransition(transitionValid);
    }
    
    return toState;
  }
}

class Transition<S, E> {
  Transition(this.event, this.from);
  final E event;
  final S from;
}

class TransitionValid<S, E, Side> extends Transition<S, E> {
  TransitionValid(super.event, super.from, this.to, this.side);
  final S to;
  final Side side;
}

class TransitionDefinition<S, E, Side> {
  TransitionDefinition(this.event, this.from, this.to);
  final Type event;
  final Type from;
  final TransitionValid<S, E, Side> Function(E event) to;
}

abstract interface class TransitionListener<S, E, Side> {
  void onTransition(Transition<S, E> transition);
}
