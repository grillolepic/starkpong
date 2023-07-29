//WORK IN PROGRESS
// - Following: https://community.starknet.io/t/cairo-1-contract-syntax-is-evolving/94794
// - Extensibility and Components seems unfinished yet

use starknet::ContractAddress;
use zeroable::Zeroable;

#[starknet::contract_state(OwnableState)]
struct OwnableStorage {
   owner: ContractAddress
}

#[starknet::interface]
trait Ownable<TContractState> {
   //External functions
   fn renounce_ownership(ref self: TContractState);
   fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
   
   //View functions
   fn owner(self: @TContractState) -> ContractAddress;

   //Internal functions
   fn _is_owner(self: @TContractState, addr: ContractAddress) -> bool;
}

#[starknet::component]
impl OwnableImpl<TContractState, impl I: GetComponent<TContractState, OwnableState>> of Ownable<TContractState> {
   fn renounce_ownership(ref self: TContractState) {
      //self.component().owner = Zeroable::zero();
   }

   fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress) {
      //self.component().owner = new_owner;
   }

   fn owner(self: @TContractState) -> ContractAddress {
      //self.component_snap().owner.read()
      Zeroable::zero()
   }

   fn _is_owner(self: @TContractState, addr: ContractAddress) -> bool {
      //self.component_snap().owner.read() == addr
      false
   }
}