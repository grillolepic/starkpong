use starknet::StorageAccess;
use starknet::ContractAddress;

#[derive(PartialEq, Copy, Drop, Serde, storage_access::StorageAccess)]
enum GameRoomStatus {
    WaitingForPlayers: (),
    InProgress: (),
    Finished: (),
    PartialExit: (),
    Closed: ()
}

impl IntoFelt252GameRoomStatusImpl of Into<GameRoomStatus, felt252> {
    fn into(self: GameRoomStatus) -> felt252 {
        match self {
            GameRoomStatus::WaitingForPlayers(()) => 0,
            GameRoomStatus::InProgress(()) => 1,
            GameRoomStatus::Finished(()) => 2,
            GameRoomStatus::PartialExit(()) => 3,
            GameRoomStatus::Closed(()) => 4
        }
    }
}
