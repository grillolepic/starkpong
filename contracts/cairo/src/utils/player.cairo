use starknet::ContractAddress;
use starknet::StorageAccess;

#[derive(Drop, Copy, Serde, storage_access::StorageAccess)]
struct Player {
    address: ContractAddress,
    offchain_public_key: ContractAddress
}