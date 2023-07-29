use hash::LegacyHash;
use traits::{Into, TryInto};
use starknet::ContractAddress;
use ecdsa::check_ecdsa_signature;
use stark_pong::utils::signature::{Signature};

#[derive(Drop, Copy, Serde)]
enum Action {
    MoveUp: (),
    NoMove: (),
    MoveDown: ()
}

impl IntoFelt252ActionImpl of Into<Action, felt252> {
    fn into(self: Action) -> felt252 {
        match self {
            Action::MoveUp(()) => 0,
            Action::NoMove(()) => 1,
            Action::MoveDown(()) => 2,
        }
    }
}

impl TryIntoActionFelt252Impl of TryInto<felt252, Action> {
    fn try_into(self: felt252) -> Option<Action> {
        if (self == 0) {
            return Option::Some(Action::MoveUp(()));
        } else if (self == 1) {
            return Option::Some(Action::MoveDown(()));
        } else if (self == 2) {
            return Option::Some(Action::NoMove(()));
        } else {
            return Option::None(());
        }
    }
}

#[derive(Drop, Copy, Serde)]
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

        check_ecdsa_signature(turn_action_hash, player_public_key.into(), turn_action.signature.r, turn_action.signature.s)
    }
}
