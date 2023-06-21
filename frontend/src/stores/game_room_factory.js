import { defineStore } from 'pinia';
import { Contract } from 'starknet';
import { useStarknetStore } from './starknet';
import { useGameTokenStore } from './game_token';
import {
    gameRoomFactoryAddress
} from '@/helpers/blockchainConstants';

import GAME_ROOM_FACTORY_ABI from '@/stores/abi/GameRoomFactory.json' assert { type: 'json' };

let _starknetStore = null;
let _gameTokenStore = null;
let _gameRoomFactoryContract = null;

let _initialState = {
    loadingGameRoom: true,
    currentGameRoom: null
}

export const useGameRoomFactoryStore = defineStore('game_room_factory', {
    state: () => {
        return { ..._initialState }
    },

    getters: {},

    actions: {
        async init() {
            console.log('game_token_factory: init()');
            _starknetStore = useStarknetStore();
            _gameTokenStore = useGameTokenStore();
        },

        loggedIn() {
            console.log('game_token_factory: loggedIn()');
            if (_starknetStore.isStarknetReady) {
                _gameRoomFactoryContract = new Contract(GAME_ROOM_FACTORY_ABI, gameRoomFactoryAddress[_starknetStore.chainId], _starknetStore.account);
                this.updateGameRoom();
            }
        },

        async updateGameRoom() {
            console.log('game_token_factory: updateGameRoom()');
            if (!_starknetStore.isStarknetReady) {
                return this.$patch({
                    loadingGameRoom: true,
                    currentGameRoom: null
                });
            }

            let current_game_room = await _gameRoomFactoryContract.current_game_room(_starknetStore.address);
            if (current_game_room == 0n) {
                return this.$patch({
                    loadingGameRoom: false,
                    currentGameRoom: null
                });
            } else {
                return this.$patch({
                    loadingGameRoom: false,
                    currentGameRoom: current_game_room
                });
            }
        },

        loggedOut() {
            console.log('game_token_factory: loggedOut()');
            _gameRoomFactoryContract = null;
            this.$patch({ ..._initialState });
            this.initialized = true;
        }
    }
});