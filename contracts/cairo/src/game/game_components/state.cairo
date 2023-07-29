use hash::LegacyHash;
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::{ContractAddress, StorageAccess, StorageBaseAddress, SyscallResult};
use stark_pong::game::{WINNING_SCORE, limits_check, state_transition};
use stark_pong::game::game_components::objects::{Ball, Paddle};
use stark_pong::game::game_components::actions::TurnAction;
use stark_pong::utils::signature::{Signature};
use ecdsa::check_ecdsa_signature;

const POW_2_64: u128 = 18446744073709551616;
const POW_2_72: u128 = 4722366482869645213696;

//***********************************************************//
//                         GAMESTATE
//***********************************************************//

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct GameState {
    turn: u64,
    score_0: u8,
    score_1: u8,
    paddle_0: Paddle,
    paddle_1: Paddle,
    ball: Ball
}

trait GameStateTrait {
    fn hash(self: @GameState) -> felt252;
    fn is_valid(self: @GameState, previous_state: @GameState) -> bool;
    fn winner(self: @GameState) -> Option<u8>;
    fn apply_turn(self: @GameState, turn: TurnAction, seed: u64) -> GameState;
    fn calculate_optimal_predictable_result(self: @GameState) -> GameState;
}

impl HashGameStateImpl of GameStateTrait {
    fn hash(self: @GameState) -> felt252 {
        let game_state = *self;

        //Turn and scores
        let turn_value_252: felt252 = game_state.turn.into();
        let score_0_value_252: felt252 = game_state.score_0.into();
        let score_1_value_252: felt252 = game_state.score_1.into();

        let turn_value: u128 = turn_value_252.try_into().unwrap();
        let score_0_value: u128 = score_0_value_252.try_into().unwrap() * POW_2_64;
        let score_1_value: u128 = score_1_value_252.try_into().unwrap() * POW_2_72;
        let first_felt: felt252 = (turn_value + score_0_value + score_1_value).into();

        //Other felts
        let second_felt: felt252 = game_state.paddle_0.into();
        let third_felt: felt252 = game_state.paddle_1.into();
        let fourth_felt: felt252 = game_state.ball.into();

        let first_hash: felt252 = LegacyHash::hash(first_felt, second_felt);
        let second_hash: felt252 = LegacyHash::hash(first_hash, third_felt);
        LegacyHash::hash(second_hash, fourth_felt)
    }

    fn is_valid(self: @GameState, previous_state: @GameState) -> bool {
        let new_state = *self;
        let old_state = *previous_state;

        if (new_state.turn <= old_state.turn) {
            return false;
        }

        if (new_state.score_0 > WINNING_SCORE || new_state.score_1 > WINNING_SCORE) {
            return false;
        }

        if (!limits_check(@new_state)) {
            return false;
        }

        true
    }

    fn winner(self: @GameState) -> Option<u8> {
        let game_state = *self;
        if game_state.score_0 == WINNING_SCORE {
            Option::Some(0_u8)
        } else if game_state.score_1 == WINNING_SCORE {
            Option::Some(1_u8)
        } else {
            Option::None(())
        }
    }

    fn apply_turn(self: @GameState, turn: TurnAction, seed: u64) -> GameState {
        let new_state = state_transition(self, turn.action, seed).unwrap();
        new_state
    }

    fn calculate_optimal_predictable_result(self: @GameState) -> GameState {
        let mut game_state = *self;

        //TODO: Calculate an optimal outcome for both players until the next bounce or the next score

        game_state
    }
}


//***********************************************************//
//                        CHECKPOINT
//***********************************************************//

#[derive(Drop, Copy, Serde)]
struct Checkpoint {
    state: GameState,
    signature_0: Signature,
    signature_1: Signature
}

trait CheckpointTrait {
    fn verify_signatures(self: @Checkpoint, public_key_0: ContractAddress, public_key_1: ContractAddress) -> bool;
}

impl CheckpointTraitImpl of CheckpointTrait {
    fn verify_signatures(
        self: @Checkpoint, public_key_0: ContractAddress, public_key_1: ContractAddress
    ) -> bool {
        let checkpoint = *self;
        let state_hash = checkpoint.state.hash();

        let signature_0_ok = check_ecdsa_signature(
            state_hash,
            public_key_0.into(),
            checkpoint.signature_0.r,
            checkpoint.signature_0.s
        );
        let signature_1_ok = check_ecdsa_signature(
            state_hash,
            public_key_1.into(),
            checkpoint.signature_1.r,
            checkpoint.signature_1.s
        );
        
        (signature_0_ok && signature_1_ok)
    }
}
