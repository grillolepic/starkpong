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
    use ecdsa::check_ecdsa_signature;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
    use stark_pong::utils::game_room_status::{GameRoomStatus, StorageAccessGameRoomStatusImpl};
    use stark_pong::game::{initial_game_state};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::state::{GameState};
    use stark_pong::game::game_components::actions::TurnAction;
    use stark_pong::game_room_factory::{IGameRoomFactoryDispatcher, IGameRoomFactoryDispatcherTrait};
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};

    struct Storage {
        _factory_address: ContractAddress,
        _players: LegacyMap<u8, Player>,
        _status: GameRoomStatus,
        _deadline: u64,
        _wager: u256,
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
        wager: u256
    ) {
        _set_deadline(30_u64);

        _factory_address::write(factory_address);
        _status::write(GameRoomStatus::WaitingForPlayers(()));
        _wager::write(wager);

        let block_timestamp = get_block_timestamp();
        let player_number: u8 = (block_timestamp % 2_u64).try_into().unwrap();

        _players::write(player_number, Player {
            address: player_address,
            offchain_public_key: offchain_public_key
        });
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    fn GameStarted() {}

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
    fn join_game_room(
        offchain_public_key: ContractAddress
    ) {
        assert_deadline();
        assert_status(GameRoomStatus::WaitingForPlayers(()));
        
        let player_address = get_caller_address();

        let mut other_player_number = 0_u8;
        if (_players::read(0_u8).address.is_zero()) {
            other_player_number = 1_u8;
        }
        assert(player_address != _players::read(other_player_number).address, 'SAME_PLAYER');

        _send_wager_to_game_room(player_address);

        let player_number: u8 = if (other_player_number == 0_u8) { 1_u8 } else { 0_u8 };
        _players::write(player_number, Player {
            address: player_address,
            offchain_public_key: offchain_public_key
        });
        
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
    fn set_game_state() {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));
    }

    #[external]
    fn advance_game_state() {
        assert_deadline();
        assert_status(GameRoomStatus::InProgress(()));
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

    //***********************************************************//
    //              GAME STATUS INTERNAL FUNCTIONS
    //***********************************************************//

    fn _start_game() {
        _status::write(GameRoomStatus::InProgress(()));
        _set_deadline(60_u64);
        _state::write(initial_game_state());
        GameStarted();
    }

    fn _finish_game() {}

    fn _calculate_optimal_result() {}

    //***********************************************************//
    //         SIGNATURE VERIFICATION INTERNAL FUNCTIONS
    //***********************************************************//

    fn _verify_signature() {}

    fn _verify_game_state() {}

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
            assert(game_token.transfer_from(player_address, contract_address, wager), 'WAGER_TRANSFER_FAILED');
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
        
        if (player_1.address.is_zero()) {
            assert(game_token.transfer(player_0.address, total_balance), 'REFUND_FAILED');
        } else {
            let balance_for_each = total_balance / 2_u256;
            assert(game_token.transfer(player_0.address, balance_for_each), 'REFUND_FAILED');
            assert(game_token.transfer(player_1.address, balance_for_each), 'REFUND_FAILED');
        }
    }
}