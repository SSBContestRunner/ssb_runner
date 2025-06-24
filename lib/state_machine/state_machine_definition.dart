import 'package:ssb_contest_runner/state_machine/state_machine.dart';

class StateMachineBuilder<S, E, Side> {
  S? _initialState;

  List<TransitionListener<S, E, Side>> _transitionListeners = [];

  final stateTransitionDefinitionMap =
      <
        Type,
        Map<Type, TransitionDefinition<S, Side> Function(S state, E event)>
      >{};

  void initialState(S state) {
    this._initialState = state;
  }

  void state(
    Type state,
    void Function(
      EventTransitionDefinition<S, E, Side> eventTransitionDefinition,
    )
    definitionBlock,
  ) {
    final eventTransitionDefinition = EventTransitionDefinition<S, E, Side>();

    definitionBlock(eventTransitionDefinition);

    final eventTransitionDefinitionMap =
        eventTransitionDefinition._definitionMap;

    stateTransitionDefinitionMap[state] = eventTransitionDefinitionMap;
  }

  StateMachine<S, E, Side> build() {
    final initialStateVal = _initialState;

    if (_initialState == null) {
      throw Exception('No initial state specified');
    }
    return StateMachine<S, E, Side>(
      initialState: initialStateVal as S,
      stateDefinitionMap: stateTransitionDefinitionMap,
      transitionListeners: _transitionListeners,
    );
  }
}

class EventTransitionDefinition<S, E, Side> {
  final _definitionMap =
      <Type, TransitionDefinition<S, Side> Function(S state, E event)>{};

  void on(
    Type event,
    TransitionDefinition<S, Side> Function(S state, E event)
    transitionDefinitionBlock,
  ) {
    _definitionMap[event] = transitionDefinitionBlock;
  }

  TransitionDefinition<S, Side> transitionTo(S toState, [Side? side]) {
    return TransitionDefinition<S, Side>(toState, side);
  }
}

class TransitionDefinition<S, Side> {
  TransitionDefinition(this.toState, this.side);
  final S toState;
  final Side? side;
}

abstract interface class TransitionListener<S, E, Side> {
  void onTransition(Transition<S, E> transition);
}
