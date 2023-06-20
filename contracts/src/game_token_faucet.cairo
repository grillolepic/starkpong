#[contract]
mod GameTokenFaucet {
    use serde::Serde;
    use zeroable::Zeroable;
    use starknet::replace_class_syscall;
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_block_timestamp, get_contract_address};

    struct Storage {
        _owner: ContractAddress,
        _game_token: ContractAddress,
        _time_between_claims: u64,
        _claim_amount: u256,
        _last_claim: LegacyMap<ContractAddress, u64>
    }

    #[constructor]
    fn constructor(token_address: ContractAddress, time_between_claims: u64, claim_amount: u256) {
        let caller: ContractAddress = get_caller_address();
        _transfer_ownership(caller);
        _game_token::write(token_address);
        _time_between_claims::write(time_between_claims);
        _claim_amount::write(claim_amount);
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    fn OwnershipTransferred(previous_owner: ContractAddress, new_owner: ContractAddress) {}

    #[event]
    fn TokensClaimed(player: ContractAddress, amount: u256) {}

    //***********************************************************//
    //                      VIEW FUNCTIONS
    //***********************************************************//

    #[view]
    fn tokens_left() -> u256 {
        let contract_address = get_contract_address();
        let token_address = _game_token::read();
        let token = IERC20Dispatcher { contract_address: token_address };
        let balance = token.balance_of(contract_address);
        balance
    }

    #[view]
    fn time_until_next_claim(user: ContractAddress) -> u64 {
        let block_timestamp = get_block_timestamp();
        let last_caller_claim = _last_claim::read(user);
        let time_past = block_timestamp - last_caller_claim;
        let needed_time = _time_between_claims::read();
        if time_past >= needed_time {
            0_u64
        } else {
            needed_time - time_past
        }
    }

    #[view]
    fn owner() -> ContractAddress {
        _owner::read()
    }

    //***********************************************************//
    //                      FAUCET CLAIM
    //***********************************************************//

    #[external]
    fn claim() {
        let caller_address = get_caller_address();
        let token_address = _game_token::read();
        let token = IERC20Dispatcher { contract_address: token_address };
        let amount = _claim_amount::read();

        _last_claim::write(caller_address, get_block_timestamp());

        assert(time_until_next_claim(caller_address) == 0_u64, 'ALREADY_CLAIMED');
        assert(token.transfer(caller_address, amount), 'TRNSFER_FAILED');

        TokensClaimed(caller_address, amount);
    }

    //***********************************************************//
    //                FAUCET SETTINGS FOR OWNER     
    //***********************************************************//

    #[external]
    fn set_game_token(new_game_token: ContractAddress) {
        assert_only_owner();
        _game_token::write(new_game_token);
    }

    #[external]
    fn set_time_between_claims(new_time: u64) {
        assert_only_owner();
        _time_between_claims::write(new_time);
    }

    #[external]
    fn set_claim_amount(new_claim_amount: u256) {
        assert_only_owner();
        _claim_amount::write(new_claim_amount);
    }

    #[external]
    fn upgrade(new_class_hash: ClassHash) {
        assert_only_owner();
        replace_class_syscall(new_class_hash);
    }

    //***********************************************************//
    //                CONTRACT OWNERSHIP FUNCTIONS              
    //***********************************************************//

    #[external]
    fn transfer_ownership(new_owner: ContractAddress) {
        assert(!new_owner.is_zero(), 'NEW_OWNER_IS_ZERO');
        assert_only_owner();
        _transfer_ownership(new_owner);
    }

    #[external]
    fn renounce_ownership() {
        assert_only_owner();
        _transfer_ownership(Zeroable::zero());
    }

    fn assert_only_owner() {
        let owner: ContractAddress = _owner::read();
        let caller: ContractAddress = get_caller_address();
        assert(!caller.is_zero(), 'CALLER_IS_ZERO');
        assert(caller == owner, 'NOT_OWNER');
    }

    fn _transfer_ownership(new_owner: ContractAddress) {
        let previous_owner: ContractAddress = _owner::read();
        _owner::write(new_owner);
        OwnershipTransferred(previous_owner, new_owner);
    }

    //***********************************************************//
    //                  WITHDRAW FUNCTIONS          
    //***********************************************************//

    #[external]
    fn withdraw(token_address: ContractAddress) {
        assert_only_owner();
        let contract_address = get_contract_address();
        let owner_address = _owner::read();
        let token = IERC20Dispatcher { contract_address: token_address };
        let balance = token.balance_of(contract_address);

        assert(token.transfer(owner_address, balance), 'TOKEN_TRANSFER_FAILED');
    }

    #[external]
    fn withdraw_game_token() {
        let game_token: ContractAddress = _game_token::read();
        withdraw(game_token);
    }
}

