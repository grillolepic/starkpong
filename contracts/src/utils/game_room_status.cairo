use serde::Serde;
use array::ArrayTrait;
use core::array::SpanTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use result::{ResultTrait, ResultTraitImpl};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};
use starknet::{ContractAddress, Felt252TryIntoContractAddress};

#[derive(PartialEq, Serde, Copy, Drop)]
enum GameRoomStatus {
    WaitingForPlayers: (),
    InProgress: (),
    Finished: (),
    Disputed: (),
    Closed: ()
}

impl IntoFelt252GameRoomStatusImpl of Into<GameRoomStatus, felt252> {
    fn into(self: GameRoomStatus) -> felt252 {
        match self {
            GameRoomStatus::WaitingForPlayers(()) => 0,
            GameRoomStatus::InProgress(()) => 1,
            GameRoomStatus::Finished(()) => 2,
            GameRoomStatus::Disputed(()) => 3,
            GameRoomStatus::Closed(()) => 4
        }
    }
}

impl IntoGameRoomStatusFelt252Impl of Into<felt252, GameRoomStatus> {
    fn into(self: felt252) -> GameRoomStatus {
        if (self == 0) {
            return GameRoomStatus::WaitingForPlayers(());
        } else if (self == 1) {
            return GameRoomStatus::InProgress(());
        } else if (self == 2) {
            return GameRoomStatus::Finished(());
        } else if (self == 3) {
            return GameRoomStatus::Disputed(());
        }
        GameRoomStatus::Closed(())
    }
}

//    impl SerdeGameRoomStatusImpl of Serde<GameRoomStatus> {
//        fn serialize(self: @GameRoomStatus, ref output: Array<felt252>) {
//            let game_room_status = *self;
//            let felt_value: felt252 = game_room_status.into();
//            output.append(felt_value);
//        }
//        fn deserialize(ref serialized: Span<felt252>) -> Option<GameRoomStatus> {
//            let felt_value: felt252 = *serialized.at(0);
//            Option::Some(felt_value.into())
//        }
//    }

impl StorageAccessGameRoomStatusImpl of StorageAccess<GameRoomStatus> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: GameRoomStatus) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<GameRoomStatus> {
        let mut stored_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        Result::Ok(stored_value.into())
    }
}
