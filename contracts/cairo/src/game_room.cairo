use stark_pong::game::game_components::actions::TurnActionTrait;
use stark_pong::utils::player::Player;
use stark_pong::utils::game_room_status::GameRoomStatus;
use stark_pong::game::game_components::objects::{Paddle, Ball};
use core::zeroable::Zeroable;
use starknet::ContractAddress;
use stark_pong::game::game_components::state::{GameState, Checkpoint};
use stark_pong::game::game_components::actions::TurnAction;

#[starknet::interface]
trait IGameRoom<TContractState> {
    //View Functions
    fn is_active(self: @TContractState) -> bool;
    fn factory(self: @TContractState) -> ContractAddress;
    fn num_players(self: @TContractState) -> u8;
    fn player(self: @TContractState, number: u8) -> Player;
    fn status(self: @TContractState) -> (GameRoomStatus, u64);
    fn game_state(self: @TContractState) -> GameState;
    fn wager(self: @TContractState) -> (ContractAddress, u256);
    fn fee(self: @TContractState) -> u128;
    fn random_seed(self: @TContractState) -> u64;
    
    //Public Functions
    fn join_game_room(ref self: TContractState, offchain_public_key: ContractAddress);
    fn close_game_room(ref self: TContractState);
    fn set_checkpoint(ref self: TContractState, checkpoint: Checkpoint);
    fn advance_game_state(ref self: TContractState, turns: Array<TurnAction>);
    fn exit_unplayed(ref self: TContractState);
    fn exit_with_partial_result(ref self: TContractState, checkpoint: Checkpoint, turns: Array<TurnAction>, use_optimal_predictable_result: bool);
    fn dispute_partial_result(ref self: TContractState, evidence: TurnAction);
    fn confirm_partial_result(ref self: TContractState);
    fn finish_exit_with_partial_result(ref self: TContractState);
}

