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
    lastGameRoom: null,

    gameRoomToJoin: {
        address: null,
        opponent: null,
        lastInput: 0,
        checking: true,
        wager: null,
        opponent: null,
        status: null,
        error: null
    },

    gamesPlayed: null
}

export const useGameRoomFactoryStore = defineStore('game_room_factory', {
    state: () => {
        return { ..._initialState }
    },

    getters: {
        localKey: (_) => hash.computeHashOnElements([BigInt(gameRoomFactoryAddress[_starknetStore.chainId]), BigInt(_starknetStore.address)])
    },

    actions: {
        loggedIn() {
            console.log('game_room_factory: loggedIn()');
            _starknetStore = useStarknetStore();
            _gameTokenStore = useGameTokenStore();
            _gameRoomStore = useGameRoomStore();
            
            if (_starknetStore.isStarknetReady) {
                _gameRoomFactoryContract = new Contract(GAME_ROOM_FACTORY_ABI, gameRoomFactoryAddress[_starknetStore.chainId], _starknetStore.account);
                this.updateGameRoom();
            }
        },

        async updateGameRoomCount() {
            console.log('game_room_factory: updateGameRoomCount()');
            let gamesPlayed = await _gameRoomFactoryContract.game_room_count();
            this.gamesPlayed = gamesPlayed;
        },

        async updateGameRoom() {
            console.log('game_room_factory: updateGameRoom()');
            if (_starknetStore == null) {
                _starknetStore = useStarknetStore();
                _gameTokenStore = useGameTokenStore();
                _gameRoomStore = useGameRoomStore();
            }

            if (!_starknetStore.isStarknetReady) {
                this.loadingGameRoom = true;
                return _gameRoomStore.reset();
            }

            if (_gameRoomFactoryContract == null) return;

            this.loadingGameRoom = true;
            let current_game_room = await _gameRoomFactoryContract.current_game_room(_starknetStore.address);

            if (current_game_room == 0n) {
                _gameRoomStore.reset(true);
                
                //Check if the last game room can be withdrawn from
                let last_game_room = await _gameRoomFactoryContract.last_game_room(_starknetStore.address);
                if (last_game_room != 0n) {

                    last_game_room = '0x' + last_game_room.toString(16);

                    //Check if the last game room is still active
                    let lastGameRoomContract = new Contract(GAME_ROOM_ABI, last_game_room, _starknetStore.account);
                    let lastGameRoomStatus = await lastGameRoomContract.status();
                    lastGameRoomStatus = lastGameRoomStatus["0"];

                    if (lastGameRoomStatus == 0n || lastGameRoomStatus == 1n || lastGameRoomStatus == 3n) {
                        this.lastGameRoom = {
                            address: last_game_room,
                            status: lastGameRoomStatus
                        };

                        let routeName = this.$router.currentRoute.value.name;
                        if (routeName != "Home") {
                            this.$router.push({ name: 'Home' });
                        }
                    }
                }
            } else {
                this.lastGameRoom = null;
                current_game_room = '0x' + current_game_room.toString(16);
                await _gameRoomStore.loadGameRoom(current_game_room);
            }

            this.updateGameRoomCount();
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
                    this.updateGameRoom();
                    _gameTokenStore.updateBalance();
                    _starknetStore.resetTransaction();
                }

            } catch (err) {
                console.log(err);
            }
        },

        async joinRoom() {
            console.log(`game_room_factory: joinRoom()`);

            if (!_starknetStore.isStarknetReady) return;

            //Verify that the user has the required balance
            if (this.gameRoomToJoin.wager > _gameTokenStore.balance) {
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

                if (this.gameRoomToJoin.wager > 0n) {
                    calls.push(await _gameTokenStore.tokenContract.populate("approve", [this.gameRoomToJoin.address, this.gameRoomToJoin.wager]));
                }

                let gameRoomToJoinContract = new Contract(GAME_ROOM_ABI, this.gameRoomToJoin.address, _starknetStore.account);

                calls.push(await gameRoomToJoinContract.populate("join_game_room", [starkKey]));
                if (await _starknetStore.sendTransactions(calls)) {
                    this.updateGameRoom();
                    _gameTokenStore.updateBalance();
                    _starknetStore.resetTransaction();
                }

            } catch (err) {
                console.log(err);
            }
        },

        updateGameRoomToJoin(gameRoomAddress, instant) {
            console.log(`game_room_factory: updateGameRoomToJoin(${gameRoomAddress}, ${instant})`);

            if (gameRoomAddress == this.gameRoomToJoin.address) return;

            this.gameRoomToJoin = {
                address: gameRoomAddress,
                lastInput: Date.now(),
                checking: true,
                wager: null,
                opponent: null,
                status: null,
                error: null
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

            try {
                let gameRoomToJoinContract = new Contract(GAME_ROOM_ABI, this.gameRoomToJoin.address, _starknetStore.account);

                this.gameRoomToJoin.checking = true;

                let status_response = await gameRoomToJoinContract.status();
                this.gameRoomToJoin.status = status_response["0"];
                let deadline = status_response["1"];

                if (this.gameRoomToJoin.status == 0n) {

                    if (deadline <= Math.floor(Date.now()/1000)) {
                        this.gameRoomToJoin.checking = false;
                        this.gameRoomToJoin.error = 'Game room is unavailable';
                        return;
                    }
                    
                    let wager_response = await gameRoomToJoinContract.wager();
                    this.gameRoomToJoin.wager = wager_response;

                    let player_0_response = await gameRoomToJoinContract.player(0);
                    if (player_0_response.address != 0n) {
                        this.gameRoomToJoin.opponent = '0x' + player_0_response.address.toString(16);
                    } else {
                        let player_1_response = await gameRoomToJoinContract.player(1);
                        this.gameRoomToJoin.opponent = '0x' + player_1_response.address.toString(16);
                    }

                    this.gameRoomToJoin.checking = false;
                } else {
                    this.gameRoomToJoin.checking = false;
                    this.gameRoomToJoin.error = 'Game room is unavailable';
                }
            } catch (err) {
                console.log(err);
                this.gameRoomToJoin.checking = false;
                this.gameRoomToJoin.error = 'Unknown error';
            }
        },

        resetGameRoomToJoin() {
            console.log(`game_room_factory: resetGameRoomToJoin()`);

            this.gameRoomToJoin = {
                address: '',
                lastInput: Date.now(),
                checking: false,
                wager: null,
                opponent: null,
                status: null,
                error: null
            };

            clearTimeout(_gameRoomToJoinTimeout);
        },

        async exitLastGameRoom() {
            console.log('game_room_factory: exitLastGameRoom()');

            if (this.lastGameRoom == null) return;

            let gameRoomContract = new Contract(GAME_ROOM_ABI, this.lastGameRoom.address, _starknetStore.account);
            let function_name = (this.lastGameRoom.status == 0n || this.lastGameRoom.status == 1n)?"close_game_room":"finish_exit_with_partial_result";

            if (await _starknetStore.sendTransactions([gameRoomContract.populate(function_name, [])])) {
                this.updateGameRoom();
                _gameTokenStore.updateBalance();
                _starknetStore.resetTransaction();
            }
        },

        loggedOut() {
            console.log('game_room_factory: loggedOut()');
            _gameRoomFactoryContract = null;
            this.$patch({ ..._initialState });
        }
    }
});