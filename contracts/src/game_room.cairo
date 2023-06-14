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
    use traits::{Into, TryInto};
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
    use stark_pong::utils::game_room_status::{GameRoomStatus, StorageAccessGameRoomStatusImpl};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::actions::TurnAction;
    use stark_pong::game_room_factory::{IGameRoomFactoryDispatcher, IGameRoomFactoryDispatcherTrait};
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};

    struct Storage {
        _factory_address: ContractAddress,
        _status: GameRoomStatus,
        _deadline: u64,
        _wager: u256,
        _left_player: u8,
        _players: LegacyMap<u8, Player>,
        _score: LegacyMap<u8, u8>,
        _paddles: LegacyMap<u8, Paddle>,
        _ball: Ball
    }

    impl GameRoomImpl of IGameRoom {
        #[view]
        fn is_active() -> bool {
            true
        }
    }

    #[constructor]
    fn constructor(
        factory_address: ContractAddress,
        player_address: ContractAddress,
        offchain_public_key: ContractAddress,
        wager: u256
    ) {
        let block_timestamp = get_block_timestamp();
        let deadline = block_timestamp + (30_u64 * 60_u64 * 1000_u64);
        _deadline::write(deadline);
        _factory_address::write(factory_address);
        _status::write(GameRoomStatus::WaitingForPlayers(()));
        _wager::write(wager);
        _left_player::write((block_timestamp % 2_u64).try_into().unwrap());
        _players::write(0_u8, Player {
            address: player_address,
            offchain_public_key: offchain_public_key
        });
    }

    //***********************************************************//
    //                      VIEW FUNCTIONS
    //***********************************************************//
    


    //***********************************************************//
    //         JOIN & EXIT GAME ROOM EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn join_game_room(
        offchain_public_key: ContractAddress
    ) {
        let player_address = get_caller_address();
        assert(player_address != _players::read(0_u8).address, 'JOIN_GAME_ROOM_TWICE');

        _send_wager_to_game_room(player_address);

        let block_timestamp = get_block_timestamp();
        let deadline = _deadline::read();
        assert(block_timestamp < deadline, 'GAME_ROOM_PAST_DEADLINE');

        let new_deadline = block_timestamp + (30_u64 * 60_u64 * 1000_u64);
        _deadline::write(new_deadline);

        _players::write(1_u8, Player {
            address: player_address,
            offchain_public_key: offchain_public_key
        });
        
        _start_game();
    }

    #[external]
    fn abandon_game_room() {
        let block_timestamp = get_block_timestamp();
        let deadline = _deadline::read();
        assert(block_timestamp < deadline, 'GAME_ROOM_PAST_DEADLINE');

       
    }

    //***********************************************************//
    //               GAME STATE EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn set_game_state() {}

    #[external]
    fn advance_game_state() {}

    #[external]
    fn exit_with_partial_result() {}

    #[external]
    fn dispute_partial_result() {}

    //***********************************************************//
    //              GAME STATUS INTERNAL FUNCTIONS
    //***********************************************************//

    fn _start_game() {}

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

    fn assert_player() {}

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
}