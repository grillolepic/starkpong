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

    checkpoint: null,    //The last on-chain state or a double signed off-chain state
    turns: [],           //Signed turns since checkpoint
    currentState: null,  //Calculated off-chain state (checkpoint + turns)

    gamePeers: [],
    gamePeersOnline: [],
}

export const INTERNAL_STATUS = {
    ERROR: -1,
    STARTING_SETUP: 0,
    CONNECTING_WITH_PLAYERS: 1,
    SYNCING: 2,
    PLAYING: 3,
}

export const MESSAGE_TYPE = {
    ID: 0,       //A message carrying identifications for players to handshake at the beginning
    SYNC: 1,     //A message carrying latest checkpoint and turns, for player to sync on start
    TURN: 2,     //A message carrying a single turn
    SYNC_REQ: 3, //A message requesting full sync information
    SYNC_OK: 4   //A message confirming sync finished
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

            let storedCheckpoint = null;
            let storedTurns = [];
            let opponentPublicKey = null;
            let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);

            if (storedGameData != null && storedGameData != undefined) {
                storedGameData = JSON.parse(storedGameData);
                if (!("private_key" in storedGameData)) { return this.gameError("Lost Private Key"); }
                try { if ("checkpoint" in storedGameData) { storedCheckpoint = { ...storedGameData.checkpoint }; } } catch (err) { storedCheckpoint = null; }
                try { if ("turns" in storedGameData) { storedTurns = [...storedGameData.turns]; } } catch (err) { storedTurns = []; }
                if ("opponent_public_key" in storedGameData) { opponentPublicKey = storedGameData.opponent_public_key; }
            } else {
                return this.gameError("Lost Private Key");
            }

            this.keys = {
                privateKey: storedGameData.private_key,
                publicKey: storedGameData.public_key,
                starkKey: storedGameData.stark_key,
                opponentPublicKey: opponentPublicKey
            };

            //02. If turns were stored, validate them and load them. Delete them if invalid.
            if (storedTurns.length > 0) {

                //TODO: Load signed turns
            }

            //03. If a checkpoint was stored, validate it and load it. Delete if invalid. Redownload if on-chain.
            if (storedCheckpoint != null) {
                try {
                    let storedCheckpointHash = this.getCheckpointHash(storedCheckpoint.data);

                    if (storedCheckpoint.on_chain) {
                        throw new Error("On-Chain checkpoint stored locally. Reset.")
                    } else {
                        if (storedCheckpoint.hash != storedCheckpointHash) {
                            throw new Error("Wrong checkpoint hash");
                        }

                        if (storedCheckpoint.signatures.length == 2) {
                            for (let i = 0; i < 2; i++) {
                                if (storedCheckpoint.signatures[i] == null) { throw new Error("Unsigned Checkpoint"); }

                                let signature = new ec.starkCurve.Signature(
                                    BigInt(storedCheckpoint.signatures[i].r),
                                    BigInt(storedCheckpoint.signatures[i].s)
                                );

                                let public_key = (i == _gameRooomStore.myPlayerNumber) ? this.keys.publicKey : this.keys.opponentPublicKey;
                                if (public_key == null || public_key == undefined) {
                                    throw new Error("Missing public key for signature verification");
                                }

                                //Verify the signature
                                if (!ec.starkCurve.verify(signature, storedCheckpointHash, public_key)) {
                                    throw new Error("Invalid checkpoint signature");
                                }
                            }
                        } else {
                            throw new Error("Invalid checkpoint signatures");
                        }
                    }

                    this.checkpoint = storedCheckpoint;
                    console.log(` - Found valid checkpoint with turn #${storedCheckpoint.data.turn}`);

                } catch (err) {
                    console.log(" - Found invalid or on-chain checkpoint. Deleted.");
                    storedCheckpoint = null;
                    delete storedGameData.checkpoint;
                    localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
                }
            }

            //04. Now check if th blockchain state is not further into the game            
            await this.getCheckpointFromBlockchain();

            //05. Recalculate the current state in case the checkpoint wasn't updated
            this.recalculateCurrentState();

            //06. Connect with other player via WebRTC and exchange signed ids before beginning sync
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
                        this.internalStatus = INTERNAL_STATUS.CONNECTING_WITH_PLAYERS;

                        //TODO: Start a timer to offer partial exit

                    }
                });
            } else {
                this.gameError("No Checkpoint Found or Downloaded");
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

                                this.keys.opponentPublicKey = message.data.publicKey;

                                //Save the opponentsPublicKey in the local storage
                                //This allows to verify checkpoints on start
                                let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                                if (storedGameData != null && storedGameData != undefined) {
                                    storedGameData = JSON.parse(storedGameData);
                                    storedGameData.opponent_public_key = message.data.publicKey;
                                }
                                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));

                                //Make the player online
                                this.gamePeersOnline[opponent_number] = true;
                                console.log(` > Player #${opponent_number} (${receivedAddress}) joined the game`);

                                this.internalStatus = INTERNAL_STATUS.SYNCING;

                                setTimeout(() => {
                                    if (this.checkpoint == null || this.turns == null) {
                                        return this.gameError("No Checkpoint or Turns found when ready to sync");
                                    }
                                    _sendMessage({
                                        type: MESSAGE_TYPE.SYNC,
                                        data: {
                                            checkpoint: { ...this.checkpoint },
                                            turns: [...this.turns]
                                        }
                                    });
                                }, 1000);

                                this.sendIdToPeers();

                            } else { console.log(` > id rejected because provided signature or public key could not be verified`); }
                        } else { console.log(` > id rejected because address is not from opponent`); }
                    } else { console.log(` > id rejected because timestamp is too old`); }
                } catch (err) {
                    console.log(err);
                }
            } else if (this.internalStatus > INTERNAL_STATUS.CONNECTING_WITH_PLAYERS && message.type == MESSAGE_TYPE.SYNC && peerId in this.gamePeers) {
                
                const peerPlayerNumber = this.gamePeers[peerId].playerNumber;

                try {

                    if (this.checkpoint == null && this.offChainCheckpoint == null) {
                        return this.gameError("No Checkpoint Found when Syncing");
                    }

                    const CHECKPOINT = { ...message.data.checkpoint };
                    const TURNS = [...message.data.turns];

                    //01. First, check if the checkpoint hash is valid
                    let checkpointHash = this.getCheckpointHash(CHECKPOINT.data);

                    if (CHECKPOINT.hash != checkpointHash) {
                        return console.log("WRONG HASH");
                    }

                    let validSignatures = [];

                    if (!CHECKPOINT.on_chain) {
                        //02. Verify all provided signatures if the checkpoint is off-chain
                        if (CHECKPOINT.signatures.length == 2) {
                            for (let i = 0; i < 2; i++) {
                                if (CHECKPOINT.signatures[i] != null) {

                                    let signature = new ec.starkCurve.Signature(
                                        BigInt(CHECKPOINT.signatures[i].r),
                                        BigInt(CHECKPOINT.signatures[i].s)
                                    );

                                    let public_key = (i == peerPlayerNumber) ? this.keys.opponentPublicKey : this.keys.publicKey;

                                    //Verify the signature
                                    if (ec.starkCurve.verify(signature, checkpointHash, public_key)) {
                                        validSignatures.push(i);
                                    } else {
                                        console.log("INVALID SIGNATURE");
                                        return;
                                    }
                                }
                            }
                        }

                        //03. Finally, verify that whoever sent the message has signed it
                        if (!validSignatures.includes(peerPlayerNumber)) {
                            console.log("NOT SIGNED BY SENDER");
                            return;
                        }

                        console.log(`Player #${peerPlayerNumber} provided a correct hash for off-chain turn ${CHECKPOINT.data.turn} with ${validSignatures.length} valid signatures`);
                    } else {
                        console.log(`Player #${peerPlayerNumber} provided an unsigned supposedly on-chain turn ${CHECKPOINT.data.turn} with a correct hash`);
                    }

                    //04. Now verify the provided turns (TODO)
                    for (let i = 0; i < TURNS.length; i++) {
                        //ALL VALID, MISSING TURNS > CHECKPOINT TURN ARE ADDED TO THE turns Array
                    }

                    this.recalculateCurrentState();

                    //SYNC THE CHECKPOIMNT
                    //This can happen in a few different ways:

                    // I. ON-CHAIN, UNSIGNED CHECKPOINT > LOCAL CHECKPOINT
                    // This happens if someone updates the checkpoint on-chain...
                    //    - First, obtain the last checkpoint from the blockchain.
                    //    - A. If blockchain's turn == the received turn, finish
                    //    - B. If blockchain's turn < the received turn, ask for retry

                    // II. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND <= LOCAL LAST TURN
                    // This happens regularly to sync middle game positions while game continues to be played
                    // The player must verify the state is ok (from checkpoint + turns), then sign it and send it back
                    // He stores the new doubly signed checkpoint on localStorage

                    // Conflicts and Resolutions:
                    //   III. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND > LOCAL LAST TURN
                    //        - Request a full state from other players
                    //        - Other players receive this message and send the required data to reconstuct the checkpoint
                    //   IV. PARTIALLY SIGNED CHECKPOINT <= LOCAL CHECKPOINT
                    //       - Opponent is somehow behind. Send them the latest checkpoint and turns.
                    //   V. FULLY SIGNED, NEWER CHECKPOINT
                    //      - Save to localStorage directly
                    //      - This could happen as a result of lost storage.


                    // I. ON-CHAIN, UNSIGNED CHECKPOINT > LOCAL CHECKPOINT
                    if (CHECKPOINT.on_chain) {
                        if ((CHECKPOINT.data.turn >= this.checkpoint.data.turn)) {
                            await this.getCheckpointFromBlockchain();
                            if (this.checkpoint < CHECKPOINT.data.turn) {
                                return _sendMessage({ type: MESSAGE_TYPE.SYNC_REQ, data: null });
                            }
                        }
                    } else {
                        if (validSignatures.length == 2) {
                            //V. FULLY SIGNED, NEWER CHECKPOINT
                            if (CHECKPOINT.data.turn > this.checkpoint.data.turn) {
                                this.checkpoint = { ...CHECKPOINT };

                                let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                                if (storedGameData != null && storedGameData != undefined) {
                                    storedGameData = JSON.parse(storedGameData);
                                } else {
                                    this.gameError("No stored game data found when syncing");
                                }
                                storedGameData.checkpoint = { ...CHECKPOINT };
                                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
                            }
                        } else {

                            //IV. PARTIALLY SIGNED CHECKPOINT < LOCAL CHECKPOINT
                            if (CHECKPOINT.data.turn <= this.checkpoint.data.turn) {
                                return _sendMessage({
                                    type: MESSAGE_TYPE.SYNC,
                                    data: {
                                        checkpoint: { ...this.checkpoint },
                                        turns: [...this.turns]
                                    }
                                });
                            } else if (CHECKPOINT.data.turn > this.checkpoint.data.turn) {

                                // II. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND <= LOCAL LAST TURN
                                if (CHECKPOINT.data.turn <= this.currentState.turn) {

                                    //TODO: Verify that the checkpoint on that turn is correct
                                    let is_valid = true;

                                    if (is_valid) {
                                        //Sign the checkpoint hash
                                        let signature = ec.starkCurve.sign(checkpointHash, this.keys.privateKey);

                                        this.CHECKPOINT.signatures[_gameRooomStore.myPlayerNumber] = {
                                            r: signature.r.toString(),
                                            s: signature.s.toString()
                                        };

                                        this.checkpoint = { ...CHECKPOINT };
                                        this.recalculateCurrentState();

                                        let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                                        if (storedGameData != null && storedGameData != undefined) {
                                            storedGameData = JSON.parse(storedGameData);
                                        } else {
                                            this.gameError("No stored game data found when syncing");
                                        }
                                        storedGameData.checkpoint = { ...CHECKPOINT };
                                        localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));

                                        //Send the checkpoint with both signatures
                                        _sendMessage({
                                            type: MESSAGE_TYPE.SYNC,
                                            data: {
                                                checkpoint: { ...this.checkpoint },
                                                turns: [...this.turns]
                                            }
                                        });

                                    } else {
                                        //Send the correct checkpoit with only your signature
                                        //TODO
                                    }

                                    // III. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND > LOCAL LAST TURN
                                } else {
                                    return _sendMessage({ type: MESSAGE_TYPE.SYNC_REQ, data: null });
                                }
                            }
                        }
                    }

                    this.recalculateCurrentState();
                    _sendMessage({ type: MESSAGE_TYPE.SYNC_OK, data: this.currentState.turn });

                } catch (err) {
                    console.error(err);
                    //this.gameError("Error syncing checkpoints");
                }
            } else if (this.internalStatus == INTERNAL_STATUS.SYNCING && message.type == MESSAGE_TYPE.SYNC_OK) {
                
                if (message.data == this.currentState.turn) {
                    _sendMessage({ type: MESSAGE_TYPE.SYNC_OK, data: this.currentState.turn });
                    this.internalStatus = INTERNAL_STATUS.PLAYING;
                }
            
            } else if (message.type == MESSAGE_TYPE.TURN) {


            } else if (message.type == MESSAGE_TYPE.SYNC_REQ) {
                setTimeout(() => {
                    if (this.checkpoint != null) {
                        _sendMessage({ type: MESSAGE_TYPE.SYNC, data: this.checkpoint });
                    }
                    if (this.offChainCheckpoint != null) {
                        _sendMessage({ type: MESSAGE_TYPE.SYNC, data: this.offChainCheckpoint });
                    }
                }, 1000);
            }
        },

        async getCheckpointFromBlockchain() {
            let current_state_on_chain = await _gameRooomStore.getGameState(true);

            if (this.checkpoint == null || this.checkpoint.data.turn < current_state_on_chain.turn ||
                (this.checkpoint.data.turn == current_state_on_chain.turn && !this.checkpoint.on_chain)) {

                let checkpoint_hash = this.getCheckpointHash(current_state_on_chain);
                let newCheckpoint = {
                    data: { ...current_state_on_chain },
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

                this.checkpoint = newCheckpoint;

                console.log("  - Created new On-Chain Checkpoint");

                this.recalculateCurrentState();

                if (this.gameInternalStatus == INTERNAL_STATUS.SYNCING || this.gameInternalStatus == INTERNAL_STATUS.PLAYING) {
                    _sendMessage({type: MESSAGE_TYPE.SYNC, data: this.checkpoint});
                }

                this.recalculateCurrentState();
            }
        },

        recalculateCurrentState() {
            //TODO: Delete turns with # < checkpoint
            //TODO: Update current state with remaining turns
            if (this.checkpoint != null) {
                this.currentState = this.checkpoint.data;
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


