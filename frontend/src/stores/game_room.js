import { defineStore } from 'pinia';
import { Contract } from 'starknet';
import { useStarknetStore } from './starknet';
import { useGameTokenStore } from './game_token';
import { useGameRoomFactoryStore } from './game_room_factory';

import GAME_ROOM_ABI from '@/stores/abi/GameRoom.json' assert { type: 'json' };

let _starknetStore = null;
let _gameTokenStore = null;
let _gameRoomContract = null;
let _gameRoomFactoryStore = null;

let _initialState = {
    currentGameRoom: null,
    loadingGameRoom: true,

    player_0: null,
    player_1: null,
    my_player: null,
    status: null,
    deadline: null,
    past_deadline: null,
    wager: null,
    
    error: null
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
            _gameRoomFactoryStore = useGameRoomFactoryStore();
        },

        async loadGameRoom(game_room_address, is_reload = false) {
            console.log(`game_room: loadGameRoom(${game_room_address}, ${is_reload})`);

            if (!_starknetStore.isStarknetReady) {
                return this.$patch({
                    currentGameRoom: null,
                    loadingGameRoom: true
                });
            }

            if (!is_reload) { this.reset(); }

            this.loadingGameRoom = true;
            this.currentGameRoom = game_room_address;

            try {
                _gameRoomContract = new Contract(GAME_ROOM_ABI, game_room_address, _starknetStore.account);

                let status_response = await _gameRoomContract.status();
                let status = status_response["0"];
                let deadline = Number(status_response["1"]);
                let past_deadline = (deadline <= Math.floor(Date.now() / 1000));

                if (past_deadline) {
                    if (status == 0n || status == 1n || status == 3n) {
                        this.reset(true);
                    }
                } else if (status == 2n || status == 4n) {
                    this.reset(true);
                }

                let player_0_response = await _gameRoomContract.player(0);
                let player_1_response = await _gameRoomContract.player(1);
                let my_player = null;

                if (player_0_response.address == BigInt(_starknetStore.address)) {
                    this.myPlayerNumber = 0;
                    my_player = player_0_response;
                } else if (player_1_response.address == BigInt(_starknetStore.address)) {
                    this.myPlayerNumber = 1;
                    my_player = player_1_response;
                }

                if (my_player == null) {
                    console.error("Player has not joined this room");
                    this.loadingGameRoom = false;
                    return this.$router.push({ name: 'Home' });
                }

                let wager = await _gameRoomContract.wager();

                this.$patch({
                    status: status,
                    deadline: deadline,
                    past_deadline: past_deadline,
                    player_0: player_0_response,
                    player_1: player_1_response,
                    my_player: my_player,
                    wager: wager
                });

                //Obtain the saved private key
                let localData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                if (localData == null || localData == undefined) {
                    this.$patch({
                        loadingGameRoom: false,
                        error: "Offchain private key not found"
                    });
                    return;
                }
                localData = JSON.parse(localData);

                //Verify that the saved private key is correct
                let offchainPlayerKey = '0x' + my_player.offchain_public_key.toString(16);
                
                if (localData.stark_key != offchainPlayerKey) {
                    this.$patch({
                        loadingGameRoom: false,
                        error: "Wrong offchain private key"
                    });
                    return;
                }

                this.redirectFromStatus();

                if (this.status == 0n) {
                    setTimeout(() => this.loadGameRoom(game_room_address, true), 30 * 1000);
                }
                
            } catch (err) {
                console.log(err);
            }

            this.loadingGameRoom = false;
        },

        redirectFromStatus(fromHome = false) {
            let routeName = this.$router.currentRoute.value.name;

            if (this.status == 0n) {
                if (routeName != "GameRoom" && (routeName != "Home" || fromHome)) {
                    this.$router.push({ name: 'GameRoom' });
                }
            } else  if (this.status == 1n) {
                if (routeName != "Game" && (routeName != "Home" || fromHome)) {
                    this.$router.push({ name: 'Game' });
                }
            }
        },

        async closeRoom() {
            console.log(`game_room: closeRoom()`);

            if (_gameRoomContract == null) return;

            if (await _starknetStore.sendTransactions([_gameRoomContract.populate("close_game_room", [])])) {
                _starknetStore.resetTransaction();
                this.updateGameRoom();
            }
        },

        reset(redirect_to_home = false) {
            _gameRoomContract = null;
            this.$patch({ ..._initialState });
            this.initialized = true;

            if (redirect_to_home) {
                let routeName = this.$router.currentRoute.value.name;
                if (routeName == "GameRoom" || routeName == "Game") {
                    this.$router.push({ name: 'Home' });
                }
            }
        }
    }
});