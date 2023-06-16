use stark_pong::game::game_components::actions::TurnActionTrait;
use core::zeroable::Zeroable;
use starknet::ContractAddress;

#[abi]
trait IGameRoom {
    #[view]
    fn is_active() -> bool;
}

#[contract]
mod GameRoom {
    use super::IGameRoom;
    use option::OptionTrait;
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use array::{ArrayTrait, SpanTrait};
    use ecdsa::check_ecdsa_signature;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
    use stark_pong::utils::game_room_status::{GameRoomStatus, StorageAccessGameRoomStatusImpl};
    use stark_pong::utils::signature::{Signature};
    use stark_pong::game::{initial_game_state};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::state::{GameState, GameStateTrait};
    use stark_pong::game::game_components::actions::{TurnAction, TurnActionTrait};
    use stark_pong::game_room_factory::{
        IGameRoomFactoryDispatcher, IGameRoomFactoryDispatcherTrait
    };
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};

    struct Storage {
        _factory_address: ContractAddress,
        _players: LegacyMap<u8, Player>,
        _status: GameRoomStatus,
        _deadline: u64,
        _wager: u256,
        _fee: u128,
        _state: GameState
    }

    impl GameRoomImpl of IGameRoom {
        #[view]
        fn is_active() -> bool {
            let block_timestamp = get_block_timestamp();
            let deadline = _deadline::read();
            let before_deadlie = (block_timestamp <= deadline);

            match _status::read() {
                GameRoomStatus::WaitingForPlayers(()) => before_deadlie,
                GameRoomStatus::InProgress(()) => before_deadlie,
                GameRoomStatus::Finished(()) => false,
                GameRoomStatus::Disputed(()) => before_deadlie,
                GameRoomStatus::Closed(()) => false
            }
        }
    }

    #[constructor]
    fn constructor(
        factory_address: ContractAddress,
        player_address: ContractAddress,
        offchain_public_key: ContractAddress,
        wager: u256,
        fee: u128
    ) {
        _set_deadline(30_u64);

        _factory_address::write(factory_address);
        _status::write(GameRoomStatus::WaitingForPlayers(()));
        _wager::write(wager);
        _fee::write(fee);

        let block_timestamp = get_block_timestamp();
        let player_number: u8 = (block_timestamp % 2_u64).try_into().unwrap();

        _players::write(
            player_number,
            Player { address: player_address, offchain_public_key: offchain_public_key }
        );
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    fn GameStarted() {}

    #[event]
    fn GameStateUpdated(state: GameState) {}

    #[event]
    fn GameFinished() {}

    #[event]
    fn PartialExit() {}

    #[event]
    fn PartialGameFinished() {}

    #[event]
    fn GameRoomClosed() {}

    //***********************************************************//
    //                      VIEW FUNCTIONS
    //***********************************************************//

    #[view]
    fn status() -> (GameRoomStatus, u64) {
        (_status::read(), _deadline::read())
    }

    #[view]
    fn game_state() -> GameState {
        _state::read()
    }

    #[view]
    fn players() -> (Player, Player) {
        (_players::read(0_u8), _players::read(1_u8))
    }

    #[view]
    fn wager() -> u256 {
        _wager::read()
    }

    //***********************************************************//
    //         JOIN & EXIT GAME ROOM EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn join_game_room(offchain_public_key: ContractAddress) {
        assert_deadline();
        assert_status(GameRoomStatus::WaitingForPlayers(()));

        let player_address = get_caller_address();

        let mut other_player_number = 0_u8;
        if (_players::read(0_u8).address.is_zero()) {
            other_player_number = 1_u8;
        }
        assert(player_address != _players::read(other_player_number).address, 'SAME_PLAYER');

        _send_wager_to_game_room(player_address);

        let player_number: u8 = if (other_player_number == 0_u8) {
            1_u8
        } else {
            0_u8
        };
        _players::write(
            player_number,
            Player { address: player_address, offchain_public_key: offchain_public_key }
        );

        _start_game();
    }

    #[external]
    fn close_game_room() {
        assert_deadline();
        assert_status(GameRoomStatus::WaitingForPlayers(()));
        assert_player(0_u8);

        _refund_wagers();
        _status::write(GameRoomStatus::Closed(()));
    }

    //***********************************************************//
    //               GAME STATE EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn set_game_state(new_game_state: GameState, signature_0: Signature, signature_1: Signature) {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));

        _update_game_state(new_game_state, signature_0, signature_1);

        match new_game_state.winner() {
            Option::Some(winner) => {
                _finish_game();
            },
            Option::None(()) => {}
        };
    }

    #[external]
    fn advance_game_state(mut turns: Array<TurnAction>) {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));

        let mut processed_turns: usize = 0;
        let mut new_game_state = _state::read();
        loop {
            match turns.pop_front() {
                Option::Some(turn_action) => {
                    let next_turn = new_game_state.turn + 1;
                    assert(turn_action.turn <= next_turn, 'NON_CONSECUTIVE_TURN');

                    if (turn_action.turn == next_turn) {
                        let player_number = _player_number_from_turn(next_turn);
                        let player = _players::read(player_number);

                        assert(
                            turn_action.verify_signature(player.offchain_public_key),
                            'INVALID_SIGNATURE'
                        );

                        new_game_state = new_game_state.apply_turn(turn_action);

                        if (new_game_state.winner().is_some()) {
                            break ();
                        }
                    }
                },
                Option::None(_) => {
                    break ();
                }
            };
        };

        _state::write(new_game_state);
        GameStateUpdated(new_game_state);

        match new_game_state.winner() {
            Option::Some(winner) => {
                _finish_game();
            },
            Option::None(()) => {}
        };
    }

    #[external]
    fn exit_with_partial_result() {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));
    }

    #[external]
    fn dispute_partial_result() {
        assert_deadline();
        assert_status(GameRoomStatus::Disputed(()));
    }

    #[external]
    fn confirm_partial_result() {
        assert_deadline();
        assert_status(GameRoomStatus::Disputed(()));
    }

    //***********************************************************//
    //              GAME STATUS INTERNAL FUNCTIONS
    //***********************************************************//

    fn _start_game() {
        _status::write(GameRoomStatus::InProgress(()));
        _set_deadline(60_u64);
        _state::write(initial_game_state());
        GameStarted();
    }

    fn _update_game_state(
        new_game_state: GameState, signature_0: Signature, signature_1: Signature
    ) {
        let new_game_state_hash = new_game_state.hash();
        let player_0 = _players::read(0_u8);
        let player_1 = _players::read(1_u8);

        assert(new_game_state.is_valid(@_state::read()), 'INVALID_GAME_STATE');
        assert(
            check_ecdsa_signature(
                new_game_state_hash,
                player_0.offchain_public_key.into(),
                signature_0.r,
                signature_0.s
            ),
            'INVALID_SIGNATURE_0'
        );
        assert(
            check_ecdsa_signature(
                new_game_state_hash,
                player_1.offchain_public_key.into(),
                signature_1.r,
                signature_1.s
            ),
            'INVALID_SIGNATURE_1'
        );

        _state::write(new_game_state);
        GameStateUpdated(new_game_state);
    }

    fn _player_number_from_turn(turn: u64) -> u8 {
        let rem = turn % 2_u64;
        rem.try_into().unwrap()
    }

    fn _finish_game() {
        let game_state = _state::read();
        let winner = game_state.winner().unwrap();
        _pay_prize_and_fees(winner);
        _status::write(GameRoomStatus::Finished(()));
        GameFinished();
    }

    fn _calculate_optimal_result() {}

    //***********************************************************//
    //                 UTILS INTERNAL FUNCTIONS                 
    //***********************************************************//

    fn assert_player(player_number: u8) {
        let player_address = get_caller_address();
        let player = _players::read(player_number);
        assert(player_address == player.address, 'INVALID_PLAYER');
    }

    fn assert_status(status: GameRoomStatus) {
        let current_status = _status::read();
        assert(current_status == status, 'INVALID_STATUS');
    }

    fn assert_deadline() {
        let block_timestamp = get_block_timestamp();
        let deadline = _deadline::read();
        assert(block_timestamp <= deadline, 'DEADLINE');
    }

    fn _set_deadline(minutes: u64) {
        let block_timestamp = get_block_timestamp();
        let deadline = block_timestamp + (minutes * 60_u64 * 1000_u64);
        _deadline::write(deadline);
    }

    fn _send_wager_to_game_room(player_address: ContractAddress) {
        let wager = _wager::read();
        if (wager > 0_u256) {
            let contract_address = get_contract_address();
            let factory = IGameRoomFactoryDispatcher { contract_address: _factory_address::read() };
            let game_token_address = factory.game_token();
            let game_token = IERC20Dispatcher { contract_address: game_token_address };
            assert(
                game_token.transfer_from(player_address, contract_address, wager),
                'WAGER_TRANSFER_FAILED'
            );
        }
    }

    fn _refund_wagers() {
        let contract_address = get_contract_address();
        let factory = IGameRoomFactoryDispatcher { contract_address: _factory_address::read() };
        let game_token_address = factory.game_token();
        let game_token = IERC20Dispatcher { contract_address: game_token_address };

        let player_0 = _players::read(0_u8);
        let player_1 = _players::read(1_u8);
        let total_balance = game_token.balance_of(contract_address);

        if (player_1.address.is_zero() | player_0.address.is_zero()) {
            let creator_address = if (player_0.address.is_zero()) { player_1.address } else { player_0.address };
            assert(game_token.transfer(creator_address, total_balance), 'REFUND_FAILED');
        } else {
            let balance_for_each = total_balance / 2_u256;
            assert(game_token.transfer(player_0.address, balance_for_each), 'REFUND_FAILED');
            assert(game_token.transfer(player_1.address, balance_for_each), 'REFUND_FAILED');
        }
    }

    fn _pay_prize_and_fees(player_number: u8) {
        if (_wager::read() > 0_u256) {
            let contract_address = get_contract_address();
            let factory_address = _factory_address::read();
            let factory = IGameRoomFactoryDispatcher { contract_address: factory_address };
            let game_token_address = factory.game_token();
            let game_token = IERC20Dispatcher { contract_address: game_token_address };

            let winner = _players::read(player_number);
            let total_balance = game_token.balance_of(contract_address);

            let fee: felt252 = _fee::read().into();
            let fees_to_factory_contract: u256 = (total_balance / 10000_u256) * fee.into();
            let payment_to_winner: u256 = total_balance - fees_to_factory_contract;

            assert(game_token.transfer(winner.address, payment_to_winner), 'PRIZE_TRANSFER_FAILED');
            assert(game_token.transfer(factory_address, fees_to_factory_contract), 'FEE_PAYMENT_FAILED');
        }
    }
}
