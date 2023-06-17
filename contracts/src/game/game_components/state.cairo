use serde::Serde;
use hash::LegacyHash;
use result::{ResultTrait};
use traits::{Into, TryInto};
use option::{Option, OptionTrait};
use starknet::{ContractAddress, StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};
use stark_pong::game::game_components::objects::{
    Ball, IntoFelt252BallImpl, IntoBallFelt252Impl, Paddle, IntoFelt252PaddleImpl,
    IntoPaddleFelt252Impl
};
use stark_pong::game::game_components::actions::{TurnAction};
use stark_pong::game::{limits_check};
use stark_pong::utils::signature::{Signature};
use ecdsa::check_ecdsa_signature;

const POW_2_64: u128 = 18446744073709551616;
const POW_2_72: u128 = 4722366482869645213696;

const WINNING_SCORE: u8 = 3;

//***********************************************************//
//                         GAMESTATE
//***********************************************************//

#[derive(Drop, Copy, Serde)]
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
    fn apply_turn(self: @GameState, turn: TurnAction) -> GameState;
    fn calculate_optimal_predictable_result(self: @GameState) -> GameState;
}

impl StorageAccessGameStateImpl of StorageAccess<GameState> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: GameState) -> SyscallResult<()> {
        //Turn and scores
        let turn_value: u128 = value.turn.into();
        let score_0_value: u128 = value.score_0.into() * POW_2_64;
        let score_1_value: u128 = value.score_1.into() * POW_2_72;
        let first_felt: felt252 = (turn_value + score_0_value + score_1_value).into();

        //Other felts
        let second_felt: felt252 = value.paddle_0.into();
        let third_felt: felt252 = value.paddle_1.into();
        let fourth_felt: felt252 = value.ball.into();

        //Stored value
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8), first_felt
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), second_felt
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), third_felt
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8), fourth_felt
        );

        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<GameState> {
        let first_felt: u128 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 0_u8)
        )?
            .try_into()
            .unwrap();
        let second_felt: felt252 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8)
        )?;
        let third_felt: felt252 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8)
        )?;
        let fourth_felt: felt252 = storage_read_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8)
        )?;

        //Values
        let turn_value: u128 = (first_felt
            & 0b1111111111111111111111111111111111111111111111111111111111111111);
        let score_0_value: u128 = (first_felt
            & 0b111111110000000000000000000000000000000000000000000000000000000000000000)
            / POW_2_64;
        let score_1_value: u128 = (first_felt
            & 0b11111111000000000000000000000000000000000000000000000000000000000000000000000000)
            / POW_2_72;

        Result::Ok(
            GameState {
                turn: turn_value.try_into().unwrap(),
                score_0: score_0_value.try_into().unwrap(),
                score_1: score_1_value.try_into().unwrap(),
                paddle_0: second_felt.into(),
                paddle_1: third_felt.into(),
                ball: fourth_felt.into()
            }
        )
    }
}

impl HashGameStateImpl of GameStateTrait {
    fn hash(self: @GameState) -> felt252 {
        let game_state = *self;

        //Turn and scores
        let turn_value: u128 = game_state.turn.into();
        let score_0_value: u128 = game_state.score_0.into() * POW_2_64;
        let score_1_value: u128 = game_state.score_1.into() * POW_2_72;
        let first_felt: felt252 = (turn_value + score_0_value + score_1_value).into();

        //Other felts
        let second_felt: felt252 = game_state.paddle_0.into();
        let third_felt: felt252 = game_state.paddle_1.into();
        let fourth_felt: felt252 = game_state.ball.into();

        let first_hash: felt252 = LegacyHash::hash(first_felt, second_felt);
        let second_hash: felt252 = LegacyHash::hash(first_hash, third_felt);
        let final_hash: felt252 = LegacyHash::hash(second_hash, fourth_felt);

        final_hash
    }

    fn is_valid(self: @GameState, previous_state: @GameState) -> bool {
        let new_state = *self;
        let old_state = *previous_state;

        if (new_state.turn <= old_state.turn) {
            return false;
        }

        if (new_state.score_0 > WINNING_SCORE | new_state.score_1 > WINNING_SCORE) {
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

    fn apply_turn(self: @GameState, turn: TurnAction) -> GameState {
        let mut game_state = *self;
        game_state
    }

    fn calculate_optimal_predictable_result(self: @GameState) -> GameState {
        let mut game_state = *self;
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

        (signature_0_ok & signature_1_ok)
    }
}
