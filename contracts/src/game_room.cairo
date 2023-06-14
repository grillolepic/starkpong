use starknet::ContractAddress;

#[abi]
trait IGameRoom {
    #[view]
    fn is_active() -> bool;
}

#[contract]
mod GameRoom {    
    use super::IGameRoom;
    use starknet::ContractAddress;
    use stark_pong::utils::player::{Player, StorageAccessPlayerImpl};
    use stark_pong::utils::game_room_status::{GameRoomStatus, StorageAccessGameRoomStatusImpl};
    use stark_pong::game::game_components::objects::{Paddle, Ball};
    use stark_pong::game::game_components::actions::TurnAction;

    struct Storage {
        _factory_address: ContractAddress,
        _wager: u256,

        _players: LegacyMap<u8, Player>,
        _status: GameRoomStatus,

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
        _wager::write(wager);
    }

    //***********************************************************//
    //         JOIN & EXIT GAME ROOM EXTERNAL FUNCTIONS
    //***********************************************************//

    #[external]
    fn join_game_room(
        player_address: ContractAddress,
        offchain_public_key: ContractAddress
    ) {}

    #[external]
    fn exit_game_room() {}

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
}