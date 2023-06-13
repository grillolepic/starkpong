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
        offchain_address: ContractAddress,
        wager: u256
    ) {
        _wager::write(wager);
    }
}