#[starknet::contract]
mod GameRoom {
    use super::IGameRoom;
    use option::OptionTrait;
    use zeroable::Zeroable;
    use traits::{Into, TryInto};
    use array::{ArrayTrait, SpanTrait};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use stark_pong::utils::player::Player;
    use stark_pong::utils::game_room_status::GameRoomStatus;
    use stark_pong::utils::signature::{Signature};
    use stark_pong::game::{initial_game_state, player_number_from_turn, WINNING_SCORE};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::state::{
        GameState, GameStateTrait, Checkpoint, CheckpointTrait
    };
    use stark_pong::game::game_components::actions::{TurnAction, TurnActionTrait};
    use stark_pong::game_room_factory::{
        IGameRoomFactoryDispatcher, IGameRoomFactoryDispatcherTrait
    };
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        factory: ContractAddress,
        players: LegacyMap<u8, Player>,
        status: GameRoomStatus,
        random_seed: u64,
        deadline: u64,
        wager_token: ContractAddress,
        wager: u256,
        fee: u128,
        game_state: GameState,
        optimal_predictable_result: bool,
        exit_player_number: u8
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        factory: ContractAddress,
        player_address: ContractAddress,
        offchain_public_key: ContractAddress,
        wager_token: ContractAddress,
        wager: u256,
        fee: u128
    ) {
        self._set_deadline(30_u64);

        self.factory.write(factory);
        self.status.write(GameRoomStatus::WaitingForPlayers(()));
        self.wager_token.write(wager_token);
        self.wager.write(wager);
        self.fee.write(fee);

        let random_seed = get_block_timestamp();
        self.random_seed.write(random_seed);

        let seed_mod: felt252 = (random_seed % 2_u64).into();
        let player_number: u8 = seed_mod.try_into().unwrap();

        self
            .players
            .write(
                player_number,
                Player { address: player_address, offchain_public_key: offchain_public_key }
            );

        let empty_player = Player {
            address: Zeroable::zero(), offchain_public_key: Zeroable::zero()
        };
        let empty_player_number: u8 = self._get_empty_player_number().unwrap();
        self.players.write(empty_player_number, empty_player);

        self.game_state.write(initial_game_state(random_seed));
        self.optimal_predictable_result.write(false);
        self.exit_player_number.write(0_u8);
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameStarted: GameStarted,
        GameStateUpdated: GameStateUpdated,
        GameFinished: GameFinished,
        PartialExit: PartialExit,
        PartialResultDisputed: PartialResultDisputed,
        PartialGameFinished: PartialGameFinished,
        GameRoomClosed: GameRoomClosed
    }

    #[derive(Drop, starknet::Event)]
    struct GameStarted {}

    #[derive(Drop, starknet::Event)]
    struct GameStateUpdated {
        state: GameState
    }

    #[derive(Drop, starknet::Event)]
    struct GameFinished {}

    #[derive(Drop, starknet::Event)]
    struct PartialExit {
        last_turn: u64
    }

    #[derive(Drop, starknet::Event)]
    struct PartialResultDisputed {}

    #[derive(Drop, starknet::Event)]
    struct PartialGameFinished {}

    #[derive(Drop, starknet::Event)]
    struct GameRoomClosed {}

    //***********************************************************//
    //                   IMPL CONTRACT LOGIC
    //***********************************************************//

    impl GameRoomImpl of IGameRoom<ContractState> {
        //***********************************************************//
        //                      VIEW FUNCTIONS       
        //***********************************************************//

        fn is_active(self: @ContractState) -> bool {
            let block_timestamp = get_block_timestamp();
            let deadline = self.deadline.read();
            let before_deadlie = (block_timestamp <= deadline);

            match self.status.read() {
                GameRoomStatus::WaitingForPlayers(()) => before_deadlie,
                GameRoomStatus::InProgress(()) => before_deadlie,
                GameRoomStatus::Finished(()) => false,
                GameRoomStatus::PartialExit(()) => before_deadlie,
                GameRoomStatus::Closed(()) => false
            }
        }

        fn factory(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }

        fn num_players(self: @ContractState) -> u8 {
            2_u8
        }
        
        fn player(self: @ContractState, number: u8) -> Player {
            self.players.read(number)
        }

        fn status(self: @ContractState) -> (GameRoomStatus, u64) {
            (self.status.read(), self.deadline.read())
        }

        fn game_state(self: @ContractState) -> GameState {
            self.game_state.read()
        }

        fn wager(self: @ContractState) -> (ContractAddress, u256) {
            (self.wager_token.read(), self.wager.read())
        }

        fn fee(self: @ContractState) -> u128 {
            self.fee.read()
        }

        fn random_seed(self: @ContractState) -> u64 {
            self.random_seed.read()
        }

        //***********************************************************//
        //                     PUBLIC FUNCTIONS       
        //***********************************************************//

        fn join_game_room(ref self: ContractState, offchain_public_key: ContractAddress) {
            self._assert_deadline();
            self._assert_status(GameRoomStatus::WaitingForPlayers(()));
            assert(self._get_caller_player_number().is_none(), 'PLAYER_ALREADY_JOINED');

            let player_address = get_caller_address();
            self._send_wager_to_game_room(player_address);

            let player_number: u8 = self._get_empty_player_number().unwrap();
            self.players
                .write(
                    player_number,
                    Player { address: player_address, offchain_public_key: offchain_public_key }
                );

            self._start_game();

            let factory = IGameRoomFactoryDispatcher { contract_address: self.factory.read() };
            factory.update_players_from_game_room(get_contract_address());
        }

        fn close_game_room(ref self: ContractState) {
            let status = self.status.read();

            if (status == GameRoomStatus::InProgress(())) {
                self._assert_past_deadline();
            } else {
                self._assert_status(GameRoomStatus::WaitingForPlayers(()));
                // Only the player who created the room can close it befor it started
                let player_0 = self.players.read(0_u8);
                if (player_0.address.is_non_zero()) {
                    assert(player_0.address == get_caller_address(), 'WRONG_PLAYER');
                } else {
                    let player_1 = self.players.read(1_u8);
                    assert(player_1.address == get_caller_address(), 'WRONG_PLAYER');
                }
            }

            self._refund_wagers();
            self.status.write(GameRoomStatus::Closed(()));
        }

        //***********************************************************//
        //               GAME STATE EXTERNAL FUNCTIONS
        //***********************************************************//

        fn set_checkpoint(ref self: ContractState, checkpoint: Checkpoint) {
            self._assert_deadline();
            self._assert_status(GameRoomStatus::InProgress(()));

            self._set_checkpoint(checkpoint);
            if (checkpoint.state.winner().is_some()) {
                self._finish_game();
            }
        }

        fn advance_game_state(ref self: ContractState, mut turns: Array<TurnAction>) {
            self._assert_deadline();
            self._assert_status(GameRoomStatus::InProgress(()));
            assert(turns.len() > 0, 'EMPTY_TURNS');

            self._advance_game_state(turns);

            let new_game_state = self.game_state.read();
            if (new_game_state.winner().is_some()) {
                self._finish_game();
            }
        }

        fn exit_unplayed(ref self: ContractState, ) {
            self._assert_deadline();
            self._assert_player(Option::None(()));
            self._assert_status(GameRoomStatus::InProgress(()));
            self._partial_exit(false);
        }

        fn exit_with_partial_result(
            ref self: ContractState, 
            checkpoint: Checkpoint,
            mut turns: Array<TurnAction>,
            use_optimal_predictable_result: bool
        ) {
            self._assert_deadline();
            self._assert_player(Option::None(()));
            self._assert_status(GameRoomStatus::InProgress(()));

            if (checkpoint.state.turn > self.game_state.read().turn) {
                self._set_checkpoint(checkpoint);
            }

            if (turns.len() > 0) {
                self._advance_game_state(turns);
            }

            self._partial_exit(use_optimal_predictable_result);
        }

        fn dispute_partial_result(ref self: ContractState, evidence: TurnAction) {
            self._assert_deadline();
            self._assert_status(GameRoomStatus::PartialExit(()));
            self._assert_player_can_dispute();
            self._dispute_partial_result(evidence);
        }

        fn confirm_partial_result(ref self: ContractState) {
            self._assert_deadline();
            self._assert_status(GameRoomStatus::PartialExit(()));
            self._assert_player_can_dispute();
            self._finish_partial_exit();
        }

        fn finish_exit_with_partial_result(ref self: ContractState) {
            self._assert_past_deadline();
            self._assert_status(GameRoomStatus::PartialExit(()));
            self._finish_partial_exit();
        }
    }

    //***********************************************************//
    //                  INTERNAL FUNCTIONS              
    //***********************************************************//

    #[generate_trait]
    impl PrivateMethods of PrivateMethodsTrait {

        fn _start_game(ref self: ContractState) {
            self.status.write(GameRoomStatus::InProgress(()));
            self._set_deadline(60_u64);
            self.emit(Event::GameStarted(GameStarted {}));

            //TODO: Send message to factory to emit event?
        }

        fn _set_checkpoint(ref self: ContractState, checkpoint: Checkpoint) {
            let new_game_state_hash = checkpoint.state.hash();
            let player_0 = self.players.read(0_u8);
            let player_1 = self.players.read(1_u8);

            assert(checkpoint.state.is_valid(@self.game_state.read()), 'INVALID_GAME_STATE');
            assert(
                checkpoint
                    .verify_signatures(player_0.offchain_public_key, player_1.offchain_public_key),
                'INVALID_CHECKPOINT'
            );

            self.game_state.write(checkpoint.state);
            self.emit(Event::GameStateUpdated(GameStateUpdated {
                state: checkpoint.state
            }));

            //TODO: Send message to factory to emit event?
        }

        fn _advance_game_state(ref self: ContractState, mut turns: Array<TurnAction>) {
            let mut new_game_state = self.game_state.read();
            let random_seed = self.random_seed.read();

            loop {
                match turns.pop_front() {
                    Option::Some(turn_action) => {
                        let next_turn = new_game_state.turn + 1;
                        assert(turn_action.turn <= next_turn, 'NON_CONSECUTIVE_TURN');

                        if (turn_action.turn == next_turn) {
                            let player_number = player_number_from_turn(next_turn);
                            let player = self.players.read(player_number);

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

            self.game_state.write(new_game_state);
            self.emit(Event::GameStateUpdated(GameStateUpdated {
                state: new_game_state
            }));

            //TODO: Send message to factory to emit event?
        }

        fn _finish_game(ref self: ContractState) {
            let game_state = self.game_state.read();
            let winner = game_state.winner().unwrap();
            self._pay_prize_and_fees(Option::Some(winner));
            self.status.write(GameRoomStatus::Finished(()));
            self.emit(Event::GameFinished(GameFinished {}));

            //TODO: Send message to factory to emit event?
        }

        fn _partial_exit(ref self: ContractState, use_optimal_predictable_result: bool) {
            self.optimal_predictable_result.write(use_optimal_predictable_result);
            self.exit_player_number.write(self._get_caller_player_number().unwrap());

            self.status.write(GameRoomStatus::PartialExit(()));

            self._set_deadline(60_u64);

            self.emit(Event::PartialExit(PartialExit {
                last_turn: self.game_state.read().turn
            }));

            //TODO: Send message to factory to emit event?
        }

        fn _dispute_partial_result(ref self: ContractState, evidence: TurnAction) {
            //Disputing a result requires a signed turn from the Player who exited the game,
            //which is higher than the last turn saved to the game state
            let exited_player_number = self.exit_player_number.read();
            let exited_player = self.players.read(exited_player_number);
            assert(
                evidence.verify_signature(exited_player.offchain_public_key),
                'INVALID_EVIDENCE_SIGNATURE'
            );
            assert(evidence.turn >= self.game_state.read().turn, 'INVALID_EVIDENCE_TURN');

            //No matter the result, if a player successfully disputes a result, that player receives the full prize
            self._pay_prize_and_fees(self._get_caller_player_number());

            self.status.write(GameRoomStatus::Finished(()));

            self.emit(Event::PartialResultDisputed(PartialResultDisputed {}));
            self.emit(Event::PartialGameFinished(PartialGameFinished {}));

            //TODO: Send message to factory to emit event?
        }

        fn _finish_partial_exit(ref self: ContractState) {
            if (self.optimal_predictable_result.read()) {
                let optimal_predictable_result = self.game_state.read().calculate_optimal_predictable_result();
                self.game_state.write(optimal_predictable_result);
            }

            //winner is only one of the players is the MAX_SCORE is reached
            //if not, it is none
            let winner = self.game_state.read().winner();
            self._pay_prize_and_fees(winner);

            self.status.write(GameRoomStatus::Finished(()));
            self.emit(Event::PartialGameFinished(PartialGameFinished {}));

            //TODO: Send message to factory to emit event?
        }


        //***********************************************************//
        //                 UTILS INTERNAL FUNCTIONS                 
        //***********************************************************//

        fn _assert_player(self: @ContractState, player_number: Option<u8>) {
            match player_number {
                Option::Some(player_number) => {
                    let player_address = get_caller_address();
                    let player = self.players.read(player_number);
                    assert(player_address == player.address, 'NOT_THE_PLAYER');
                },
                Option::None(()) => {
                    assert(self._get_caller_player_number().is_some(), 'NOT_A_PLAYER');
                }
            }
        }

        fn _get_caller_player_number(self: @ContractState) -> Option<u8> {
            let caller_address = get_caller_address();
            let player_0 = self.players.read(0_u8);
            let player_1 = self.players.read(1_u8);
            if (player_0.address == caller_address) {
                return Option::Some(0_u8);
            }
            if (player_1.address == caller_address) {
                return Option::Some(1_u8);
            }
            Option::None(())
        }

        fn _get_empty_player_number(self: @ContractState) -> Option<u8> {
            let player_0_address = self.players.read(0_u8).address;
            let player_1_address = self.players.read(1_u8).address;

            if (player_0_address.is_zero()) {
                return Option::Some(0_u8);
            } else if (player_1_address.is_zero()) {
                return Option::Some(1_u8);
            }
            Option::None(())
        }

        fn _assert_player_can_dispute(self: @ContractState) {
            let player_number = self._get_caller_player_number();
            assert(player_number.is_some(), 'NOT_A_PLAYER');
            assert(
                player_number.unwrap() != player_number_from_turn(self.game_state.read().turn), 'WRONG_PLAYER'
            );
        }

        fn _assert_status(self: @ContractState, status: GameRoomStatus) {
            let current_status = self.status.read();
            assert(current_status == status, 'INVALID_STATUS');
        }

        fn _assert_deadline(self: @ContractState) {
            let block_timestamp = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(block_timestamp <= deadline, 'DEADLINE');
        }

        fn _assert_past_deadline(self: @ContractState) {
            let block_timestamp = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(block_timestamp > deadline, 'NOT_PAST_DEADLINE');
        }

        fn _set_deadline(ref self: ContractState, minutes: u64) {
            let block_timestamp = get_block_timestamp();
            let deadline = block_timestamp + (minutes * 60_u64);
            self.deadline.write(deadline);
        }

        fn _send_wager_to_game_room(self: @ContractState, player_address: ContractAddress) {
            let wager_token_address = self.wager_token.read();
            let wager = self.wager.read();
            if (wager > 0_u256) {
                let contract_address = get_contract_address();
                let game_token = IERC20Dispatcher { contract_address: wager_token_address };
                assert(
                    game_token.transfer_from(player_address, contract_address, wager),
                    'WAGER_TRANSFER_FAILED'
                );
            }
        }

        fn _refund_wagers(self: @ContractState) {
            let contract_address = get_contract_address();
            let wager_token_address = self.wager_token.read();
            let wager_token = IERC20Dispatcher { contract_address: wager_token_address };

            let player_0 = self.players.read(0_u8);
            let player_1 = self.players.read(1_u8);
            let total_balance = wager_token.balance_of(contract_address);

            if (player_1.address.is_zero() | player_0.address.is_zero()) {
                let creator_address = if (player_0.address.is_zero()) {
                    player_1.address
                } else {
                    player_0.address
                };
                assert(wager_token.transfer(creator_address, total_balance), 'REFUND_FAILED');
            } else {
                let total_balance_252: felt252 = total_balance.try_into().unwrap();
                let total_balance_128: u128 = total_balance_252.try_into().unwrap();
                let amount_for_each_player_128: u128 = total_balance_128 / 2_u128;
                let amount_for_each_player_252: felt252 = amount_for_each_player_128.into();
                let amount_for_each_player: u256 = amount_for_each_player_252.into();

                assert(wager_token.transfer(player_0.address, amount_for_each_player), 'REFUND_FAILED');
                assert(wager_token.transfer(player_1.address, amount_for_each_player), 'REFUND_FAILED');
            }
        }

        fn _pay_prize_and_fees(ref self: ContractState, player_number: Option<u8>) {
            //This function receives the player number of a winner if:
            // - The game is really over, and there is a winner
            // - A partial result was successfully disputed
            // - A partial result was completed with optimalresult and there's a player with MAX_SCORE

            //Player is otherwise None, even in cases where there's a clear winner
            // - A 2-0 partial exit for example, will have a winner None

            //The game incentivizes complete games by always taking away the full wager
            //from the losing player, but only giving the complete prize to a full winner.

            if (self.wager.read() > 0_u256) {
                let contract_address = get_contract_address();
                let wager_token_address = self.wager_token.read();
                let wager_token = IERC20Dispatcher { contract_address: wager_token_address };

                let total_balance = wager_token.balance_of(contract_address);
                let fee: felt252 = self.fee.read().into();

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
                            wager_token.transfer(self.players.read(winner).address, total_prize),
                            'PRIZE_TRANSFER_FAILED'
                        );
                    },
                    Option::None(()) => {
                        //No score can be MAX_SCORE, or we would have a winner
                        let player_0_score = self.game_state.read().score_0;
                        let player_1_score = self.game_state.read().score_0;

                        let player_0_score_252: felt252 = player_0_score.into();
                        let player_0_score_128: u128 = player_0_score_252.try_into().unwrap();
                        let player_1_score_252: felt252 = player_1_score.into();
                        let player_1_score_128: u128 = player_1_score_252.try_into().unwrap();

                        //Reduce the prize according to the maximum score
                        let total_prize_252: felt252 = total_prize.try_into().unwrap();
                        let total_prize_128: u128 = total_prize_252.try_into().unwrap();

                        //The remaining tokens will go to factory contract
                        let WINNING_SCORE_252: felt252 = WINNING_SCORE.into();
                        let WINNING_SCORE_128: u128 = WINNING_SCORE_252.try_into().unwrap();

                        let mut new_total_prize_128 = 0_u128;

                        if (player_0_score == player_1_score) {
                            new_total_prize_128 = total_prize_128
                                / (WINNING_SCORE_128 - player_0_score_128);
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
                            new_total_prize_128 = total_prize_128 / (WINNING_SCORE_128 - point_diff_128);
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
                                wager_token.transfer(self.players.read(0_u8).address, half_prize),
                                'REFUND_FAILED'
                            );
                            assert(
                                wager_token.transfer(self.players.read(1_u8).address, half_prize),
                                'REFUND_FAILED'
                            );
                        } else if (player_0_score > player_1_score) {
                            //Player 0 wins partial victory
                            assert(
                                wager_token.transfer(self.players.read(0_u8).address, new_total_prize_256),
                                'REFUND_FAILED'
                            );
                        } else {
                            //Player 1 wins partial victory
                            assert(
                                wager_token.transfer(self.players.read(1_u8).address, new_total_prize_256),
                                'REFUND_FAILED'
                            );
                        }
                    }
                }

                if (fees_to_factory_contract > 0_u256) {
                    assert(
                        wager_token.transfer(self.factory.read(), fees_to_factory_contract),
                        'FEE_PAYMENT_FAILED'
                    );
                }
            }
        }
    }
}
