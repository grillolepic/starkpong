use serde::Serde;
use array::ArrayTrait;
use option::OptionTrait;
use traits::{Into, TryInto};
use result::{ResultTrait, ResultTraitImpl};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};
use starknet::{ContractAddress, Felt252TryIntoContractAddress};

#[derive(PartialEq, Drop)]
enum GameRoomStatus {
    WaitingForPlayers: (),
    InProgress: (),
    Finished: (),
    Disputed: (),
    Closed: ()
}

impl StorageAccessGameRoomStatusImpl of StorageAccess<GameRoomStatus> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: GameRoomStatus) -> SyscallResult<()> {
        match value {
            GameRoomStatus::WaitingForPlayers(()) => storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), 0_u8.into()),
            GameRoomStatus::InProgress(()) => storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), 1_u8.into()),
            GameRoomStatus::Finished(()) => storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), 2_u8.into()),
            GameRoomStatus::Disputed(()) => storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), 3_u8.into()),
            GameRoomStatus::Closed(()) => storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), 4_u8.into())
        }
        
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<GameRoomStatus> {
        let mut status_value: u8 = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?.try_into().unwrap();
        
        if (status_value == 0) {
            return Result::Ok(GameRoomStatus::WaitingForPlayers(()));
        } else if (status_value == 1) {
            return Result::Ok(GameRoomStatus::InProgress(()));
        } else if (status_value == 2) {
            return Result::Ok(GameRoomStatus::Finished(()));
        } else if (status_value == 3) {
            return Result::Ok(GameRoomStatus::Disputed(()));
        } else if (status_value == 4) {
            return Result::Ok(GameRoomStatus::Closed(()));
        }

        let mut error_msg = ArrayTrait::<felt252>::new();
        error_msg.append('INVALID_STATUS_VALUE');
        
        SyscallResult::Err(error_msg)
    }
}
