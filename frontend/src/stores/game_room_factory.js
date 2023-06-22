import { defineStore } from 'pinia';
import { Contract, stark, ec, encode, hash } from 'starknet';
import { parseEther } from '../helpers/ethereumHelpers';
import { useStarknetStore } from './starknet';
import { useGameTokenStore } from './game_token';
import { useGameRoomStore } from './game_room';
import {
    gameRoomFactoryAddress
} from '@/helpers/blockchainConstants';

import GAME_ROOM_FACTORY_ABI from '@/stores/abi/GameRoomFactory.json' assert { type: 'json' };
import GAME_ROOM_ABI from '@/stores/abi/GameRoom.json' assert { type: 'json' };

let _starknetStore = null;
let _gameTokenStore = null;
let _gameRoomStore = null;
let _gameRoomToJoinTimeout = null;
let _gameRoomFactoryContract = null;

let _initialState = {
    loadingGameRoom: true,
    
    gameRoomToJoin: {
        address: null,
        opponent: null,
        lastInput: 0,
        checking: false,
        wager: null,
        error: null
    }
}

export const useGameRoomFactoryStore = defineStore('game_room_factory', {
    state: () => {
        return { ..._initialState }
    },

    getters: {
        localKey: (_) => hash.computeHashOnElements([BigInt(gameRoomFactoryAddress[_starknetStore.chainId]), BigInt(_starknetStore.address)])
    },

    actions: {
        async init() {
            console.log('game_room_factory: init()');
            _starknetStore = useStarknetStore();
            _gameTokenStore = useGameTokenStore();
            _gameRoomStore = useGameRoomStore();
        },

        loggedIn() {
            console.log('game_room_factory: loggedIn()');
            if (_starknetStore.isStarknetReady) {
                _gameRoomFactoryContract = new Contract(GAME_ROOM_FACTORY_ABI, gameRoomFactoryAddress[_starknetStore.chainId], _starknetStore.account);
                this.updateGameRoom();
            }
        },

        async updateGameRoom() {
            console.log('game_room_factory: updateGameRoom()');
            
            if (!_starknetStore.isStarknetReady) {
                this.loadingGameRoom = true;
                return _gameRoomStore.reset();
            }

            this.loadingGameRoom = true;
            let current_game_room = await _gameRoomFactoryContract.current_game_room(_starknetStore.address);
            
            if (current_game_room == 0n) {
                this.loadingGameRoom = false;
                return _gameRoomStore.reset();
            } else {
                current_game_room = '0x' + current_game_room.toString(16);
                
                let currentPath = this.$router.currentRoute.fullPath;
                if (currentPath != `/rooom/${current_game_room}`) {
                    this.$router.push({ name: 'GameRoom', params: { id: current_game_room } });
                }

                await _gameRoomStore.loadGameRoom(current_game_room);
            }

            this.loadingGameRoom = false;
        },

        async createRoom(wager) {
            console.log(`game_room_factory: createRoom(${wager})`);

            if (!_starknetStore.isStarknetReady) return;

            //Verify that the user has the required balance
            wager = parseEther(wager);
            if (wager > _gameTokenStore.balance) {
                console.error(`Insufficient $PONG balance`);
                return;
            }

            //Verify that the user has no active game room
            await this.updateGameRoom();
            if (_gameRoomStore.currentGameRoom != null) return;

            //Create an offchain KeyPair
            const privateKey = stark.randomAddress();
            const starkKey = ec.starkCurve.getStarkKey(privateKey);
            const publicKey = encode.addHexPrefix(encode.buf2hex(ec.starkCurve.getPublicKey(privateKey, false)));

            localStorage.setItem(this.localKey, JSON.stringify({
                private_key: privateKey,
                stark_key: starkKey,
                public_key: publicKey
            }));

            try {
                let calls = [];

                if (wager > 0n) {
                    calls.push(await _gameTokenStore.tokenContract.populate("approve", [gameRoomFactoryAddress[_starknetStore.chainId], wager]));
                }

                calls.push(await _gameRoomFactoryContract.populate("create_room", [starkKey, wager]));
                if (await _starknetStore.sendTransactions(calls)) {
                    _gameTokenStore.updateBalance();
                    this.updateGameRoom();
                }

            } catch (err) {
                console.log(err);
            }
        },

        updateGameRoomToJoin(gameRoomAddress, instant) {
            console.log(`game_room_factory: updateGameRoomToJoin(${gameRoomAddress}, ${instant})`);

            this.gameRoomToJoin = {
                address: gameRoomAddress,
                lastInput: Date.now(),
                checking: false,
                wager: null,
                opponent: null
            };

            clearTimeout(_gameRoomToJoinTimeout);

            if (instant) {
                this._getGameRoomToJoinInfo();
            } else {
                _gameRoomToJoinTimeout = setTimeout(this._getGameRoomToJoinInfo, 1000);
            }
        },

        async _getGameRoomToJoinInfo() {
            console.log('game_room_factory: _getGameRoomToJoinInfo()');

            let gameRoomToJoinContract = new Contract(GAME_ROOM_ABI, this.gameRoomToJoin.address, _starknetStore.account);

            let result_0 = await gameRoomToJoinContract.is_active();
            console.log("is_active: ", result_0);

            let result_1 = await gameRoomToJoinContract.status();
            console.log("status: ", result_1);

            let result_2 = await gameRoomToJoinContract.game_state();
            console.log("game_state: ", result_2);

            let result_3 = await gameRoomToJoinContract.players();
            console.log("players: ", result_3);

            let result_4 = await gameRoomToJoinContract.wager();
            console.log("wager: ", result_4);

            let result_5 = await gameRoomToJoinContract.random_seed();
            console.log("random_seed: ", result_5);
            
        },

        loggedOut() {
            console.log('game_room_factory: loggedOut()');
            _gameRoomFactoryContract = null;
            this.$patch({ ..._initialState });
            this.initialized = true;
        }
    }
});