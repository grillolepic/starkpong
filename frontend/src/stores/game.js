import { defineStore } from 'pinia';
import { Contract, hash, ec } from 'starknet';
import { useStarknetStore } from './starknet';
import { useGameTokenStore } from './game_token';
import { useGameRoomFactoryStore } from './game_room_factory';
import { useGameRoomStore, GAME_STATUS } from './game_room';
import { joinRoom } from 'trystero';
import { gameRoomFactoryAddress } from '@/helpers/blockchainConstants';

let _starknetStore = null;
let _gameRoomFactoryStore = null;
let _gameRooomStore = null;
let _trysteroRoom = null;
let _sendMessage = null;
let _getMessage = null;

let _initialState = {
    internalStatus: null,

    keys: null,

    checkpoint: null,
    offChainCheckpoint: null,

    gamePeers: [],
    gamePeersOnline: [],

    opponentPublicKey: null,
}

export const INTERNAL_STATUS = {
    ERROR: -1,
    STARTING_SETUP: 0,
    CONNECTING_WITH_PLAYERS: 1,
    SYNCING: 2,
    PLAYING: 3,
}

export const MESSAGE_TYPE = {
    ID: 0,
    SYNC_CHECKPOINT: 1,
    TURN: 2,
    FULL_CHECKPOINT_REQUEST: 3
};

const MASK_250 = BigInt("0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF");

