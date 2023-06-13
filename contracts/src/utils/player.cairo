use serde::Serde;
use option::OptionTrait;
use traits::{Into, TryInto};
use result::{ResultTrait, ResultTraitImpl};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};
use starknet::{ContractAddress, Felt252TryIntoContractAddress};

#[derive(Drop)]
struct Player {
    address: ContractAddress,
    offchain_address: ContractAddress,
    score: u8
}

impl StorageAccessPlayerImpl of StorageAccess<Player> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Player) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.address.into());
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8), value.offchain_address.into());
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8), value.score.into());
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Player> {
        let mut address_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8));
        let mut offchain_address_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8));
        let mut score_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 2_u8));
        
        Result::Ok(
            Player {
                address: address_value.unwrap().try_into().expect('CANT_READ_ADDRESS'),
                offchain_address: offchain_address_value.unwrap().try_into().expect('CANT_READ_OFFCHAIN_ADDRESS'),
                score: score_value.unwrap().try_into().expect('CANT_READ_SCORE')
            }
        )
    }
}
