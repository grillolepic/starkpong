import { defineStore } from 'pinia';
import { Contract, stark, ec, encode, hash, cairo } from 'starknet';
import { parseEther } from '../helpers/ethereumHelpers';
import { useStarknetStore } from './starknet';
import { useGameTokenStore } from './game_token';

import GAME_ROOM_ABI from '@/stores/abi/GameRoom.json' assert { type: 'json' };

let _starknetStore = null;
let _gameTokenStore = null;
let _gameRoomContract = null;

let _initialState = {
    currentGameRoom: null,
    loadingGameRoom: true
}

export const useGameRoomStore = defineStore('game_room', {
    state: () => {
        return { ..._initialState }
    },

    getters: {},

    actions: {
        async init() {
            console.log('game_room: init()');
            _starknetStore = useStarknetStore();
            _gameTokenStore = useGameTokenStore();
        },

        async loadGameRoom(game_room_address) {
            console.log(`game_room: loadGameRoom(${game_room_address})`);
            
            if (!_starknetStore.isStarknetReady) {
                return this.$patch({
                    currentGameRoom: null,
                    loadingGameRoom: true
                });
            }

            this.loadingGameRoom = true;
            this.currentGameRoom = game_room_address;
            
            //TODO!

            this.loadingGameRoom = false;
        },

        reset() {
            _gameRoomContract = null;
            this.$patch({ ..._initialState });
            this.initialized = true;
        }
    }
});