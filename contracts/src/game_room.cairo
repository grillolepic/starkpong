use stark_pong::game::game_components::actions::TurnActionTrait;
use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
use core::zeroable::Zeroable;
use starknet::ContractAddress;

#[abi]
trait IGameRoom {
    #[view]
    fn is_active() -> bool;

    #[view]
    fn player(number: u8) -> Player;
}

#[contract]
mod GameRoom {
    use super::IGameRoom;
    use option::OptionTrait;
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use array::{ArrayTrait, SpanTrait};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
    use stark_pong::utils::game_room_status::{GameRoomStatus, StorageAccessGameRoomStatusImpl};
    use stark_pong::utils::signature::{Signature};
    use stark_pong::game::{initial_game_state, player_number_from_turn, MAX_SCORE};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::state::{
        GameState, GameStateTrait, Checkpoint, CheckpointTrait
    };
    use stark_pong::game::game_components::actions::{TurnAction, TurnActionTrait};
    use stark_pong::game_room_factory::{
        IGameRoomFactoryDispatcher, IGameRoomFactoryDispatcherTrait
    };
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};

    struct Storage {
        _factory_address: ContractAddress,
        _players: LegacyMap<u8, Player>,
        _status: GameRoomStatus,
        _random_seed: u64,
        _deadline: u64,
        _wager: u256,
        _fee: u128,
        _state: GameState,
        _optimal_predictable_result: bool,
        _exit_player_number: u8
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
                GameRoomStatus::PartialExit(()) => before_deadlie,
                GameRoomStatus::Closed(()) => false
            }
        }

        #[view]
        fn player(number: u8) -> Player {
            _players::read(number)
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

        let random_seed = get_block_timestamp();
        _random_seed::write(random_seed);

        let seed_mod: felt252 = (random_seed % 2_u64).into();
        let player_number: u8 = seed_mod.try_into().unwrap();

        _players::write(
            player_number,
            Player { address: player_address, offchain_public_key: offchain_public_key }
        );

        let empty_address: ContractAddress = 0.try_into().unwrap();
        let empty_player = Player { address: empty_address, offchain_public_key: empty_address };
        let empty_player_number: u8 = _get_empty_player_number().unwrap();
        _players::write(empty_player_number, empty_player);

        _state::write(initial_game_state(random_seed));
        _optimal_predictable_result::write(false);
        _exit_player_number::write(0_u8);
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
    fn PartialExit(last_turn: u64) {}

    #[event]
    fn PartialResultDisputed() {}

    #[event]
    fn PartialGameFinished() {}

    #[event]
    fn GameRoomClosed() {}

    //***********************************************************//
    //                      VIEW FUNCTIONS
    //***********************************************************//

    #[view]
    fn is_active() -> bool {
        IGameRoom::is_active()
    }

    #[view]
    fn status() -> (GameRoomStatus, u64) {
        (_status::read(), _deadline::read())
    }

    #[view]
    fn game_state() -> (u64, u8, u8) {
        let state = _state::read();
        (state.turn, state.score_0, state.score_1)
    }

    #[view]
    fn ball() -> Ball {
        let state = _state::read();
        state.ball
    }

    #[view]
    fn paddle(number: u8) -> Paddle {
        let state = _state::read();
        if (number == 0_u8) {
            state.paddle_0
        } else {
            state.paddle_1
        }
    }

    #[view]
    fn player(number: u8) -> Player {
        IGameRoom::player(number)
    }

    #[view]
    fn wager() -> u256 {
        _wager::read()
    }

    #[view]
    fn fee() -> u128 {
        _fee::read()
    }

    #[view]
    fn random_seed() -> u64 {
        _random_seed::read()
    }

    //***********************************************************//
    //         JOIN & EXIT GAME ROOM EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn join_game_room(offchain_public_key: ContractAddress) {
        assert_deadline();
        assert_status(GameRoomStatus::WaitingForPlayers(()));
        assert(_get_caller_player_number().is_none(), 'PLAYER_ALREADY_JOINED');

        let player_address = get_caller_address();
        _send_wager_to_game_room(player_address);

        let player_number: u8 = _get_empty_player_number().unwrap();
        _players::write(
            player_number,
            Player { address: player_address, offchain_public_key: offchain_public_key }
        );

        _start_game();

        let factory = IGameRoomFactoryDispatcher { contract_address: _factory_address::read() };
        factory.update_players_from_game_room(get_contract_address());
    }

    #[external]
    fn close_game_room() {
        let status = _status::read();

        if (status == GameRoomStatus::InProgress(())) {
            assert_past_deadline();
        } else {
            assert_status(GameRoomStatus::WaitingForPlayers(()));
            // Only the player who created the room can close it befor it started
            let player_0 = _players::read(0_u8);
            if (player_0.address.is_non_zero()) {
                assert(player_0.address == get_caller_address(), 'WRONG_PLAYER');
            } else {
                let player_1 = _players::read(1_u8);
                assert(player_1.address == get_caller_address(), 'WRONG_PLAYER');
            }
        }

        _refund_wagers();
        _status::write(GameRoomStatus::Closed(()));
    }

    //***********************************************************//
    //               GAME STATE EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn set_checkpoint(checkpoint: Checkpoint) {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));

        _set_checkpoint(checkpoint);
        if (checkpoint.state.winner().is_some()) {
            _finish_game();
        }
    }

    #[external]
    fn advance_game_state(mut turns: Array<TurnAction>) {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));
        assert(turns.len() > 0, 'EMPTY_TURNS');

        _advance_game_state(turns);

        let new_game_state = _state::read();
        if (new_game_state.winner().is_some()) {
            _finish_game();
        }
    }

    #[external]
    fn exit_unplayed() {
        assert_deadline();
        assert_player(Option::None(()));
        assert_status(GameRoomStatus::InProgress(()));
        _partial_exit(false);
    }

    #[external]
    fn exit_with_partial_result(
        checkpoint: Checkpoint, mut turns: Array<TurnAction>, use_optimal_predictable_result: bool
    ) {
        assert_deadline();
        assert_player(Option::None(()));
        assert_status(GameRoomStatus::InProgress(()));

        if (checkpoint.state.turn > _state::read().turn) {
            _set_checkpoint(checkpoint);
        }

        if (turns.len() > 0) {
            _advance_game_state(turns);
        }

        _partial_exit(use_optimal_predictable_result);
    }

    #[external]
    fn dispute_partial_result(evidence: TurnAction) {
        assert_deadline();
        assert_status(GameRoomStatus::PartialExit(()));
        assert_player_can_dispute();
        _dispute_partial_result(evidence);
    }

    #[external]
    fn confirm_partial_result() {
        assert_deadline();
        assert_status(GameRoomStatus::PartialExit(()));
        assert_player_can_dispute();
        _finish_partial_exit();
    }

    #[external]
    fn finish_exit_with_partial_result() {
        assert_past_deadline();
        assert_status(GameRoomStatus::PartialExit(()));
        _finish_partial_exit();
    }

    //***********************************************************//
    //              GAME STATUS INTERNAL FUNCTIONS
    //***********************************************************//

    fn _start_game() {
        _status::write(GameRoomStatus::InProgress(()));
        _set_deadline(60_u64);
        GameStarted();
    }

    fn _set_checkpoint(checkpoint: Checkpoint) {
        let new_game_state_hash = checkpoint.state.hash();
        let player_0 = _players::read(0_u8);
        let player_1 = _players::read(1_u8);

        assert(checkpoint.state.is_valid(@_state::read()), 'INVALID_GAME_STATE');
        assert(
            checkpoint
                .verify_signatures(player_0.offchain_public_key, player_1.offchain_public_key),
            'INVALID_CHECKPOINT'
        );

        _state::write(checkpoint.state);
        GameStateUpdated(checkpoint.state);
    }

    fn _advance_game_state(mut turns: Array<TurnAction>) {
        let mut new_game_state = _state::read();
        let random_seed = _random_seed::read();

        loop {
            match turns.pop_front() {
                Option::Some(turn_action) => {
                    let next_turn = new_game_state.turn + 1;
                    assert(turn_action.turn <= next_turn, 'NON_CONSECUTIVE_TURN');

                    if (turn_action.turn == next_turn) {
                        let player_number = player_number_from_turn(next_turn);
                        let player = _players::read(player_number);

                        assert(
                            turn_action.verify_signature(player.offchain_public_key),
                            'INVALID_TURN_ACTION'
                        );

                        new_game_state = new_game_state.apply_turn(turn_action, random_seed);

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
    }

    fn _finish_game() {
        let game_state = _state::read();
        let winner = game_state.winner().unwrap();
        _pay_prize_and_fees(Option::Some(winner));
        _status::write(GameRoomStatus::Finished(()));
        GameFinished();
    }

    fn _partial_exit(use_optimal_predictable_result: bool) {
        _optimal_predictable_result::write(use_optimal_predictable_result);
        _exit_player_number::write(_get_caller_player_number().unwrap());

        _status::write(GameRoomStatus::PartialExit(()));

        _set_deadline(60_u64);
        PartialExit(_state::read().turn);
    }

    fn _dispute_partial_result(evidence: TurnAction) {
        //Disputing a result requires a signed turn from the Player who exited the game,
        //which is higher than the last turn saved to the game state
        let exited_player_number = _exit_player_number::read();
        let exited_player = _players::read(exited_player_number);
        assert(
            evidence.verify_signature(exited_player.offchain_public_key),
            'INVALID_EVIDENCE_SIGNATURE'
        );
        assert(evidence.turn >= _state::read().turn, 'INVALID_EVIDENCE_TURN');

        //No matter the result, if a player successfully disputes a result, that player receives the full prize
        _pay_prize_and_fees(_get_caller_player_number());

        _status::write(GameRoomStatus::Finished(()));
        PartialResultDisputed();
        PartialGameFinished();
    }

    fn _finish_partial_exit() {
        if (_optimal_predictable_result::read()) {
            let optimal_predictable_result = _state::read().calculate_optimal_predictable_result();
            _state::write(optimal_predictable_result);
        }

        //winner is only one of the players is the MAX_SCORE is reached
        //if not, it is none
        let winner = _state::read().winner();
        _pay_prize_and_fees(winner);

        _status::write(GameRoomStatus::Finished(()));
        PartialGameFinished();
    }


    //***********************************************************//
    //                 UTILS INTERNAL FUNCTIONS                 
    //***********************************************************//

    fn assert_player(player_number: Option<u8>) {
        match player_number {
            Option::Some(player_number) => {
                let player_address = get_caller_address();
                let player = _players::read(player_number);
                assert(player_address == player.address, 'NOT_THE_PLAYER');
            },
            Option::None(()) => {
                assert(_get_caller_player_number().is_some(), 'NOT_A_PLAYER');
            }
        }
    }

    fn _get_caller_player_number() -> Option<u8> {
        let caller_address = get_caller_address();
        let player_0 = _players::read(0_u8);
        let player_1 = _players::read(1_u8);
        if (player_0.address == caller_address) {
            return Option::Some(0_u8);
        }
        if (player_1.address == caller_address) {
            return Option::Some(1_u8);
        }
        Option::None(())
    }

    fn _get_empty_player_number() -> Option<u8> {
        let player_0_address = _players::read(0_u8).address;
        let player_1_address = _players::read(1_u8).address;

        if (player_0_address.is_zero()) {
            return Option::Some(0_u8);
        } else if (player_1_address.is_zero()) {
            return Option::Some(1_u8);
        }
        Option::None(())
    }

    fn assert_player_can_dispute() {
        let player_number = _get_caller_player_number();
        assert(player_number.is_some(), 'NOT_A_PLAYER');
        assert(
            player_number.unwrap() != player_number_from_turn(_state::read().turn), 'WRONG_PLAYER'
        );
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

    fn assert_past_deadline() {
        let block_timestamp = get_block_timestamp();
        let deadline = _deadline::read();
        assert(block_timestamp > deadline, 'NOT_PAST_DEADLINE');
    }

    fn _set_deadline(minutes: u64) {
        let block_timestamp = get_block_timestamp();
        let deadline = block_timestamp + (minutes * 60_u64);
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
            let creator_address = if (player_0.address.is_zero()) {
                player_1.address
            } else {
                player_0.address
            };
            assert(game_token.transfer(creator_address, total_balance), 'REFUND_FAILED');
        } else {
            let total_balance_252: felt252 = total_balance.try_into().unwrap();
            let total_balance_128: u128 = total_balance_252.try_into().unwrap();
            let amount_for_each_player_128: u128 = total_balance_128 / 2_u128;
            let amount_for_each_player_252: felt252 = amount_for_each_player_128.into();
            let amount_for_each_player: u256 = amount_for_each_player_252.into();

            assert(game_token.transfer(player_0.address, amount_for_each_player), 'REFUND_FAILED');
            assert(game_token.transfer(player_1.address, amount_for_each_player), 'REFUND_FAILED');
        }
    }

    fn _pay_prize_and_fees(player_number: Option<u8>) {
        //This function receives the player number of a winner if:
        // - The game is really over, and there is a winner
        // - A partial result was successfully disputed
        // - A partial result was completed with optimalresult and there's a player with MAX_SCORE

        //Player is otherwise None, even in cases where there's a clear winner
        // - A 2-0 partial exit for example, will have a winner None

        //The game incentivizes complete games by always taking away the full wager
        //from the losing player, but only giving the complete prize to a full winner.

        if (_wager::read() > 0_u256) {
            let contract_address = get_contract_address();
            let factory_address = _factory_address::read();
            let factory = IGameRoomFactoryDispatcher { contract_address: factory_address };
            let game_token_address = factory.game_token();
            let game_token = IERC20Dispatcher { contract_address: game_token_address };

            let total_balance = game_token.balance_of(contract_address);
            let fee: felt252 = _fee::read().into();

            let total_balance_252: felt252 = total_balance.try_into().unwrap();
            let total_balance_128: u128 = total_balance_252.try_into().unwrap();
            let fees_to_factory_contract_128: u128 = total_balance_128
                / 10000_u128
                * fee.try_into().unwrap();
            let fees_to_factory_contract_252: felt252 = fees_to_factory_contract_128.into();

            let mut fees_to_factory_contract: u256 = fees_to_factory_contract_252.into();
            let mut total_prize: u256 = total_balance - fees_to_factory_contract;

            match player_number {
                Option::Some(winner) => {
                    //A FULL winner receives the total prize
                    assert(
                        game_token.transfer(_players::read(winner).address, total_prize),
                        'PRIZE_TRANSFER_FAILED'
                    );
                },
                Option::None(()) => {
                    //No score can be MAX_SCORE, or we would have a winner
                    let player_0_score = _state::read().score_0;
                    let player_1_score = _state::read().score_0;

                    let player_0_score_252: felt252 = player_0_score.into();
                    let player_0_score_128: u128 = player_0_score_252.try_into().unwrap();
                    let player_1_score_252: felt252 = player_1_score.into();
                    let player_1_score_128: u128 = player_1_score_252.try_into().unwrap();

                    //Reduce the prize according to the maximum score
                    let total_prize_252: felt252 = total_prize.try_into().unwrap();
                    let total_prize_128: u128 = total_prize_252.try_into().unwrap();

                    //The remaining tokens will go to factory contract
                    let MAX_SCORE_252: felt252 = MAX_SCORE.into();
                    let MAX_SCORE_128: u128 = MAX_SCORE_252.try_into().unwrap();

                    let mut new_total_prize_128 = 0_u128;

                    if (player_0_score == player_1_score) {
                        new_total_prize_128 = total_prize_128
                            / (MAX_SCORE_128 - player_0_score_128);
                    //33% of the total prize for 0-0 (16.6% each: both at a loss)
                    //66% of the total prize for 1-1 (33% each: both at a loss)
                    //100% of the total prize for 2-2 (50% each: both at a very small loss (just the fees))

                    } else {
                        let point_diff = if (player_0_score > player_1_score) {
                            (player_0_score - player_1_score) - 1_u8
                        } else {
                            (player_1_score - player_1_score) - 1_u8
                        };

                        let point_diff_252: felt252 = point_diff.into();
                        let point_diff_128: u128 = point_diff_252.try_into().unwrap();
                        new_total_prize_128 = total_prize_128 / (MAX_SCORE_128 - point_diff_128);
                    //33% of the total prize for 1-0, 2-1 (winner loses a small part, loser loses all)
                    //66% of the total prize for 2-0 (winner makes a small profit, loser loses all)
                    }

                    //What doesn't go to the player is added to the factory fees
                    let new_total_prize_252: felt252 = new_total_prize_128.into();
                    let new_total_prize_256: u256 = new_total_prize_252.into();

                    let penalty_for_factory: u128 = total_prize_128 - new_total_prize_128;
                    let penalty_for_factory_252: felt252 = penalty_for_factory.into();
                    fees_to_factory_contract += penalty_for_factory_252.into();

                    if (player_0_score == player_1_score) {
                        //Split in half for each player
                        let half_prize_128: u128 = new_total_prize_128 / 2_u128;
                        let half_prize_252: felt252 = half_prize_128.into();
                        let half_prize: u256 = half_prize_252.into();

                        assert(
                            game_token.transfer(_players::read(0_u8).address, half_prize),
                            'REFUND_FAILED'
                        );
                        assert(
                            game_token.transfer(_players::read(1_u8).address, half_prize),
                            'REFUND_FAILED'
                        );
                    } else if (player_0_score > player_1_score) {
                        //Player 0 wins partial victory
                        assert(
                            game_token.transfer(_players::read(0_u8).address, new_total_prize_256),
                            'REFUND_FAILED'
                        );
                    } else {
                        //Player 1 wins partial victory
                        assert(
                            game_token.transfer(_players::read(1_u8).address, new_total_prize_256),
                            'REFUND_FAILED'
                        );
                    }
                }
            }

            if (fees_to_factory_contract > 0_u256) {
                assert(
                    game_token.transfer(factory_address, fees_to_factory_contract),
                    'FEE_PAYMENT_FAILED'
                );
            }
        }
    }
}
