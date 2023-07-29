#[derive(Drop, Copy, Serde)]
struct Signature {
    r: felt252,
    s: felt252
}