export const useGameStore = defineStore('game', {
    state: () => {
        return { ..._initialState }
    },

    getters: {},

    actions: {
        async startGame() {
            console.log("game: startGame()");
            this.reset();

            if (_gameRooomStore.status != GAME_STATUS.IN_PROGRESS) { return this.gameError("GameRoom not loaded"); }

            this.internalStatus = INTERNAL_STATUS.STARTING_SETUP;

            //01. Load the stored data. If private key data is not found, exit.
            //    Checking is done before, on GameRoom. This should never result in an error.
            let storedCheckpoint = null;
            let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);

            if (storedGameData != null && storedGameData != undefined) {
                storedGameData = JSON.parse(storedGameData);

                if (!("private_key" in storedGameData)) { return this.gameError("Lost Private Key"); }
                try { if ("checkpoint" in storedGameData) { storedCheckpoint = { ...storedGameData.checkpoint }; } } catch (err) { storedCheckpoint = null; }
            } else {
                return this.gameError("Lost Private Key");
            }

            this.keys = {
                privateKey: storedGameData.private_key,
                publicKey: storedGameData.public_key,
                starkKey: storedGameData.stark_key
            };

            //02. If a checkpoint was stored, validate it and load it. Delete if invalid. Redownload if on-chain.
            if (storedCheckpoint != null) {
                try {
                    let storedCheckpointHash = this.getCheckpointHash(storedCheckpoint.data);

                    if (storedCheckpoint.on_chain) {
                        throw new Error("On-Chain checkpoint stored locally. Reset.")
                    } else {
                        /*
                        TODO: VERIFY OFF-CHAIN CHECKPOINT

                        for (let i = 0; i < storedCheckpoint.signatures.length; i++) {
                            if (storedCheckpoint.signatures[i] == null) { throw new Error("Unsigned Checkpoint"); }
                            let signerAddress = utils.verifyMessage(utils.arrayify(storedCheckpointHash), storedCheckpoint.signatures[i]);
                            if (signerAddress != this.currentRoom.offchainPublicKeys[i]) { throw new Error("Wrong Signature"); }
                        }
                        */
                    }

                    this.checkpoint = storedCheckpoint;
                    console.log(` - Found valid checkpoint with turn #${storedCheckpoint.data.turn}`);

                } catch (err) {
                    console.log(" - Found invalid checkpoint. Deleted.");
                    storedCheckpoint = null;
                    delete storedGameData.checkpoint;
                    localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
                }
            }

            //03. Now check if th blockchain state is not further into the game            
            await this.getCheckpoint();

            //04. Connect with other player via WebRTC and exchange signed ids before beginning sync
            if (this.checkpoint != null || this.offChainCheckpoint != null) {

                this.gamePeersOnline = [false, false];
                this.gamePeersOnline[_gameRooomStore.myPlayerNumber] = true;
                this.internalStatus = INTERNAL_STATUS.CONNECTING_WITH_PLAYERS;

                _trysteroRoom = joinRoom({ appId: gameRoomFactoryAddress[_starknetStore.chainId] }, _gameRooomStore.currentGameRoom);
                [_sendMessage, _getMessage] = _trysteroRoom.makeAction('message');
                _getMessage((data, peer) => this.getMessage(data, peer));

                _trysteroRoom.onPeerJoin(async () => this.sendIdToPeers());
                _trysteroRoom.onPeerLeave((peerId) => {
                    if (peerId in this.gamePeers) {
                        console.log(` > Player #${this.gamePeers[peerId].playerNumber} (${this.gamePeers[peerId].address}) left the game`);
                        this.gamePeersOnline[this.gamePeers[peerId].playerNumber] = false;
                        delete this.gamePeers[peerId];
                        this.gameInternalStatus = INTERNAL_STATUS.CONNECTING_WITH_PLAYERS;

                        //TODO: Start a timer to offer partial exit

                    }
                });
            } else {
                this.gameError("No Checkpoint Found");
            }
        },

        async sendIdToPeers() {
            console.log(`game: sendIdToPeers()`);
            if (this.internalStatus == INTERNAL_STATUS.CONNECTING_WITH_PLAYERS) {

                let publicKey = BigInt(this.keys.publicKey);
                let publicKey_0 = publicKey & MASK_250;
                let publicKey_rem = publicKey >> 250n;
                let publicKey_1 = publicKey_rem & MASK_250;
                let publicKey_2 = publicKey_rem >> 250n;

                let ts = Date.now();
                let hashedTimestampAddress = hash.computeHashOnElements([
                    BigInt(_starknetStore.address),
                    BigInt(ts),
                    BigInt(this.keys.starkKey),
                    publicKey_0,
                    publicKey_1,
                    publicKey_2
                ]);

                let signedTimestampAddress = ec.starkCurve.sign(hashedTimestampAddress, this.keys.privateKey);

                _sendMessage({
                    type: MESSAGE_TYPE.ID, data: {
                        address: _starknetStore.address,
                        timestamp: ts,
                        starkKey: this.keys.starkKey,
                        publicKey: this.keys.publicKey,
                        signature: {
                            r: '0x' + signedTimestampAddress.r.toString(16),
                            s: '0x' + signedTimestampAddress.s.toString(16)
                        }
                    }
                });
            }
        },

        async getMessage(message, peerId) {
            console.log(`game: getMessage(${message.type}, ${peerId})`);
            console.log(`internalStatus: ${this.internalStatus}`);

            if (this.internalStatus == INTERNAL_STATUS.CONNECTING_WITH_PLAYERS && message.type == MESSAGE_TYPE.ID && !(peerId in this.gamePeers)) {
                try {
                    let timeDiff = Math.abs(Date.now() - message.data.timestamp);
                    if (timeDiff < 10000) {

                        let receivedAddress = BigInt(message.data.address);
                        let receivedStarkKey = BigInt(message.data.starkKey);
                        let [opponent, opponent_number] = _gameRooomStore.getOpponent();

                        if (receivedAddress == BigInt(opponent.address) && receivedStarkKey == BigInt(opponent.offchain_public_key)) {

                            //Split the public key into parts to reconstruct hash
                            let publicKey = BigInt(message.data.publicKey);
                            let publicKey_0 = publicKey & MASK_250;
                            let publicKey_rem = publicKey >> 250n;
                            let publicKey_1 = publicKey_rem & MASK_250;
                            let publicKey_2 = publicKey_rem >> 250n;

                            let hashedTimestampAddress = hash.computeHashOnElements([
                                BigInt(message.data.address),
                                BigInt(message.data.timestamp),
                                BigInt(message.data.starkKey),
                                publicKey_0,
                                publicKey_1,
                                publicKey_2
                            ]);

                            let signature = new ec.starkCurve.Signature(
                                BigInt(message.data.signature.r),
                                BigInt(message.data.signature.s)
                            );

                            //Verify the signature
                            let verified = ec.starkCurve.verify(signature, hashedTimestampAddress, message.data.publicKey);

                            //Verify that the public key matches the stark key
                            let recoveredStarkKey = BigInt('0x' + message.data.publicKey.slice(4, 68));

                            if (verified && recoveredStarkKey == receivedStarkKey) {

                                this.gamePeers[peerId] = {
                                    playerNumber: opponent_number,
                                    address: message.data.address
                                };

                                this.opponentPublicKey = message.data.publicKey;

                                this.gamePeersOnline[opponent_number] = true;
                                console.log(` > Player #${opponent_number} (${receivedAddress}) joined the game`);

                                this.internalStatus = INTERNAL_STATUS.SYNCING;

                                setTimeout(() => {
                                    if (this.checkpoint == null && this.offChainCheckpoint == null) {
                                        return this.gameError("No Checkpoint Found when ready to sync");
                                    }
                                    _sendMessage({ type: MESSAGE_TYPE.SYNC_CHECKPOINT, data: (this.offChainCheckpoint == null) ? this.checkpoint : this.offChainCheckpoint });
                                }, 1000);

                                this.sendIdToPeers();

                            } else { console.log(` > id rejected because provided signature or public key could not be verified`); }
                        } else { console.log(` > id rejected because address is not from opponent`); }
                    } else { console.log(` > id rejected because timestamp is too old`); }
                } catch (err) {
                    console.log(err);
                }
            } else if (this.internalStatus > INTERNAL_STATUS.CONNECTING_WITH_PLAYERS && message.type == MESSAGE_TYPE.SYNC_CHECKPOINT && peerId in this.gamePeers) {
                try {

                    if (this.checkpoint == null && this.offChainCheckpoint == null) {
                        return this.gameError("No Checkpoint Found when Syncing");
                    }

                    //01. First, check if the hash is accurate
                    let checkpointData = { ...message.data.data };
                    let checkpointHash = this.getCheckpointHash(checkpointData);

                    if (message.data.hash != checkpointHash) {
                        console.log("WRONG HASH");
                        return;
                    }

                    const senderPlayerNumber = this.gamePeers[peerId].playerNumber;
                    let validSignatures = [];

                    if (!message.data.on_chain) {
                        //02. Then, verify all provided signatures
                        for (let i = 0; i < message.data.signatures.length; i++) {
                            if (message.data.signatures[i] != null) {

                                let signature = new ec.starkCurve.Signature(
                                    BigInt(message.data.signatures[i].r),
                                    BigInt(message.data.signatures[i].s)
                                );

                                let public_key = (i == _gameRooomStore.myPlayerNumber) ? this.keys.publicKey : this.opponentPublicKey;

                                //Verify the signature
                                if (ec.starkCurve.verify(signature, checkpointHash, public_key)) {
                                    validSignatures.push(i);
                                } else {
                                    console.log("INVALID SIGNATURE");
                                    return;
                                }
                            }
                        }

                        //03. Finally, verify that whoever sent the message has signed it
                        if (!validSignatures.includes(senderPlayerNumber)) {
                            console.log("NOT SIGNED BY SENDER");
                            return;
                        }

                        console.log(`Player ${senderPlayerNumber} provided a correct hash for off-chain turn ${checkpointData.turn} with ${validSignatures.length} valid signatures`);
                    } else {
                        console.log(`Player ${senderPlayerNumber} provided an unsigned supposedly on-chain turn ${checkpointData.turn} with a correct hash`);
                    }

                    // I. ON-CHAIN CHECKPOINT > MOST RECENT CHECKPOINT (OF ANY KIND)
                    //       - First, obtain the last checkpoint from the blockchain.
                    //       - A. If blockchain's turn == the received turn, finish
                    //       - B. If blockchain's turn < the received turn, ask for retry

                    // II. OFF-CHAIN, PARTIALLY SIGNED CHECKPOINT > LAST CHECKPOINT (BY EXACTLY 1) ** NORMAL STATE-CHANNEL BEHAVIOUR ** 
                    //   - Players start with no full checkpoint, only temp checkpoint with their own signature
                    //   - They send each other their temp checkpoint until they all have all signatures
                    //   - Once fully signed, the temp checkpoint is saved on local storage and 'readyForNextCheckpoint' is set to true
                    //   - A new temp checkpoint is created for turn + 1. All players calculate it separately.
                    //   - They send it partially signed and the whole process repeats

                    // Conflicts and Resolutions:
                    //   III. OFF-CHAIN PARTIALLY SIGNED CHECKPOINT > TEMP CHECKPOINT (BY MORE THAN 1)
                    //       - Request a full state from other players with `sync_checkpoint_full_request`
                    //            - Other players receive this message and send their last full checkpoint
                    //   IV. PARTIALLY SIGNED CHECKPOINT < TEMP CHECKPOINT
                    //       - Some player is behind. Send them the last fully signed checkpoint
                    //   V. FULLY SIGNED, NEWER CHECKPOINT
                    //      - If newer (> tempCheckpoint && >lastCheckpoint), this checkpoint is saved to storage and 'readyForNextCheckpoint' is set to true
                    //      - This could happen as a result of lost storage.

                    /*                    
                    if (message.data.on_chain) {
                        if ((this.offChainCheckpoint != null && checkpointData.turn >= this.gameTempCheckpoint.data.turn) ||
                            (this.gameTempCheckpoint == null && checkpointData.turn >= this.gameLastCheckpoint.data.turn)) {

                            await this.getCheckpointFromBlockchain();

                            if (this.gameLastCheckpoint < checkpointData.turn) {
                                _sendMessage({ type: "sync_checkpoint_full_request", data: null });
                            }
                        }
                    } else {

                        console.log(message.data);

                        if (validSignatures.length < this.currentRoom.numberOfPlayers) {

                            //I. PARTIALLY SIGNED CHECKPOINT == TEMP CHECKPOINT OR EXATLY +1 FROM LAST CHECKPOINT
                            if ((this.gameTempCheckpoint != null && checkpointData.turn == this.gameTempCheckpoint.data.turn) ||
                                (checkpointData.turn == (this.gameLastCheckpoint.data.turn + 1))) {

                                console.log(" -> I. PARTIALLY SIGNED CHECKPOINT == TEMP CHECKPOINT OR EXATLY +1 FROM LAST CHECKPOINT");

                                if (this.gameTempCheckpoint == null || (this.gameTempCheckpoint != null && this.gameLastCheckpoint.data.turn == this.gameTempCheckpoint.data.turn)) {
                                    await this.createOffChainTempCheckpoint(false);
                                }

                                if (this.gameTempCheckpoint != null) {
                                    if (checkpointHash == this.gameTempCheckpoint.hash) {
                                        console.log("   - Adding signatures to my local temp checkpoint");
                                        this.addTempCheckpointSignatures(message.data.signatures);
                                    } else {
                                        console.log("CONSENSUS BROKEN... settle on chain...");
                                        console.log(this.gameTempCheckpoint.data);
                                        console.log(checkpointData);
                                    }
                                } else {
                                    console.log("CONSENSUS BROKEN... settle on chain...");
                                }

                                //NEW CASE: RECEIVED PARTIAL CHECKPOINT WHEN PLAYER HAS FULLY SIGNED CHECKPOINT
                            } else if (checkpointData.turn == this.gameLastCheckpoint.data.turn) {

                                console.log(" -> Ib. PARTIAL CHECKPOINT == LAST FULLY SIGNED CHECKPOINT");
                                _sendMessage({ type: "sync_checkpoint", data: this.gameLastCheckpoint });

                                //II. PARTIALLY SIGNED CHECKPOINT > TEMP CHECKPOINT (BY MORE THAN 1)
                            } else if ((this.gameTempCheckpoint != null && checkpointData.turn > this.gameTempCheckpoint.data.turn) ||
                                (checkpointData.turn > this.gameLastCheckpoint.data.turn)) {

                                console.log(" -> II. PARTIALLY SIGNED CHECKPOINT > TEMP CHECKPOINT (BY MORE THAN 1)");

                                await this.getCheckpointFromBlockchain();

                                console.log("   - Finished requesting turn from blockchain...");

                                if (this.gameTempCheckpoint != null) {

                                    console.log(`   My temp: ${this.gameTempCheckpoint.data.turn}, Received: ${checkpointData.turn}`);

                                    if (checkpointData.turn == this.gameTempCheckpoint.data.turn) {
                                        if (checkpointHash == this.gameTempCheckpoint.hash) {
                                            this.addTempCheckpointSignatures(message.data.signatures);
                                        }
                                    } else if (checkpointData.turn < this.gameTempCheckpoint.data.turn) {
                                        _sendMessage({ type: "sync_checkpoint", data: this.gameTempCheckpoint });
                                    }
                                } else {
                                    console.log("   - Requesting full checkpoint...");
                                    _sendMessage({ type: "sync_checkpoint_full_request", data: null });
                                }

                                //III. PARTIALLY SIGNED CHECKPOINT < TEMP CHECKPOINT
                            } else if ((this.gameTempCheckpoint != null && checkpointData.turn < this.gameTempCheckpoint.data.turn) ||
                                (checkpointData.turn < this.gameLastCheckpoint.data.turn)) {

                                console.log(" -> III. PARTIALLY SIGNED CHECKPOINT < TEMP CHECKPOINT");

                                if (this.gameLastCheckpoint != null) {
                                    _sendMessage({ type: "sync_checkpoint", data: this.gameLastCheckpoint });
                                }
                            }

                            //IV. FULLY SIGNED, NEWER CHECKPOINT
                        } else if ((validSignatures.length == this.currentRoom.numberOfPlayers) && (
                            (this.gameLastCheckpoint == null) ||
                            (this.gameTempCheckpoint != null && checkpointData.turn >= this.gameTempCheckpoint.data.turn) ||
                            (this.gameLastCheckpoint != null && checkpointData.turn > this.gameLastCheckpoint.data.turn))) {

                            console.log(" -> IV. FULLY SIGNED, NEWER CHECKPOINT");


                            let storedGameData = this.getLocalStorage();
                            let _newGameLastCheckpoint = JSON.parse(JSON.stringify(message.data));
                            storedGameData.checkpoint = _newGameLastCheckpoint;
                            localStorage.setItem(this.localKeyGameRoom, JSON.stringify(storedGameData));
                            this.gameLastCheckpoint = _newGameLastCheckpoint;
                            if (this.gameTempCheckpoint != null && (this.gameTempCheckpoint.data.turn <= this.gameLastCheckpoint.data.turn)) {
                                this.gameTempCheckpoint = null;
                            }

                        } else {
                            //console.log("WTF");
                        }
                    }
                */
                } catch (err) {
                    console.log(err);
                    this.gameError("Error syncing chackpoints");
                }

            } else if (message.type == MESSAGE_TYPE.TURN) {


            } else if (message.type == MESSAGE_TYPE.FULL_CHECKPOINT_REQUEST) {
                setTimeout(() => {
                    if (this.checkpoint != null) {
                        _sendMessage({ type: MESSAGE_TYPE.SYNC_CHECKPOINT, data: this.checkpoint });
                    }
                    if (this.offChainCheckpoint != null) {
                        _sendMessage({ type: MESSAGE_TYPE.SYNC_CHECKPOINT, data: this.offChainCheckpoint });
                    }
                }, 1000);
            }
        },

        async getCheckpoint() {
            let current_state = await _gameRooomStore.getGameState(true);

            if (this.checkpoint == null || this.checkpoint.data.turn < current_state.turn ||
                (this.checkpoint.data.turn == current_state[0].turn && !this.checkpoint.on_chain)) {

                let checkpoint_hash = this.getCheckpointHash(current_state);
                let newCheckpoint = {
                    data: { ...current_state },
                    hash: checkpoint_hash,
                    on_chain: true
                };

                //Save the latest checkpoint to local storage
                let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                if (storedGameData != null && storedGameData != undefined) {
                    storedGameData = JSON.parse(storedGameData);
                } else {
                    throw new Error("No local game data found");
                }
                storedGameData.checkpoint = newCheckpoint;
                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));

                this.$patch({
                    checkpoint: newCheckpoint,
                    offChainCheckpoint: null
                });
                console.log("       - Created new On-Chain Checkpoint");

                /*
                TODO: SYNC CHECKPOINT WITH OTHER PLAYER
                if (this.gameInternalStatus == 2) {
                    _sendMessage({type: "sync_checkpoint", data: this.gameLastCheckpoint});
                }
                */

                //TODO: Check for win condition and change game status???
            }
        },

        stateToArrayOfBigInt(current_state) {
            let state_as_array_of_felts = [];
            state_as_array_of_felts.push(current_state.turn);
            state_as_array_of_felts.push(current_state.score_0);
            state_as_array_of_felts.push(current_state.score_1);

            state_as_array_of_felts.push(current_state.paddle_0.y);
            state_as_array_of_felts.push(current_state.paddle_0.size);
            state_as_array_of_felts.push(current_state.paddle_0.speed);
            state_as_array_of_felts.push(current_state.paddle_0.moving_up ? 1n : 0n);

            state_as_array_of_felts.push(current_state.paddle_1.y);
            state_as_array_of_felts.push(current_state.paddle_1.size);
            state_as_array_of_felts.push(current_state.paddle_1.speed);
            state_as_array_of_felts.push(current_state.paddle_1.moving_up ? 1n : 0n);

            state_as_array_of_felts.push(current_state.ball.x);
            state_as_array_of_felts.push(current_state.ball.y);
            state_as_array_of_felts.push(current_state.ball.size);
            state_as_array_of_felts.push(current_state.ball.speed_x);
            state_as_array_of_felts.push(current_state.ball.speed_y);
            state_as_array_of_felts.push(current_state.ball.moving_up ? 1n : 0n);
            state_as_array_of_felts.push(current_state.ball.moving_left ? 1n : 0n);

            return state_as_array_of_felts;
        },

        getCheckpointHash(state) {
            let state_as_array_of_felts = this.stateToArrayOfBigInt(state);
            return hash.computeHashOnElements(state_as_array_of_felts);
        },

        gameError(message) {
            console.error(message);
            this.reset();
            let routeName = this.$router.currentRoute.value.name;
            if (routeName != "Home") { this.$router.push({ name: 'Home' }); }
            return;
        },

        reset() {
            console.log("game: reset()");
            this.$patch({ ..._initialState });
            if (_starknetStore == null) {
                _starknetStore = useStarknetStore();
                _gameRoomFactoryStore = useGameRoomFactoryStore();
                _gameRooomStore = useGameRoomStore();
            }
            if (_trysteroRoom != null) {
                _trysteroRoom.leave();
                _trysteroRoom = null;
            }
            _sendMessage = null;
            _getMessage = null;
        }
    }
});


