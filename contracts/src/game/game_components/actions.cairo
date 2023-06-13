#[derive(Drop)]
enum Action {
    MoveUp: (),
    Static: (),
    MoveDown: ()
}

#[derive(Drop)]
struct TurnAction {
    turn: u32,
    player_number: u8,
    action: Action
}

