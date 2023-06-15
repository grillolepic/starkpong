use serde::Serde;
use option::OptionTrait;
use traits::{Into, TryInto};
use result::{ResultTrait, ResultTraitImpl};
use starknet::{StorageAccess, StorageBaseAddress, SyscallResult};
use starknet::{storage_read_syscall, storage_write_syscall, storage_address_from_base_and_offset};
use starknet::{ContractAddress, Felt252TryIntoContractAddress};

#[derive(Drop, Serde, Copy)]
struct Signature {
    r: felt252,
    s: felt252
}

impl StorageAccessSignatureImpl of StorageAccess<Signature> {
    fn write(address_domain: u32, base: StorageBaseAddress, value: Signature) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8), value.r);
        storage_write_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8), value.s);
        SyscallResult::Ok(())
    }

    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<Signature> {
        let r_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 0_u8))?;
        let s_value = storage_read_syscall(address_domain, storage_address_from_base_and_offset(base, 1_u8))?;

        Result::Ok(
            Signature {
                r: r_value,
                s: s_value
            }
        )
    }
}
