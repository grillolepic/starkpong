use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IGameRoomFactory<TContractState> {
    //View Functions
    fn owner(self: @TContractState) -> ContractAddress;
    fn wager_token_allowed(self: @TContractState, token_address: ContractAddress) -> bool;
    fn current_game_room(self: @TContractState, player: ContractAddress) -> ContractAddress;
    fn last_game_room(self: @TContractState, player: ContractAddress) -> ContractAddress;
    fn game_room_count(self: @TContractState) -> u256;
    fn fee(self: @TContractState) -> u128;

    //Public Functions
    fn update_players_from_game_room(ref self: TContractState, game_room_address: ContractAddress);
    fn create_room(
        ref self: TContractState,
        offchain_public_key: ContractAddress,
        wager_token: ContractAddress,
        wager: u256
    );

    //Game Settings External Functions
    fn set_game_room_classhash(ref self: TContractState, new_game_room_classhash: ClassHash);
    fn set_allowed_wager_token(
        ref self: TContractState, token_address: ContractAddress, allowed: bool
    );

    //Fee Managment External Functions
    fn set_fee(ref self: TContractState, new_fee: u128);
    fn withdraw(self: @TContractState, token_address: ContractAddress);

    //Ownable External Functions
    fn renounce_ownership(ref self: TContractState);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    //Upgradeable External
    fn upgrade(self: @TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
mod GameRoomFactory {
    use super::IGameRoomFactory;
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};
    use stark_pong::game_room::{IGameRoomDispatcher, IGameRoomDispatcherTrait};
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address};
    use stark_pong::utils::player::Player;
    use starknet::syscalls::deploy_syscall;
    use starknet::syscalls::SyscallResult;
    use starknet::replace_class_syscall;
    use zeroable::Zeroable;
    use traits::TryInto;
    use result::ResultTrait;
    use option::OptionTrait;
    use array::ArrayTrait;
    use array::SpanTrait;
    use serde::Serde;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        allowed_wager_token: LegacyMap<ContractAddress, bool>,
        game_room_classhash: ClassHash,
        player_game_room: LegacyMap<ContractAddress, ContractAddress>,
        game_room_count: u256,
        fee: u128
    }

    #[constructor]
    fn constructor(ref self: ContractState, game_room_classhash: ClassHash) {
        let caller: ContractAddress = get_caller_address();
        self._transfer_ownership(caller);
        self.game_room_classhash.write(game_room_classhash);
        self.game_room_count.write(0_u256);
        self.fee.write(0_u128);
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred,
        GameRoomCreated: GameRoomCreated,
        GameRoomUpdated: GameRoomUpdated,
        GameRoomFinished: GameRoomFinished
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct GameRoomCreated {
        #[key]
        game_room: ContractAddress,
        #[key]
        player: ContractAddress,
        wager_token: ContractAddress,
        wager: u256,
        fee: u128
    }

    #[derive(Drop, starknet::Event)]
    struct GameRoomUpdated {
        #[key]
        game_room: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct GameRoomFinished {
        #[key]
        game_room: ContractAddress
    }

    //***********************************************************//
    //                   IMPL CONTRACT LOGIC
    //***********************************************************//

    impl GameRoomFactoryImpl of IGameRoomFactory<ContractState> {
        //***********************************************************//
        //                      VIEW FUNCTIONS       
        //***********************************************************//

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn wager_token_allowed(self: @ContractState, token_address: ContractAddress) -> bool {
            self.allowed_wager_token.read(token_address)
        }

        fn current_game_room(self: @ContractState, player: ContractAddress) -> ContractAddress {
            assert(!player.is_zero(), 'PLAYER_IS_ZERO_ADDRESS');

            let current_game_room_address = self.player_game_room.read(player);

            if (!(current_game_room_address.is_zero())) {
                let current_game_room = IGameRoomDispatcher {
                    contract_address: current_game_room_address
                };
                if (current_game_room.is_active()) {
                    return current_game_room_address;
                }
            }

            Zeroable::zero()
        }

        fn last_game_room(self: @ContractState, player: ContractAddress) -> ContractAddress {
            assert(!player.is_zero(), 'PLAYER_IS_ZERO_ADDRESS');
            self.player_game_room.read(player)
        }

        fn game_room_count(self: @ContractState) -> u256 {
            self.game_room_count.read()
        }

        fn fee(self: @ContractState) -> u128 {
            self.fee.read()
        }

        //***********************************************************//
        //                     PUBLIC FUNCTIONS       
        //***********************************************************//

        fn update_players_from_game_room(
            ref self: ContractState, game_room_address: ContractAddress
        ) {
            let current_game_room = IGameRoomDispatcher { contract_address: game_room_address };
            if (current_game_room.is_active()) {
                let player_0: Player = current_game_room.player(0);
                let player_1: Player = current_game_room.player(1);

                self.player_game_room.write(player_0.address, game_room_address);
                self.player_game_room.write(player_1.address, game_room_address);
            }
        }

        fn create_room(
            ref self: ContractState,
            offchain_public_key: ContractAddress,
            wager_token: ContractAddress,
            wager: u256
        ) {
            let player_address = get_caller_address();

            self._assert_player_can_join_room(player_address);
            self._assert_wager_token_allowed(wager_token);
            self._assert_player_can_wager(player_address, wager_token, wager);

            let new_game_room_address = self
                ._deploy_game_room(player_address, offchain_public_key, wager_token, wager);

            self._send_wager_to_game_room(player_address, wager_token, wager, new_game_room_address);
            self.player_game_room.write(player_address, new_game_room_address);

            self
                .emit(
                    Event::GameRoomCreated(
                        GameRoomCreated {
                            game_room: new_game_room_address,
                            player: player_address,
                            wager_token: wager_token,
                            wager: wager,
                            fee: self.fee.read()
                        }
                    )
                );
        }

        //***********************************************************//
        //             GAME SETTINGS EXTERNAL FUNCTIONS       
        //***********************************************************//

        fn set_game_room_classhash(ref self: ContractState, new_game_room_classhash: ClassHash) {
            self._assert_only_owner();
            self.game_room_classhash.write(new_game_room_classhash);
        }

        fn set_allowed_wager_token(
            ref self: ContractState, token_address: ContractAddress, allowed: bool
        ) {
            self._assert_only_owner();
            self.allowed_wager_token.write(token_address, allowed);
        }

        //***********************************************************//
        //             FEE MANAGMENT EXTERNAL FUNCTIONS        
        //***********************************************************//

        fn set_fee(ref self: ContractState, new_fee: u128) {
            self._assert_only_owner();
            self.fee.write(new_fee);
        }

        fn withdraw(self: @ContractState, token_address: ContractAddress) {
            let contract_address = get_contract_address();
            let token = IERC20Dispatcher { contract_address: token_address };
            let balance = token.balance_of(contract_address);
            assert(token.transfer(self.owner(), balance), 'TOKEN_WITHDRAWAL_FAILED');
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

    //***********************************************************//
    //          INTERNAL GAME ROOM MANAGMENT FUNCTIONS              
    //***********************************************************//

    #[generate_trait]
    impl PrivateMethods of PrivateMethodsTrait {
        fn _assert_player_can_join_room(self: @ContractState, player_address: ContractAddress) {
            assert(
                self.current_game_room(player_address) == Zeroable::zero(),
                'PLAYER_HAS_ACTIVE_GAME_ROOM'
            );
        }

        fn _assert_wager_token_allowed(self: @ContractState, token_address: ContractAddress) {
            assert(self.wager_token_allowed(token_address), 'WAGER_TOKEN_NOT_ALLOWED');
        }

        fn _assert_player_can_wager(
            self: @ContractState,
            player_address: ContractAddress,
            wager_token: ContractAddress,
            wager: u256
        ) {
            if (wager > 0_u256) {
                let game_token = IERC20Dispatcher { contract_address: wager_token };
                let user_balance = game_token.balance_of(player_address);
                assert(user_balance >= wager, 'INSUFFICIENT_BALANCE');

                let user_allowance = game_token.allowance(player_address, get_contract_address());
                assert(user_allowance >= wager, 'INSUFFICIENT_ALLOWANCE');
            }
        }

        fn _deploy_game_room(
            ref self: ContractState,
            player_address: ContractAddress,
            offchain_public_key: ContractAddress,
            wager_token: ContractAddress,
            wager: u256
        ) -> ContractAddress {
            let game_room_classhash = self.game_room_classhash.read();
            let fee = self.fee();

            let mut calldata = ArrayTrait::<felt252>::new();
            get_contract_address().serialize(ref calldata);
            player_address.serialize(ref calldata);
            offchain_public_key.serialize(ref calldata);
            wager_token.serialize(ref calldata);
            wager.serialize(ref calldata);
            fee.serialize(ref calldata);

            let game_room_count = self.game_room_count.read();

            let deployed_contract = deploy_syscall(
                self.game_room_classhash.read(),
                game_room_count.try_into().unwrap(),
                calldata.span(),
                false
            );

            assert(deployed_contract.is_ok(), 'DEPLOYMENT_FAILED');

            self.game_room_count.write(game_room_count + 1_u256);

            let (new_contract_address, _) = deployed_contract.unwrap();
            new_contract_address
        }

        fn _send_wager_to_game_room(
            self: @ContractState,
            player_address: ContractAddress,
            wager_token: ContractAddress,
            wager: u256,
            game_room_address: ContractAddress
        ) {
            if (wager > 0_u256) {
                let game_token = IERC20Dispatcher { contract_address: wager_token };
                assert(
                    game_token.transfer_from(player_address, game_room_address, wager),
                    'WAGER_TRANSFER_FAILED'
                );
            }
        }
    }
}
