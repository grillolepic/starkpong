%lang starknet
from starkware.cairo.common.cairo_builtins import SignatureBuiltin
from starkware.cairo.common.signature import verify_ecdsa_signature

@view
func verify{
    syscall_ptr: felt*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,
}(hash: felt, public_key: felt, signature: (felt, felt)) {
    verify_ecdsa_signature(
        message = hash,
        public_key = public_key,
        signature_r = signature[0],
        signature_s = signature[1],
    );
    return ();
}