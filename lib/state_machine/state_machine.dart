part 'state_machine_definition.dart';

class StateMachine<S, E, Side> {
  factory StateMachine.create(
    void Function(StateMachineBuilder<S, E, Side>) builderBlock,
  ) {
    final builder = StateMachineBuilder<S, E, Side>();
    builderBlock(builder);
    return builder._build();
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
      listener.call(
        TransitionValid(
          event,
          currentState,
          toState,
          transitionDefinition.side,
        ),
      );
    }

    return toState;
  }

  void _notifyInvalidTransition(E event) {
    final transition = Transition<S, E, Side>(event, currentState);
    for (final listener in _transitionListeners) {
      listener.call(transition);
    }
  }

  void dispose() {
    _transitionListeners.clear();
  }
}

class Transition<S, E, Side> {
  Transition(this.event, this.from, [this.sideEffect]);
  final E event;
  final S from;
  final Side? sideEffect;
}

class TransitionValid<S, E, Side> extends Transition<S, E, Side> {
  TransitionValid(super.event, super.from, this.to, super.side);
  final S to;
}
