use core::serde::Serde;
#[contract]
mod GameRoomFactory {
    use stark_pong::game_token::{IERC20Dispatcher, IERC20DispatcherTrait};
    use stark_pong::game_room::{IGameRoomDispatcher, IGameRoomDispatcherTrait};
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_contract_address};
    use starknet::syscalls::deploy_syscall;
    use starknet::syscalls::SyscallResult;
    use zeroable::Zeroable;
    use traits::TryInto;
    use result::ResultTrait;
    use option::OptionTrait;
    use array::ArrayTrait;
    use array::SpanTrait;
    use serde::Serde;

    struct Storage {
        _owner: ContractAddress,
        _game_token: ContractAddress,
        _game_room_classhash: ClassHash,
        _player_game_room: LegacyMap<ContractAddress, ContractAddress>,
        _game_room_count: u256
    }

    #[constructor]
    fn constructor(token: ContractAddress, game_room_classhash: ClassHash) {
        let caller: ContractAddress = get_caller_address();
        _transfer_ownership(caller);
        _game_token::write(token);
        _game_room_count::write(0_u256);
    }

    //***********************************************************//
    //                          EVENTS
    //***********************************************************//

    #[event]
    fn OwnershipTransferred(previous_owner: ContractAddress, new_owner: ContractAddress) {}
    fn GameRoomCreated(game_room: ContractAddress, player: ContractAddress, wager: u256) {}

    //***********************************************************//
    //                      VIEW FUNCTIONS
    //***********************************************************//

    #[view]
    fn owner() -> ContractAddress {
        _owner::read()
    }

    #[view]
    fn game_token() -> ContractAddress {
        _game_token::read()
    }

    #[view]
    fn current_game_room(player: ContractAddress) -> Option<ContractAddress> {
        assert(!player.is_zero(), 'PLAYER_IS_ZERO_ADDRESS');

        let current_game_room_address = _player_game_room::read(player);

        if (!(current_game_room_address.is_zero())) {
            let current_game_room = IGameRoomDispatcher { contract_address: current_game_room_address};
            if (current_game_room.is_active()) {
                return Option::Some((current_game_room_address));
            }
        }

        return Option::None(());
    }

    #[view]
    fn game_room_count() -> u256 {
        _game_room_count::read()
    }

    //***********************************************************//
    //          EXTERNAL GAME ROOM MANAGMENT FUNCTIONS              
    //***********************************************************//

    #[external]
    fn create_room(offchain_address: ContractAddress, wager: u256) {
        let player_address = get_caller_address();

        assert_player_can_join_room(player_address);
        assert_player_can_wager(player_address, wager);

        let new_game_room_address = _deploy_game_room(player_address, offchain_address, wager);

        _send_wager_to_game_room(player_address, wager, new_game_room_address);

        _player_game_room::write(player_address, new_game_room_address);
        GameRoomCreated(player_address, new_game_room_address, wager);
    }

    //***********************************************************//
    //          INTERNAL GAME ROOM MANAGMENT FUNCTIONS              
    //***********************************************************//

    fn assert_player_can_join_room(player_address: ContractAddress) {
        assert(!current_game_room(player_address).is_none(), 'PLAYER_HAS_ACTIVE_GAME_ROOM');
    }

    fn assert_player_can_wager(player_address: ContractAddress, wager: u256) {
        if (wager > 0_u256) {
            let game_token = IERC20Dispatcher { contract_address: _game_token::read() };
            let user_balance = game_token.balance_of(player_address);
            assert(user_balance >= wager, 'INSUFFICIENT_BALANCE');

            let user_allowance = game_token.allowance(player_address, get_contract_address());
            assert(user_allowance >= wager, 'INSUFFICIENT_ALLOWANCE');
        }
    }

    fn _deploy_game_room(player_address: ContractAddress, offchain_address: ContractAddress, wager: u256) -> ContractAddress {
        let game_room_classhash = _game_room_classhash::read();

        let mut calldata = ArrayTrait::<felt252>::new();
        get_contract_address().serialize(ref calldata);
        player_address.serialize(ref calldata);
        offchain_address.serialize(ref calldata);
        wager.serialize(ref calldata);

        let game_room_count = _game_room_count::read();

        let deployed_contract = deploy_syscall(
            _game_room_classhash::read(),
            game_room_count.try_into().unwrap(),
            calldata.span(),
            false
        );

        assert(deployed_contract.is_ok(), 'DEPLOYMENT_FAILED');

        _game_room_count::write(game_room_count + 1_u256);

        let (new_contract_address, _) = deployed_contract.unwrap();
        new_contract_address
    }

    fn _send_wager_to_game_room(player_address: ContractAddress, wager: u256, game_room_address: ContractAddress) {
        if (wager > 0_u256) {
            let game_token = IERC20Dispatcher { contract_address: _game_token::read() };
            assert(game_token.transfer_from(player_address, game_room_address, wager), 'WAGER_TRANSFER_FAILED');
        }
    }

    //***********************************************************//
    //                 OWNER-ONLY GAME SETTINGS
    //***********************************************************//

    #[external]
    fn update_game_room_classhash(new_game_room_classhash: ClassHash) {
        assert_only_owner();
        _game_room_classhash::write(new_game_room_classhash);
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
}