use serde::Serde;
use hash::LegacyHash;
use array::{ArrayTrait, SpanTrait};
use option::OptionTrait;
use traits::{Into, TryInto};
use starknet::ContractAddress;
//use ecdsa::check_ecdsa_signature;
use result::{ResultTrait, ResultTraitImpl};
use stark_pong::utils::signature::{Signature};
use stark_pong::utils::signature_verification::external_verify;

#[derive(Drop, Serde, Copy)]
enum Action {
    MoveUp: (),
    Static: (),
    MoveDown: ()
}

impl IntoFelt252ActionImpl of Into<Action, felt252> {
    fn into(self: Action) -> felt252 {
        match self {
            Action::MoveUp(()) => 0,
            Action::Static(()) => 1,
            Action::MoveDown(()) => 2,
        }
    }
}

impl IntoActionFelt252Impl of Into<felt252, Action> {
    fn into(self: felt252) -> Action {
        if (self == 0) {
            return Action::MoveUp(());
        } else if (self == 2) {
            return Action::MoveDown(());
        }
        Action::Static(())
    }
}

#[derive(Serde, Drop, Copy)]
struct TurnAction {
    turn: u64,
    action: Action,
    signature: Signature
}

trait TurnActionTrait {
    fn verify_signature(self: @TurnAction, player_public_key: ContractAddress) -> bool;
}

impl TurnActionTraitImpl of TurnActionTrait {
    fn verify_signature(self: @TurnAction, player_public_key: ContractAddress) -> bool {
        let turn_action = *self;
        let action: felt252 = turn_action.action.into();
        let turn_action_hash = LegacyHash::hash(turn_action.turn.into(), action);

        //EXPERIMENTAL: check_ecdsa_signature(turn_action_hash, player_public_key.into(), turn_action.signature.r, turn_action.signature.s)
        external_verify(turn_action_hash, player_public_key, turn_action.signature);
        
        true
    }
}
