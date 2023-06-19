use starknet::ContractAddress;
use traits::{Into, TryInto};
use option::OptionTrait;
use stark_pong::utils::signature::Signature;

#[abi]
trait ISignatureVerification {
    #[view]
    fn verify(hash: felt252, public_key: felt252, signature: (felt252, felt252));
}

fn external_verify(hash: felt252, public_key: ContractAddress, signatures: Signature) {
    let cairo_0_signature_verification_address: ContractAddress = 0x0090eb31ad0d49d1a1dc446379a74a5a5a40908a7be3838fe93ef5d5a801ef6b.try_into().unwrap();
    let cairo_0_signature_verification_contract = ISignatureVerificationDispatcher {
        contract_address: cairo_0_signature_verification_address
    };
    cairo_0_signature_verification_contract.verify(hash, public_key.into(), (signatures.r, signatures.s));
}