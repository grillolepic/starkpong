mod game_components;

use array::ArrayTrait;
use result::ResultTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use game_components::objects::{Paddle, Ball};
use game_components::state::GameState;

fn initial_game_state(seed: u64) -> GameState {
    let (speed_x, speed_y, moving_up, moving_left) = randomize_ball_velocity(seed);

    GameState {
        turn: 0_u64, score_0: 0_u8, score_1: 0_u8,
        paddle_0: Paddle { y: 6000_u16, size: 2000_u16, speed: 0_u16, moving_up: true },
        paddle_1: Paddle { y: 6000_u16, size: 2000_u16, speed: 0_u16, moving_up: true },
        ball: Ball {x: 8000_u16, y: 6000_u16, size: 400_u16, speed_x: speed_x, speed_y: speed_y, moving_up: moving_up, moving_left: moving_left }
    }
}

fn player_number_from_turn(turn: u64) -> u8 {
    let rem: felt252 = (turn % 2_u64).into();
    rem.try_into().unwrap()
}

fn limits_check(game_state: @GameState) -> bool {
    let state = *game_state;
    true
}

fn randomize_ball_velocity(seed: u64) -> (u16, u16, bool, bool) {
    //(10_u16, 10_u16, false, false)
    (0_u16, 0_u16, false, false)
}

//fn advance_game_state(state: GameState, action: Action) -> GameState {}
