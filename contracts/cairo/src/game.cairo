mod game_components;

use hash::LegacyHash;
use array::ArrayTrait;
use result::ResultTrait;
use option::{Option, OptionTrait};
use traits::{Into, TryInto};
use game_components::objects::{Paddle, Ball};
use game_components::state::GameState;
use stark_pong::game::game_components::actions::{Action};

const MAX_Y: u16 = 12000_u16;
const MAX_X: u16 = 16000_u16;
const MAX_BALL_SPEED: u16 = 100_u16;
const PADDLE_SPEED: u16 = 100_u16;
const PADDLE_HEIGHT: u16 = 400_u16;
const WINNING_SCORE: u8 = 3;

fn initial_game_state(seed: u64) -> GameState {
    let (speed_x, speed_y, moving_up, moving_left) = randomize_ball(seed, 0_u64);

    GameState {
        turn: 0_u64, score_0: 0_u8, score_1: 0_u8, paddle_0: Paddle {
            y: 6000_u16, size: 2000_u16, speed: 0_u16, moving_up: true
            }, paddle_1: Paddle {
            y: 6000_u16, size: 2000_u16, speed: 0_u16, moving_up: true
            }, ball: Ball {
            x: MAX_X / 2_u16,
            y: MAX_Y / 2_u16,
            size: 400_u16,
            speed_x: speed_x,
            speed_y: speed_y,
            moving_up: moving_up,
            moving_left: moving_left
        }
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

fn randomize_ball(seed: u64, turn: u64) -> (u16, u16, bool, bool) {
    let BASE_SPEED: u16 = 30_u16;

    //let seed_252: felt252 = seed.into();
    //let turn_252: felt252 = turn.into();    
    //let hash_of_turn: felt252 = LegacyHash::hash(turn_252, seed_252);
    //let hash_of_random_x = LegacyHash::hash(hash_of_turn, 0);
    //let hash_of_random_y = LegacyHash::hash(hash_of_turn, 1);
    //let hash_of_random_left = LegacyHash::hash(hash_of_turn, 2);
    //let hash_of_random_up = LegacyHash::hash(hash_of_turn, 3);

    // CANNOT IMPLEMENT RANDOMIZING ALGORITHM WITHOUT downcasting, div mod, etc
    // SIMPLY USE TURN NUMNER INSTEAD AND BASE SPEED FOR NOW

    let moving_up: bool = (turn % 2_u64) == 0_u64;

    (BASE_SPEED, BASE_SPEED, moving_up, false) //moving_left, moving_up)
}

fn state_transition(state: @GameState, action: Action, seed: u64) -> Option<GameState> {
    let mut new_state = *state;

    //Check if there's already a winner
    if (new_state.score_0 >= WINNING_SCORE || new_state.score_1 >= WINNING_SCORE) {
        return Option::None(());
    }

    //Get the player number for the action
    let player_number = player_number_from_turn(new_state.turn);
    if (player_number == 0) {
        //Calculate the new speed and direction
        match action {
            Action::MoveUp(()) => {
                new_state.paddle_0.moving_up = true;
                new_state.paddle_0.speed = PADDLE_SPEED;
            },
            Action::NoMove(()) => {
                new_state.paddle_0.speed = 0_u16;
            },
            Action::MoveDown(()) => {
                new_state.paddle_0.moving_up = false;
                new_state.paddle_0.speed = PADDLE_SPEED;
            }
        };

        //Now, calculate the new position
        if (new_state.paddle_0.speed > 0) {
            if (new_state.paddle_0.moving_up) {
                let MIN_VALUE: u16 = new_state.paddle_0.size / 2_u16;
                if (new_state.paddle_0.speed > (new_state.paddle_0.y - MIN_VALUE)) {
                    new_state.paddle_0.y = MIN_VALUE;
                } else {
                    new_state.paddle_0.y = (new_state.paddle_0.y - new_state.paddle_0.speed);
                }
            } else {
                let MAX_VALUE: u16 = MAX_Y - (new_state.paddle_0.size / 2_u16);
                new_state.paddle_0.y = new_state.paddle_0.y + new_state.paddle_0.speed;
                if (new_state.paddle_0.y > MAX_VALUE) {
                    new_state.paddle_0.y = MAX_VALUE;
                }
            }
        }
    } else {
        //Calculate the new speed and direction
        match action {
            Action::MoveUp(()) => {
                new_state.paddle_1.moving_up = true;
                new_state.paddle_1.speed = PADDLE_SPEED;
            },
            Action::NoMove(()) => {
                new_state.paddle_1.speed = 0_u16;
            },
            Action::MoveDown(()) => {
                new_state.paddle_1.moving_up = false;
                new_state.paddle_1.speed = PADDLE_SPEED;
            }
        };

        //Now, calculate the new position
        if (new_state.paddle_1.speed > 0) {
            if (new_state.paddle_1.moving_up) {
                let MIN_VALUE: u16 = new_state.paddle_1.size / 2_u16;
                if (new_state.paddle_1.speed > (new_state.paddle_1.y - MIN_VALUE)) {
                    new_state.paddle_1.y = MIN_VALUE;
                } else {
                    new_state.paddle_1.y = (new_state.paddle_1.y - new_state.paddle_1.speed);
                }
            } else {
                let MAX_VALUE: u16 = MAX_Y - (new_state.paddle_1.size / 2_u16);
                new_state.paddle_1.y = new_state.paddle_1.y + new_state.paddle_1.speed;
                if (new_state.paddle_1.y > MAX_VALUE) {
                    new_state.paddle_1.y = MAX_VALUE;
                }
            }
        }
    }

    //Calculate the ball position
    if (new_state.ball.moving_up) {
        let MIN_VALUE = new_state.ball.size / 2_u16;
        let distance = new_state.ball.y - MIN_VALUE;
        if (new_state.ball.speed_y >= distance) {
            new_state.ball.y = new_state.ball.speed_y - distance;
            new_state.ball.moving_up = false;
        } else {
            new_state.ball.y = new_state.ball.y - new_state.ball.speed_y;
        }
    } else {
        let MAX_VALUE = MAX_Y - (new_state.ball.size / 2_u16);
        let distance = MAX_VALUE - new_state.ball.y;
        if (new_state.ball.speed_y >= distance) {
            new_state.ball.y = MAX_VALUE - (new_state.ball.speed_y - distance);
            new_state.ball.moving_up = true;
        } else {
            new_state.ball.y = new_state.ball.y + new_state.ball.speed_y;
        }
    }

    let mut has_scored_0 = false;
    let mut has_scored_1 = false;
    let ball_lower_limit = new_state.ball.y + (new_state.ball.size / 2_u16);
    let ball_upper_limit = new_state.ball.y - (new_state.ball.size / 2_u16);
    let paddle_0_lower_limit = new_state.paddle_0.y + (new_state.paddle_0.size / 2_u16);
    let paddle_0_upper_limit = new_state.paddle_0.y - (new_state.paddle_0.size / 2_u16);
    let paddle_1_lower_limit = new_state.paddle_0.y + (new_state.paddle_1.size / 2_u16);
    let paddle_1_upper_limit = new_state.paddle_0.y - (new_state.paddle_1.size / 2_u16);

    if (new_state.ball.moving_left) {
        let will_bounce = (ball_lower_limit >= paddle_0_upper_limit)
            & (ball_upper_limit <= paddle_0_lower_limit);

        let MIN_VALUE = PADDLE_HEIGHT + (new_state.ball.size / 2_u16);
        if (new_state.ball.x < MIN_VALUE) {
            //The ball has already crossed the paddle limit and will score the goal on time
            if (new_state.ball.speed_x >= new_state.ball.x) {
                //The ball reaches the screen limit in this turn. Change score
                new_state.score_1 = new_state.score_1 + 1_u8;
                has_scored_1 = true;
            } else {
                //Continue moving the ball
                new_state.ball.x = new_state.ball.x - new_state.ball.speed_x;
            }
        } else {
            let distance = new_state.ball.x - MIN_VALUE;

            if (new_state.ball.speed_x >= new_state.ball.x) {
                //The ball will reach the screen limit in this turn, but it can still bounce
                if (will_bounce) {
                    new_state.ball.x = MIN_VALUE + new_state.ball.speed_x - distance;
                    new_state.ball.moving_left = false;

                    //Calculate the new speed and direction
                    let mut hit_distance = 0_u16;
                    if (new_state.ball.y > new_state.paddle_0.y) {
                        new_state.ball.moving_up = false;
                        hit_distance = new_state.ball.y - new_state.paddle_0.y;
                    } else {
                        new_state.ball.moving_up = true;
                        hit_distance = new_state.paddle_0.y - new_state.ball.y;
                    }

                    let hit_percentage = 50_u16
                        + ((hit_distance * 50_u16) / (new_state.paddle_0.size / 2_u16));
                    new_state.ball.speed_y = (hit_percentage * MAX_BALL_SPEED) / 100_u16;
                } else {
                    //The ball will not bounce, so the ball will reach 0. Change score.
                    new_state.score_1 = new_state.score_1 + 1_u8;
                    has_scored_1 = true;
                }
            } else {
                if ((new_state.ball.x - new_state.ball.speed_x) < MIN_VALUE) {
                    //The ball will cross the paddle limit in this turn, but it can still bounce
                    if (will_bounce) {
                        new_state.ball.x = MIN_VALUE + new_state.ball.speed_x - distance;
                        new_state.ball.moving_left = false;

                        //Calculate the new speed and direction
                        let mut hit_distance = 0_u16;
                        if (new_state.ball.y > new_state.paddle_0.y) {
                            new_state.ball.moving_up = false;
                            hit_distance = new_state.ball.y - new_state.paddle_0.y;
                        } else {
                            new_state.ball.moving_up = true;
                            hit_distance = new_state.paddle_0.y - new_state.ball.y;
                        }

                        let hit_percentage = 50_u16
                            + ((hit_distance * 50_u16) / (new_state.paddle_0.size / 2_u16));
                        new_state.ball.speed_y = (hit_percentage * MAX_BALL_SPEED) / 100_u16;
                    } else {
                        //The ball will not bounce, but won't reach 0 yet. Continue moving.
                        new_state.ball.x = new_state.ball.x - new_state.ball.speed_x;
                    }
                } else {
                    //The ball will not cross the paddle limit in this turn, so we can just move it
                    new_state.ball.x = new_state.ball.x - new_state.ball.speed_x;
                }
            }
        }
    } else {
        let will_bounce = (ball_lower_limit >= paddle_1_upper_limit)
            & (ball_upper_limit <= paddle_1_lower_limit);

        let MAX_VALUE = MAX_X - PADDLE_HEIGHT - (new_state.ball.size / 2_u16);
        if (new_state.ball.x > MAX_VALUE) {
            //The ball has already crossed the paddle limit and will score the goal on time
            if (new_state.ball.speed_x >= (MAX_X - new_state.ball.x)) {
                //The ball reach the screen limit in this turn. Change score
                new_state.score_0 = (new_state.score_0 + 1_u8);
                has_scored_0 = true;
            } else {
                //Continue moving the ball
                new_state.ball.x = new_state.ball.x + new_state.ball.speed_x;
            }
        } else {
            let distance = MAX_VALUE - new_state.ball.x;

            if (new_state.ball.speed_x >= (MAX_X - new_state.ball.x)) {
                //The ball will reach the screen limit in this turn, but it can still bounce
                if (will_bounce) {
                    new_state.ball.x = MAX_VALUE - (new_state.ball.speed_x - distance);
                    new_state.ball.moving_left = true;

                    //Calculate the new speed and direction
                    let mut hit_distance = 0_u16;
                    if (new_state.ball.y > new_state.paddle_1.y) {
                        new_state.ball.moving_up = true;
                        hit_distance = new_state.ball.y - new_state.paddle_1.y;
                    } else {
                        new_state.ball.moving_up = false;
                        hit_distance = new_state.paddle_1.y - new_state.ball.y;
                    }

                    let hit_percentage = 50_u16
                        + ((hit_distance * 50_u16) / (new_state.paddle_1.size / 2_u16));
                    new_state.ball.speed_y = (hit_percentage * MAX_BALL_SPEED) / 100_u16;
                } else {
                    //The ball will not bounce, so the ball will reach 0. Change score.
                    new_state.score_0 = (new_state.score_0 + 1_u8);
                    has_scored_0 = true;
                }
            } else {
                if ((new_state.ball.x + new_state.ball.speed_x) > MAX_VALUE) {
                    //The ball will cross the paddle limit in this turn, but it can still bounce
                    if (will_bounce) {
                        new_state.ball.x = MAX_VALUE - (new_state.ball.speed_x - distance);
                        new_state.ball.moving_left = true;

                        //Calculate the new speed and direction
                        let mut hit_distance = 0_u16;
                        if (new_state.ball.y > new_state.paddle_1.y) {
                            new_state.ball.moving_up = true;
                            hit_distance = new_state.ball.y - new_state.paddle_1.y;
                        } else {
                            new_state.ball.moving_up = false;
                            hit_distance = new_state.paddle_1.y - new_state.ball.y;
                        }

                        let hit_percentage = 50_u16
                            + ((hit_distance * 50_u16) / (new_state.paddle_1.size / 2_u16));
                        new_state.ball.speed_y = (hit_percentage * MAX_BALL_SPEED) / 100_u16;
                    } else {
                        //The ball will not bounce, but won't reach 0 yet. Continue moving.
                        new_state.ball.x = new_state.ball.x + new_state.ball.speed_x;
                    }
                } else {
                    //The ball will not cross the paddle limit in this turn, so we can just move it
                    new_state.ball.x = new_state.ball.x + new_state.ball.speed_x;
                }
            }
        }
    }

    //If the game continues
    if (new_state.score_0 < WINNING_SCORE && new_state.score_1 < WINNING_SCORE) {
        //Reset the ball in case of score
        if (has_scored_0 | has_scored_1) {
            new_state.ball.x = MAX_X / 2_u16;
            new_state.ball.y = MAX_Y / 2_u16;

            let (speed_x, speed_y, moving_up, moving_left) = randomize_ball(seed, new_state.turn);

            new_state.ball.speed_x = speed_x;
            new_state.ball.speed_y = speed_y;
            new_state.ball.moving_up = moving_up;

            if (has_scored_0) {
                new_state.ball.moving_left = true;
            } else {
                new_state.ball.moving_left = false;
            }
        }
    }

    new_state.turn = (new_state.turn) + 1_u64;

    Option::Some(new_state)
}
