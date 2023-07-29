use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IGameTokenFaucet<TContractState> {
    //View Functions
    fn owner(self: @TContractState) -> ContractAddress;
    fn tokens_left(self: @TContractState) -> u256;
    fn last_claim(self: @TContractState, user: ContractAddress) -> u64;
    fn time_until_next_claim(self: @TContractState, user: ContractAddress) -> u64;

    //Claim Public Function
    fn claim(ref self: TContractState);

    //Faucet Settings External Function
    fn set_game_token(ref self: TContractState, new_game_token: ContractAddress);
    fn set_time_between_claims(ref self: TContractState, new_time: u64);
    fn set_claim_amount(ref self: TContractState, new_claim_amount: u256);

    //Token Withdrawal External Functions
    fn withdraw(self: @TContractState, token_address: ContractAddress);
    fn withdraw_game_token(self: @TContractState);

    //Ownable External Functions
    fn renounce_ownership(ref self: TContractState);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    //Upgradeable External
    fn upgrade(self: @TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
mod GameTokenFaucet {
    use super::IGameTokenFaucet;
    use serde::Serde;
    use zeroable::Zeroable;
    use starknet::replace_class_syscall;
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_block_timestamp, get_contract_address
    };

    #[storage]
    struct Storage {
        owner: ContractAddress,
        game_token: ContractAddress,
        time_between_claims: u64,
        claim_amount: u256,
        last_claim: LegacyMap<ContractAddress, u64>
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_address: ContractAddress,
        time_between_claims: u64,
        claim_amount: u256
    ) {
        let caller: ContractAddress = get_caller_address();
        self._transfer_ownership(caller);
        self.game_token.write(token_address);
        self.time_between_claims.write(time_between_claims);
        self.claim_amount.write(claim_amount);
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred,
        TokensClaimed: TokensClaimed
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct TokensClaimed {
        #[key]
        player: ContractAddress,
        amount: u256
    }

    impl GameTokenFaucetImpl of IGameTokenFaucet<ContractState> {
        //***********************************************************//
        //                      VIEW FUNCTIONS       
        //***********************************************************//

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn tokens_left(self: @ContractState) -> u256 {
            let contract_address = get_contract_address();
            let token_address = self.game_token.read();
            let token = IERC20Dispatcher { contract_address: token_address };
            let balance = token.balance_of(contract_address);
            balance
        }

        fn last_claim(self: @ContractState, user: ContractAddress) -> u64 {
            self.last_claim.read(user)
        }

        fn time_until_next_claim(self: @ContractState, user: ContractAddress) -> u64 {
            let block_timestamp = get_block_timestamp();
            let last_caller_claim = self.last_claim.read(user);
            let time_past = block_timestamp - last_caller_claim;
            let needed_time = self.time_between_claims.read();
            if time_past >= needed_time {
                0_u64
            } else {
                needed_time - time_past
            }
        }

        //***********************************************************//
        //                          CLAIM
        //***********************************************************//

        fn claim(ref self: ContractState) {
            let player = get_caller_address();
            let token_address = self.game_token.read();
            let token = IERC20Dispatcher { contract_address: token_address };
            let amount = self.claim_amount.read();

            assert(self.time_until_next_claim(player) == 0_u64, 'ALREADY_CLAIMED');
            self.last_claim.write(player, get_block_timestamp());

            assert(token.transfer(player, amount), 'TRNSFER_FAILED');
            self.emit(Event::TokensClaimed(TokensClaimed { player, amount }));
        }

        //***********************************************************//
        //                FAUCET SETTINGS FOR OWNER     
        //***********************************************************//

        fn set_game_token(ref self: ContractState, new_game_token: ContractAddress) {
            self._assert_only_owner();
            self.game_token.write(new_game_token);
        }

        fn set_time_between_claims(ref self: ContractState, new_time: u64) {
            self._assert_only_owner();
            self.time_between_claims.write(new_time);
        }

        fn set_claim_amount(ref self: ContractState, new_claim_amount: u256) {
            self._assert_only_owner();
            self.claim_amount.write(new_claim_amount);
        }

        //***********************************************************//
        //                TOKEN WITHDRAWAL FUNCTIONS          
        //***********************************************************//

        fn withdraw(self: @ContractState, token_address: ContractAddress) {
            let contract_address = get_contract_address();
            let token = IERC20Dispatcher { contract_address: token_address };
            let balance = token.balance_of(contract_address);
            assert(token.transfer(self.owner(), balance), 'TOKEN_WITHDRAWAL_FAILED');
        }

        fn withdraw_game_token(self: @ContractState) {
            let game_token: ContractAddress = self.game_token.read();
            self.withdraw(game_token);
        }

        //***********************************************************//
        //                OWNABLE EXTERNAL FUNCTIONS        
        //***********************************************************//

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            assert(!new_owner.is_zero(), 'NEW_OWNER_IS_ZERO');
            self._assert_only_owner();
            self._transfer_ownership(new_owner);
        }

        fn renounce_ownership(ref self: ContractState) {
            self._assert_only_owner();
            self._transfer_ownership(Zeroable::zero());
        }

        //***********************************************************//
        //             UPGRADEABLE EXTERNAL FUNCTIONS        
        //***********************************************************//

        fn upgrade(self: @ContractState, new_class_hash: ClassHash) {
            self._assert_only_owner();
            replace_class_syscall(new_class_hash);
        }
    }

    //***********************************************************//
    //               INTERNAL OWNABLE FUNCTIONS              
    //***********************************************************//

    #[generate_trait]
    impl PrivateOwnableMethods of PrivateOwnableMethodsTrait {
        fn _assert_only_owner(self: @ContractState) {
            let owner: ContractAddress = self.owner.read();
            let caller: ContractAddress = get_caller_address();
            assert(!caller.is_zero(), 'CALLER_IS_ZERO');
            assert(caller == owner, 'CALLER_IS_NOT_OWNER');
        }

        fn _transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let previous_owner: ContractAddress = self.owner.read();
            self.owner.write(new_owner);

            self
                .emit(
                    Event::OwnershipTransferred(OwnershipTransferred { previous_owner, new_owner })
                );
        }
    }
}

