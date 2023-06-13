use result::ResultTrait;
use array::ArrayTrait;

enum Action {
    MoveUp: (),
    Static: (),
    MoveDown: ()
}

struct TurnAction {
    turn: u32,
    player: u8,
    action: Action
}

struct Coordinate {
    x: u32,
    y: u32
}

struct Size {
    width: u32,
    height: u32
}

struct Speed {
    direction: Coordinate,
    sign: (bool, bool)
}

struct StarkPongObject {
    position: Coordinate,
    size: Size,
    speed: Speed
}

struct GameState {
    paddle1: StarkPongObject,
    paddle2: StarkPongObject,
    ball: StarkPongObject
}

fn advance_serialized_game_state(state: Array<felt252>, action: Array<felt252>) -> Array<felt252> {
    ArrayTrait::<felt252>::new()
}
