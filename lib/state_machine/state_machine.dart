import 'package:ssb_contest_runner/state_machine/state_machine_definition.dart';

class StateMachine<S, T, E, Side> {
  factory StateMachine.create(
    void Function(StateMachineBuilder<S, T, E, Side>) builderBlock,
  ) {
    final builder = StateMachineBuilder<S, T, E, Side>();
    builderBlock(builder);
    return builder.build();
  }

  StateMachine({
    required S initialState,
    required Map<
      Type,
      Map<Type, TransitionDefinition<S, Side> Function(S state, E event)>
    >
    stateDefinitionMap,
    required List<TransitionListener<S, E, Side>> transitionListeners,
  }) : currentState = initialState,
       _stateDefinitionMap = stateDefinitionMap,
       _transitionListeners = transitionListeners;

  S currentState;

  final Map<
    Type,
    Map<Type, TransitionDefinition<S, Side> Function(S state, E event)>
  >
  _stateDefinitionMap;

  final List<TransitionListener<S, E, Side>> _transitionListeners;

  S? transition(E event) {
    final currentStateVal = currentState;

    final eventTransitionMap = _stateDefinitionMap[currentStateVal.runtimeType];

    if (eventTransitionMap == null) {
      _notifyInvalidTransition(event);
      return null;
    }

    final transitionDefinitionBlock = eventTransitionMap[event.runtimeType];

    if (transitionDefinitionBlock == null) {
      _notifyInvalidTransition(event);
      return null;
    }

    final transitionDefinition = transitionDefinitionBlock(
      currentStateVal,
      event,
    );

    final toState = transitionDefinition.toState;
    currentState = toState;

    for (final listener in _transitionListeners) {
      listener.onTransition(TransitionValid(event, currentState, toState, transitionDefinition.side));
    }

    return toState;
  }

  void _notifyInvalidTransition(E event) {
    final transition = Transition(event, currentState);
    for (final listener in _transitionListeners) {
      listener.onTransition(transition);
    }
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
