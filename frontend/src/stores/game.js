import { defineStore } from 'pinia';
import { hash, ec } from 'starknet';
import { useStarknetStore } from './starknet';
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
let _partialExitTimer = null;
let _messageTimer = null;

const TARGET_DISTANCE_BETWEEN_TURNS = 0;
const CHECKPOINT_DISTANCE = 50n;
const OVERSHOOT = 4n;
const TIME_FOR_PARTIAL_EXIT = 3 * 60 * 1000;

let _initialState = {
    internalStatus: null,

    keys: null,

    checkpoint: null,    //The last on-chain state or a double signed off-chain state
    turns: [],           //Signed turns since checkpoint
    currentState: null,  //Calculated off-chain state (checkpoint + turns)

    lastTurnSent: null,
    lastTurnReceived: null,
    pauseBeforeNextTurn: true,
    paused: true,

    keyUp: false,
    keyDown: false,
    currentAction: 1,

    gamePeers: []
}

export const ACTIONS = {
    MOVE_UP: 0,
    NO_MOVE: 1,
    MOVE_DOWN: 2
};

export const INTERNAL_STATUS = {
    ERROR: -1,
    STARTING_SETUP: 0,
    CONNECTING_WITH_PLAYERS: 1,
    SYNCING: 2,
    PLAYING: 3,
    FINISHED: 4
}

export const MESSAGE_TYPE = {
    ID: 0,       //A message carrying identifications for players to handshake at the beginning
    SYNC: 1,     //A message carrying latest checkpoint and turns, for player to sync on start
    TURN: 2,     //A message carrying a single turn
    SYNC_REQ: 3, //A message requesting full sync information
    SYNC_OK: 4   //A message confirming sync finished
};

function printMessageType(id) {
    switch (id) {
        case MESSAGE_TYPE.ID: return "ID";
        case MESSAGE_TYPE.SYNC: return "SYNC";
        case MESSAGE_TYPE.TURN: return "TURN";
        case MESSAGE_TYPE.SYNC_REQ: return "SYNC_REQ";
        case MESSAGE_TYPE.SYNC_OK: return "SYNC_OK";
        default: return "UNKNOWN";
    }
}

function printInternalStatus(id) {
    switch (id) {
        case INTERNAL_STATUS.ERROR: return "ERROR";
        case INTERNAL_STATUS.STARTING_SETUP: return "STARTING_SETUP";
        case INTERNAL_STATUS.CONNECTING_WITH_PLAYERS: return "CONNECTING_WITH_PLAYERS";
        case INTERNAL_STATUS.SYNCING: return "SYNCING";
        case INTERNAL_STATUS.PLAYING: return "PLAYING";
        default: return "UNKNOWN";
    }
}

const MASK_250 = BigInt("0x3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF");

export const useGameStore = defineStore('game', {
    state: () => {
        return JSON.parse(JSON.stringify(_initialState));
    },

    getters: {
        gameStateForScreen: (state) => {
            if (state.currentState == null) return null;
            let convertedState = JSON.parse(JSON.stringify(state.currentState));

            convertedState.paddle_0.y = parseFloat(convertedState.paddle_0.y / 2.0) / 10.0;
            convertedState.paddle_0.size = parseFloat(convertedState.paddle_0.size / 2.0) / 10.0;
            convertedState.paddle_0.speed = parseFloat(convertedState.paddle_0.speed / 2.0) / 10.0;

            convertedState.paddle_1.y = parseFloat(convertedState.paddle_1.y / 2.0) / 10.0;
            convertedState.paddle_1.size = parseFloat(convertedState.paddle_1.size / 2.0) / 10.0;
            convertedState.paddle_1.speed = parseFloat(convertedState.paddle_1.speed / 2.0) / 10.0;

            convertedState.ball.x = parseFloat(convertedState.ball.x / 2.0) / 10.0;
            convertedState.ball.y = parseFloat(convertedState.ball.y / 2.0) / 10.0;
            convertedState.ball.size = parseFloat(convertedState.ball.size / 2.0) / 10.0;
            convertedState.ball.speed_x = parseFloat(convertedState.ball.speed_x / 2.0) / 10.0;
            convertedState.ball.speed_y = parseFloat(convertedState.ball.speed_y / 2.0) / 10.0;

            return convertedState;
        },
        lastTurnSignature: (state) => {
            if (state.turns.length == 0) return ['.', '.'];
            let last_turn = state.turns[state.turns.length - 1];
            return [
                last_turn.signature.r,
                last_turn.signature.s,
            ];
        },
        lastCheckpointSignature: (state) => {
            if (state.checkpoint == null || state.checkpoint.on_chain) return ['.', '.', '.', '.'];
            return [
                state.checkpoint.signatures[0].r,
                state.checkpoint.signatures[0].s,
                state.checkpoint.signatures[1].r,
                state.checkpoint.signatures[1].s
            ];
        }
    },

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
                try { if ("checkpoint" in storedGameData) { storedCheckpoint = JSON.parse(JSON.stringify(storedGameData.checkpoint)); } } catch (err) { storedCheckpoint = null; }
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

            //02. If a checkpoint was stored, validate it and load it. Delete if invalid. Redownload if on-chain.
            if (false && storedCheckpoint != null) {
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

                    this.checkpoint = JSON.parse(JSON.stringify(storedCheckpoint));
                    console.log(` - Found valid checkpoint with turn #${this.checkpoint.turn}`);

                } catch (err) {
                    console.log(" - Found invalid or on-chain checkpoint. Deleted.");
                    storedCheckpoint = null;
                    delete storedGameData.checkpoint;
                    localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
                }
            }

            //03. Now check if th blockchain state is not further into the game            
            await this.getCheckpointFromBlockchain();

            //04. Now process the stored turns. Delete them if < checkpoint, (not sequential?) or if wrong signature.
            if (storedTurns.length > 0) {
                storedTurns.sort((a, b) => { return Number(BigInt(a.turn.turn) - BigInt(b.turn.turn)) });

                let turnsToDelete = [];
                let nextTurn = BigInt(this.checkpoint.data.turn);
                for (let i = 0; i < storedTurns.length; i++) {
                    if (BigInt(storedTurns[i].turn.turn) < nextTurn) {
                        turnsToDelete.push(i);
                        continue;
                    }

                    if (BigInt(storedTurns[i].turn.turn) > nextTurn) {
                        console.error(`Stored turn #${storedTurns[i].turn.turn} is not sequential. Corrupted state!`);
                        turnsToDelete.push(i);
                        continue;
                    }

                    try {
                        //Verify the hash
                        let hashedTurn = ec.starkCurve.pedersen(
                            BigInt(storedTurns[i].turn.turn),
                            BigInt(storedTurns[i].turn.action)
                        );

                        if (storedTurns[i].hash != hashedTurn) {
                            throw new Error(`Wrong hash for turn #${storedTurns[i].turn.turn}`);
                        }

                        //Verify the signature
                        let signature = new ec.starkCurve.Signature(
                            BigInt(storedTurns[i].signature.r),
                            BigInt(storedTurns[i].signature.s)
                        );

                        let player_for_turn = this.playerNumberFromTurn(BigInt(storedTurns[i].turn.turn));

                        let public_key = (player_for_turn == _gameRooomStore.myPlayerNumber) ? this.keys.publicKey : this.keys.opponentPublicKey;
                        if (public_key == null || public_key == undefined) {
                            throw new Error("Missing public key for signature verification");
                        }

                        //Verify the signature
                        if (!ec.starkCurve.verify(signature, hashedTurn, public_key)) {
                            throw new Error(`Invalid turn #${storedTurns[i].turn.turn} signature`);
                        }

                        nextTurn += 1n;
                    } catch (err) {
                        turnsToDelete.push(i);
                        console.error(err);
                    }
                }

                //Delete the invalid turns
                for (let i = turnsToDelete.length - 1; i >= 0; i--) {
                    storedTurns.splice(turnsToDelete[i], 1);
                }

                //Save the turns back to local storage
                storedGameData.turns = [...storedTurns];
                this.turns = [...storedTurns];
                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
            }

            //05. Recalculate the current state in case the checkpoint wasn't updated
            this.recalculateCurrentState();

            //06. Connect with other player via WebRTC and exchange signed ids before beginning sync
            if (this.currentState != null) {
                this.internalStatus = INTERNAL_STATUS.CONNECTING_WITH_PLAYERS;

                if (_partialExitTimer != null) { clearTimeout(_partialExitTimer); }
                _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);

                _trysteroRoom = joinRoom({ appId: gameRoomFactoryAddress[_starknetStore.chainId] }, _gameRooomStore.currentGameRoom);
                [_sendMessage, _getMessage] = _trysteroRoom.makeAction('message');
                _getMessage((data, peer) => this.getMessage(data, peer));

                _trysteroRoom.onPeerJoin(async () => this.sendIdToPeers());
                _trysteroRoom.onPeerLeave((peerId) => {
                    if (peerId in this.gamePeers) {
                        console.log(` > Player #${this.gamePeers[peerId].playerNumber} (${this.gamePeers[peerId].address}) left the game`);
                        delete this.gamePeers[peerId];
                        this.internalStatus = INTERNAL_STATUS.CONNECTING_WITH_PLAYERS;
                        if (_partialExitTimer != null) { clearTimeout(_partialExitTimer); }
                        _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);

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
            console.log(`game: getMessage(${printMessageType(message.type)}, ${peerId})`);
            console.log(`[internalStatus: ${printInternalStatus(this.internalStatus)} | gamePeers: ${JSON.stringify(this.gamePeers)}]`);

            if (message.type == MESSAGE_TYPE.ID && this.internalStatus == INTERNAL_STATUS.CONNECTING_WITH_PLAYERS && !(peerId in this.gamePeers)) {

                console.log(` > Received ID (${peerId})`);

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
                                console.log(` > Player #${opponent_number} (${receivedAddress}) joined the game`);

                                this.internalStatus = INTERNAL_STATUS.SYNCING;

                                //Stop the partial exit timer on syncing
                                if (_partialExitTimer != null) {
                                    clearTimeout(_partialExitTimer);
                                    _partialExitTimer = null;
                                }

                                setTimeout(() => this.sendSync(), 1000);
                                _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);

                                this.sendIdToPeers();

                            } else { console.log(` > id rejected because provided signature or public key could not be verified`); }
                        } else { console.log(` > id rejected because address is not from opponent`); }
                    } else { console.log(` > id rejected because timestamp is too old`); }
                } catch (err) {
                    console.log(err);
                }
            } else if (message.type == MESSAGE_TYPE.SYNC && this.internalStatus > INTERNAL_STATUS.CONNECTING_WITH_PLAYERS && peerId in this.gamePeers) {

                const peerPlayerNumber = this.gamePeers[peerId].playerNumber;

                try {

                    if (this.checkpoint == null) {
                        return this.gameError("No Checkpoint Found when Syncing");
                    }

                    const CHECKPOINT = JSON.parse(JSON.stringify(message.data.checkpoint));
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

                    //04. Now verify the provided turns
                    for (let i = 0; i < TURNS.length; i++) {
                        this.processTurn(TURNS[i]);
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
                        if ((BigInt(CHECKPOINT.data.turn) >= BigInt(this.checkpoint.data.turn))) {
                            await this.getCheckpointFromBlockchain();
                            if (this.checkpoint < CHECKPOINT.data.turn) {
                                this.internalStatus = INTERNAL_STATUS.SYNCING;
                                if (_partialExitTimer != null) { clearTimeout(_partialExitTimer); }
                                _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);
                                return _sendMessage({ type: MESSAGE_TYPE.SYNC_REQ, data: null });
                            }
                        }
                    } else {
                        if (validSignatures.length == 2) {
                            //V. FULLY SIGNED, NEWER CHECKPOINT
                            this.updateCheckpoint(CHECKPOINT);
                        } else {

                            //IV. PARTIALLY SIGNED CHECKPOINT < LOCAL CHECKPOINT
                            if (BigInt(CHECKPOINT.data.turn) <= BigInt(this.checkpoint.data.turn)) {
                                return this.sendSync();
                            } else if (BigInt(CHECKPOINT.data.turn) > BigInt(this.checkpoint.data.turn)) {

                                // II. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND <= LOCAL LAST TURN
                                if (BigInt(CHECKPOINT.data.turn) <= BigInt(this.currentState.turn)) {

                                    let locallyCreatedCheckpoint = this.createPartialCheckpoint(BigInt(CHECKPOINT.data.turn), false);
                                    let is_valid = (locallyCreatedCheckpoint.hash == CHECKPOINT.hash);

                                    if (is_valid) {
                                        //Sign the checkpoint hash
                                        let signature = ec.starkCurve.sign(checkpointHash, this.keys.privateKey);

                                        CHECKPOINT.signatures[_gameRooomStore.myPlayerNumber] =
                                            { ...locallyCreatedCheckpoint.signatures[_gameRooomStore.myPlayerNumber] };

                                        this.updateCheckpoint(CHECKPOINT);

                                        //Send the checkpoint with both signatures
                                        this.sendSync();

                                    } else {
                                        console.error("Received checkpoint seems to be invalid!");
                                        this.createPartialCheckpoint(BigInt(CHECKPOINT.data.turn));
                                    }

                                    // III. PARTIALLY SIGNED CHECKPOINT > LOCAL CHECKPOINT AND > LOCAL LAST TURN
                                } else {
                                    this.internalStatus = INTERNAL_STATUS.SYNCING;
                                    if (_partialExitTimer != null) { clearTimeout(_partialExitTimer); }
                                    _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);
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

                    //Stop the partial exit timer on syncing
                    if (_partialExitTimer != null) {
                        clearTimeout(_partialExitTimer);
                        _partialExitTimer = null;
                    }

                    setTimeout(() => {
                        this.playTurn();
                    }, 2000);
                }

            } else if (message.type == MESSAGE_TYPE.TURN) {
                this.processTurn(message.data);

            } else if (message.type == MESSAGE_TYPE.SYNC_REQ) {
                this.internalStatus = INTERNAL_STATUS.SYNCING;
                if (_partialExitTimer != null) { clearTimeout(_partialExitTimer); }
                _partialExitTimer = setTimeout(() => this.showPartialExit(), TIME_FOR_PARTIAL_EXIT);
                this.sendSync();
            }
        },

        sendSync() {
            console.log(`game: sendSync()`);
            if (this.checkpoint == null || this.turns == null) {
                return this.gameError("No Checkpoint or Turns found when ready to sync");
            }

            console.log(`ABOUT TO SEND CHECKPOINT:`);
            console.log(this.checkpoint);

            _sendMessage({
                type: MESSAGE_TYPE.SYNC,
                data: {
                    checkpoint: JSON.parse(JSON.stringify(this.checkpoint)),
                    turns: [...this.turns]
                }
            });
        },

        handleKeyDown(up) {
            if (this.currentAction == ACTIONS.NO_MOVE) {
                if (up) {
                    this.currentAction = ACTIONS.MOVE_UP;
                } else {
                    this.currentAction = ACTIONS.MOVE_DOWN;
                }
            }
            if (up) {
                this.keyUp = true;
            }
            else {
                this.keyDown = true;
            }
        },

        handleKeyUp(up) {
            if (up) { this.keyUp = false; }
            else { this.keyDown = false; }

            if (!this.keyUp && !this.keyDown) {
                this.currentAction = ACTIONS.NO_MOVE;
            } else {
                if (this.keyUp) {
                    this.currentAction = ACTIONS.MOVE_UP;
                } else {
                    this.currentAction = ACTIONS.MOVE_DOWN;
                }
            }
        },

        async getCheckpointFromBlockchain() {
            console.log(`game: getCheckpointFromBlockchain()`);
            //Obtains the state from the blockchain (data in bigint).
            //Stores it on localStorage (data in string) and updates this.checkpoint (data in bigint) if needed
            //Informs other players and calls recalculateCurrentState()

            let current_state_on_chain = await _gameRooomStore.getGameState(true);

            if (this.checkpoint == null || BigInt(this.checkpoint.data.turn) < BigInt(current_state_on_chain.turn) ||
                (BigInt(this.checkpoint.data.turn) == BigInt(current_state_on_chain.turn) && !this.checkpoint.on_chain)) {

                let checkpoint_hash = this.getCheckpointHash(current_state_on_chain);
                let newCheckpoint = {
                    data: current_state_on_chain,
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
                this.checkpoint = JSON.parse(JSON.stringify(newCheckpoint));

                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));

                console.log("I JUST GOT AN ON-CHAIN CHECKPOINT:");
                console.log(this.checkpoint);

                this.recalculateCurrentState();

                if (this.gameInternalStatus == INTERNAL_STATUS.SYNCING || this.gameInternalStatus == INTERNAL_STATUS.PLAYING) {
                    _sendMessage({ type: MESSAGE_TYPE.SYNC, data: this.checkpoint });
                }
            }
        },

        playerNumberFromTurn(turn) {
            return turn % 2n;
        },

        playTurn() {
            console.log("game: playTurn()");

            let turn_to_play = BigInt(this.currentState.turn);
            let player_number = this.playerNumberFromTurn(turn_to_play);

            console.log(` - Turn to play: ${turn_to_play} - Player number: ${player_number} - My player number: ${_gameRooomStore.myPlayerNumber}`);

            if (this.pauseBeforeNextTurn) {
                console.log(" > PAUSE FOR 5 SECONDS");
                this.pauseBeforeNextTurn = false;
                this.paused = true;
                return setTimeout(this.playTurn, 3000);
            }

            if (player_number == _gameRooomStore.myPlayerNumber) {

                this.paused = false;
                let action = this.currentAction;

                if (this.advance_state(_gameRooomStore.myPlayerNumber, turn_to_play, action)) {
                    let signed_turn = this.signTurn(turn_to_play, action);
                    this.addTurn(signed_turn);

                    console.log(' >>> lastTurnSent:', this.lastTurnSent, 'lastTurnReceived:', this.lastTurnReceived);

                    if (this.lastTurnSent != null && this.lastTurnReceived != null) {
                        let distance = this.lastTurnReceived - this.lastTurnSent;

                        console.log(` - Distance between turns: ${distance}`);
                        if (distance >= TARGET_DISTANCE_BETWEEN_TURNS) {
                            _sendMessage({ type: MESSAGE_TYPE.TURN, data: signed_turn });
                            this.lastTurnSent = Date.now();
                        } else {
                            let waitTime = TARGET_DISTANCE_BETWEEN_TURNS - distance;
                            console.log(`   > Waiting ${waitTime}ms before sending turn`);
                            _messageTimer = setTimeout(() => {
                                _sendMessage({ type: MESSAGE_TYPE.TURN, data: signed_turn });
                                this.lastTurnSent = Date.now();
                            }, waitTime);
                        }
                    } else {
                        _messageTimer = _sendMessage({ type: MESSAGE_TYPE.TURN, data: signed_turn });
                        this.lastTurnSent = Date.now();
                    }
                }
            }
        },

        signTurn(turn, action) {
            console.log(`game: signTurn(${turn}, ${action})`);
            if (this.keys == null || this.currentState == null) {
                return this.gameError("No keys or current state found when signing turn");
            }

            let hashedTurn = ec.starkCurve.pedersen(
                turn,
                action
            );
            let signedTurn = ec.starkCurve.sign(hashedTurn, this.keys.privateKey);

            return {
                turn: {
                    turn: turn.toString(),
                    action: action.toString()
                },
                hash: hashedTurn,
                signature: {
                    r: '0x' + signedTurn.r.toString(16),
                    s: '0x' + signedTurn.s.toString(16)
                }
            };
        },

        advance_state(player, turn, action) {
            console.log(`game: advance_state(${player}, ${turn}, ${action})`);
            let new_state = JSON.parse(JSON.stringify(this.currentState));

            if (BigInt(turn) != BigInt(new_state.turn)) return null;
            if (player != this.playerNumberFromTurn(turn)) return null;

            new_state = this.state_transition(new_state, action);

            if (new_state == null) {
                this.internalStatus = INTERNAL_STATUS.FINISHED;

            } else {
                if (new_state.score_0 != this.currentState.score_0 || new_state.score_1 != this.currentState.score_1) {
                    this.pauseBeforeNextTurn = true;
                }

                this.currentState = new_state;
                console.log(`  - NEW currentState TURN: ${this.currentState.turn}`);
            }

            //Check if this current state needs to be checkpointed
            if (this.internalStatus == INTERNAL_STATUS.PLAYING) {
                if ((BigInt(new_state.turn) > OVERSHOOT)) {
                    let turn_to_check = BigInt(new_state.turn) - OVERSHOOT;

                    if (turn_to_check % CHECKPOINT_DISTANCE == 0n) {
                        if ((BigInt(_gameRooomStore.myPlayerNumber) * CHECKPOINT_DISTANCE) == (turn_to_check % (2n * CHECKPOINT_DISTANCE))) {
                            this.createPartialCheckpoint(turn_to_check);
                        }
                    }
                }
            } else if (this.internalStatus == INTERNAL_STATUS.FINISHED) {
                let turn_to_check = BigInt(this.currentState.turn) - 2n;
                if (BigInt(this.checkpoint.data.turn) < turn_to_check) {
                    if (turn_to_check % CHECKPOINT_DISTANCE == 0n) {
                        if ((BigInt(_gameRooomStore.myPlayerNumber) * CHECKPOINT_DISTANCE) == (turn_to_check % (2n * CHECKPOINT_DISTANCE))) {
                            this.createPartialCheckpoint(turn_to_check);
                        }
                    }
                }
            }

            return true;
        },

        state_transition(state, action) {
            console.log(`game: state_transition(${state}, ${action})`);
            //TODO: STATE TRANSITION FUNCTION
            const SPEED = 100n;
            const MAX_SPEED = 80n;
            const MAX_Y = 12000n;
            const MAX_X = 16000n;
            const PADDLE_HEIGHT = 400n;
            const WINNING_SCORE = 3n;

            //Check if there was a winner
            if (BigInt(state.score_0) >= WINNING_SCORE || BigInt(state.score_1) >= WINNING_SCORE) {
                return null;
            }

            if (BigInt(state.ball.speed_x) == 0n || BigInt(state.ball.speed_y) == 0n) {
                let randomized = this.randomize_ball(BigInt(state.turn));
                state.ball.speed_x = randomized[0].toString();
                state.ball.speed_y = randomized[1].toString();
            }

            //Get the player number for the action
            let playerNumber = this.playerNumberFromTurn(BigInt(state.turn));
            if (playerNumber == 0n) {
                //Calculate the new speed and direction
                if (action == ACTIONS.MOVE_UP) {
                    state.paddle_0.moving_up = true;
                    state.paddle_0.speed = SPEED.toString();
                } else if (action == ACTIONS.MOVE_DOWN) {
                    state.paddle_0.moving_up = false;
                    state.paddle_0.speed = SPEED.toString();
                } else {
                    state.paddle_0.speed = 0n.toString();
                }

                //Now, calculate the new position
                if (BigInt(state.paddle_0.speed) > 0n) {
                    if (state.paddle_0.moving_up) {
                        let MIN_VALUE = BigInt(state.paddle_0.size) / 2n;
                        if (BigInt(state.paddle_0.speed) > (BigInt(state.paddle_0.y) - MIN_VALUE)) {
                            state.paddle_0.y = MIN_VALUE.toString();
                        } else {
                            state.paddle_0.y = (BigInt(state.paddle_0.y) - BigInt(state.paddle_0.speed)).toString();
                        }
                    } else {
                        let MAX_VALUE = MAX_Y - (BigInt(state.paddle_0.size) / 2n);
                        state.paddle_0.y = (BigInt(state.paddle_0.y) + BigInt(state.paddle_0.speed)).toString();
                        if (BigInt(state.paddle_0.y) > MAX_VALUE) {
                            state.paddle_0.y = MAX_VALUE.toString();
                        }
                    }
                }
            } else {
                //Calculate the new speed and direction
                if (action == ACTIONS.MOVE_UP) {
                    state.paddle_1.moving_up = true;
                    state.paddle_1.speed = SPEED.toString();
                } else if (action == ACTIONS.MOVE_DOWN) {
                    state.paddle_1.moving_up = false;
                    state.paddle_1.speed = SPEED.toString();
                } else {
                    state.paddle_1.speed = 0n.toString();
                }

                //Now, calculate the new position
                if (BigInt(state.paddle_1.speed) > 0n) {
                    if (state.paddle_1.moving_up) {
                        let MIN_VALUE = BigInt(state.paddle_1.size) / 2n;
                        if (BigInt(state.paddle_1.speed) > (BigInt(state.paddle_1.y) - MIN_VALUE)) {
                            state.paddle_1.y = MIN_VALUE.toString();
                        } else {
                            state.paddle_1.y = (BigInt(state.paddle_1.y) - BigInt(state.paddle_1.speed)).toString();
                        }
                    } else {
                        let MAX_VALUE = MAX_Y - (BigInt(state.paddle_1.size) / 2n);
                        state.paddle_1.y = (BigInt(state.paddle_1.y) + BigInt(state.paddle_1.speed)).toString();
                        if (BigInt(state.paddle_1.y) > MAX_VALUE) {
                            state.paddle_1.y = MAX_VALUE.toString();
                        }
                    }
                }
            }

            //Calculate the ball position
            if (state.ball.moving_up) {
                let MIN_VALUE = BigInt(state.ball.size) / 2n;
                let distance = BigInt(state.ball.y) - MIN_VALUE;
                if (BigInt(state.ball.speed_y) >= distance) {
                    state.ball.y = (BigInt(state.ball.speed_y) - distance).toString();
                    state.ball.moving_up = false;
                } else {
                    state.ball.y = (BigInt(state.ball.y) - BigInt(state.ball.speed_y)).toString();
                }
            } else {
                let MAX_VALUE = MAX_Y - (BigInt(state.ball.size) / 2n);
                let distance = MAX_VALUE - BigInt(state.ball.y);
                if (BigInt(state.ball.speed_y) >= distance) {
                    state.ball.y = (MAX_VALUE - (BigInt(state.ball.speed_y) - distance)).toString();
                    state.ball.moving_up = true;
                } else {
                    state.ball.y = (BigInt(state.ball.y) + BigInt(state.ball.speed_y)).toString();
                }
            }

            let has_scored_0 = false;
            let has_scored_1 = false;
            let ball_lower_limit = BigInt(state.ball.y) + (BigInt(state.ball.size) / 2n);
            let ball_upper_limit = BigInt(state.ball.y) - (BigInt(state.ball.size) / 2n);
            let paddle_0_lower_limit = BigInt(state.paddle_0.y) + (BigInt(state.paddle_0.size) / 2n);
            let paddle_0_upper_limit = BigInt(state.paddle_0.y) - (BigInt(state.paddle_0.size) / 2n);
            let paddle_1_lower_limit = BigInt(state.paddle_1.y) + (BigInt(state.paddle_1.size) / 2n);
            let paddle_1_upper_limit = BigInt(state.paddle_1.y) - (BigInt(state.paddle_1.size) / 2n);

            if (state.ball.moving_left) {
                let will_bounce = (ball_lower_limit >= paddle_0_upper_limit) && (ball_upper_limit <= paddle_0_lower_limit);
                let MIN_VALUE = PADDLE_HEIGHT + (BigInt(state.ball.size) / 2n);

                if (BigInt(state.ball.x) < MIN_VALUE) {
                    //The ball has already crossed the paddle limit and will score the goal on time
                    if (BigInt(state.ball.speed_x) >= BigInt(state.ball.x)) {
                        //The ball reaches the screen limit in this turn. Change score
                        state.score_1 = (BigInt(state.score_1) + 1n).toString();
                        has_scored_1 = true;
                    } else {
                        //Continue moving the ball
                        state.ball.x = (BigInt(state.ball.x) - BigInt(state.ball.speed_x)).toString();
                    }
                } else {
                    let distance = BigInt(state.ball.x) - MIN_VALUE;

                    if (BigInt(state.ball.speed_x) >= (BigInt(state.ball.x))) {
                        //The ball will reach the screen limit in this turn, but it can still bounce
                        if (will_bounce) {
                            state.ball.x = (MIN_VALUE + BigInt(state.ball.speed_x) - distance).toString();
                            state.ball.moving_left = false;

                            //Calculate the new speed and direction
                            let hit_distance = 0n;
                            if (BigInt(state.ball.y) > BigInt(state.paddle_0.y)) {
                                state.ball.moving_up = false;
                                hit_distance = BigInt(state.ball.y) - BigInt(state.paddle_0.y);
                            } else {
                                state.ball.moving_up = true;
                                hit_distance = BigInt(state.paddle_0.y) - BigInt(state.ball.y);
                            }

                            let hit_percentage = 50n + ((hit_distance * 50n) / (BigInt(state.paddle_0.size) / 2n));
                            state.ball.speed_y = ((hit_percentage * BigInt(MAX_SPEED)) / 100n).toString();

                        } else {
                            //The ball will not bounce, so the ball will reach 0. Change score.
                            state.score_1 = (BigInt(state.score_1) + 1n).toString();
                            has_scored_1 = true;
                        }
                    } else {
                        if ((BigInt(state.ball.x) - BigInt(state.ball.speed_x)) < MIN_VALUE) {
                            //The ball will cross the paddle limit in this turn, but it can still bounce
                            if (will_bounce) {
                                state.ball.x = (MIN_VALUE + BigInt(state.ball.speed_x) - distance).toString();
                                state.ball.moving_left = false;

                                //Calculate the new speed and direction
                                let hit_distance = 0n;
                                if (BigInt(state.ball.y) > BigInt(state.paddle_0.y)) {
                                    state.ball.moving_up = false;
                                    hit_distance = BigInt(state.ball.y) - BigInt(state.paddle_0.y);
                                } else {
                                    state.ball.moving_up = true;
                                    hit_distance = BigInt(state.paddle_0.y) - BigInt(state.ball.y);
                                }

                                let hit_percentage = 50n + ((hit_distance * 50n) / (BigInt(state.paddle_0.size) / 2n));
                                state.ball.speed_y = ((hit_percentage * BigInt(MAX_SPEED)) / 100n).toString();

                            } else {
                                //The ball will not bounce, but won't reach 0 yet. Continue moving.
                                state.ball.x = (BigInt(state.ball.x) - BigInt(state.ball.speed_x)).toString();
                            }
                        } else {
                            //The ball will not cross the paddle limit in this turn, so we can just move it
                            state.ball.x = (BigInt(state.ball.x) - BigInt(state.ball.speed_x)).toString();
                        }
                    }
                }
            } else {
                let will_bounce = (ball_lower_limit >= paddle_1_upper_limit) && (ball_upper_limit <= paddle_1_lower_limit);
                let MAX_VALUE = MAX_X - PADDLE_HEIGHT - (BigInt(state.ball.size) / 2n);

                if (BigInt(state.ball.x) > MAX_VALUE) {
                    //The ball has already crossed the paddle limit and will score the goal on time
                    if (BigInt(state.ball.speed_x) >= (MAX_X - BigInt(state.ball.x))) {
                        //The ball reach the screen limit in this turn. Change score
                        state.score_0 = (BigInt(state.score_0) + 1n).toString();
                        has_scored_0 = true;
                    } else {
                        //Continue moving the ball
                        state.ball.x = (BigInt(state.ball.x) + BigInt(state.ball.speed_x)).toString();
                    }
                } else {
                    let distance = MAX_VALUE - BigInt(state.ball.x);

                    if (BigInt(state.ball.speed_x) >= (MAX_X - BigInt(state.ball.x))) {
                        //The ball will reach the screen limit in this turn, but it can still bounce
                        if (will_bounce) {
                            state.ball.x = (MAX_VALUE - (BigInt(state.ball.speed_x) - distance)).toString();
                            state.ball.moving_left = true;

                            //Calculate the new speed and direction
                            let hit_distance = 0n;
                            if (BigInt(state.ball.y) > BigInt(state.paddle_0.y)) {
                                state.ball.moving_up = true;
                                hit_distance = BigInt(state.ball.y) - BigInt(state.paddle_1.y);
                            } else {
                                state.ball.moving_up = false;
                                hit_distance = BigInt(state.paddle_1.y) - BigInt(state.ball.y);
                            }

                            let hit_percentage = 50n + ((hit_distance * 50n) / (BigInt(state.paddle_0.size) / 2n));
                            state.ball.speed_y = ((hit_percentage * BigInt(MAX_SPEED)) / 100n).toString();

                        } else {
                            //The ball will not bounce, so the ball will reach 0. Change score.
                            state.score_0 = (BigInt(state.score_0) + 1n).toString();
                            has_scored_0 = true;
                        }
                    } else {
                        if ((BigInt(state.ball.x) + BigInt(state.ball.speed_x)) > MAX_VALUE) {
                            //The ball will cross the paddle limit in this turn, but it can still bounce
                            if (will_bounce) {
                                state.ball.x = (MAX_VALUE - (BigInt(state.ball.speed_x) - distance)).toString();
                                state.ball.moving_left = true;

                                //Calculate the new speed and direction
                                let hit_distance = 0n;
                                if (BigInt(state.ball.y) > BigInt(state.paddle_0.y)) {
                                    state.ball.moving_up = true;
                                    hit_distance = BigInt(state.ball.y) - BigInt(state.paddle_1.y);
                                } else {
                                    state.ball.moving_up = false;
                                    hit_distance = BigInt(state.paddle_1.y) - BigInt(state.ball.y);
                                }

                                let hit_percentage = 50n + ((hit_distance * 50n) / (BigInt(state.paddle_0.size) / 2n));
                                state.ball.speed_y = ((hit_percentage * BigInt(MAX_SPEED)) / 100n).toString();

                            } else {
                                //The ball will not bounce, but won't reach 0 yet. Continue moving.
                                state.ball.x = (BigInt(state.ball.x) + BigInt(state.ball.speed_x)).toString();
                            }
                        } else {
                            //The ball will not cross the paddle limit in this turn, so we can just move it
                            state.ball.x = (BigInt(state.ball.x) + BigInt(state.ball.speed_x)).toString();
                        }
                    }
                }
            }

            //If the game continues
            if (BigInt(state.score_0) < WINNING_SCORE && BigInt(state.score_1) < WINNING_SCORE) {
                //Reset the ball in case of score
                if (has_scored_0 || has_scored_1) {
                    state.ball.x = (MAX_X / 2n).toString();
                    state.ball.y = (MAX_Y / 2n).toString();

                    let randomized = this.randomize_ball(BigInt(state.turn));
                    state.ball.speed_x = randomized[0].toString();
                    state.ball.speed_y = randomized[1].toString();
                    state.ball.moving_up = randomized[2];

                    if (has_scored_0) {
                        state.ball.moving_left = false;
                    } else {
                        state.ball.moving_left = true;
                    }
                }
            }

            state.turn = (BigInt(state.turn) + 1n).toString();
            return state;
        },

        randomize_ball(turn) {
            const BASE_SPEED = 30n;
            /*
            const MAX_SPEED = 160n;
            let random_seed = _gameRooomStore.get_random_seed();
            let hash_of_turn = ec.starkCurve.pedersen(random_seed, turn);
            let random_x = BASE_SPEED + (BigInt(ec.starkCurve.pedersen(hash_of_turn, 0n)) % (MAX_SPEED - BASE_SPEED));
            let random_y = BASE_SPEED + (BigInt(ec.starkCurve.pedersen(hash_of_turn, 1n)) % (MAX_SPEED - BASE_SPEED));
            let random_moving_left = BigInt(ec.starkCurve.pedersen(hash_of_turn, 2n)) % 2n == 1n;
            let random_moving_up = BigInt(ec.starkCurve.pedersen(hash_of_turn, 3n)) % 2n == 1n;
            */
            //SMART CONTRACT CURRENTLY CANNOT REPLICATE THIS, USE SIMPLE ALTERNATICVE

            let moving_up = (turn % 2n) == 1n;
            return [BASE_SPEED, BASE_SPEED, moving_up, false];
        },

        processTurn(turn) {
            console.log(`game: processTurn()`);

            if (BigInt(this.currentState.turn) > BigInt(turn.turn.turn)) {
                console.error(`  - Turn #${this.currentState.turn} already processed`);
                return;
            }

            if (BigInt(this.currentState.turn) < (BigInt(turn.turn.turn))) {
                console.error(`  - Turn #${turn.turn} is in not sequential`);
                return;
            }

            //Verify the hash
            let hashedTurn = ec.starkCurve.pedersen(
                BigInt(turn.turn.turn),
                BigInt(turn.turn.action)
            );

            if (turn.hash != hashedTurn) {
                console.error(`Wrong hash for turn #${turn.turn.turn}`);
                return;
            }

            //Verify the signature
            let signature = new ec.starkCurve.Signature(
                BigInt(turn.signature.r),
                BigInt(turn.signature.s)
            );

            let player_for_turn = this.playerNumberFromTurn(BigInt(turn.turn.turn));

            let public_key = (player_for_turn == _gameRooomStore.myPlayerNumber) ? this.keys.publicKey : this.keys.opponentPublicKey;
            if (public_key == null || public_key == undefined) {
                console.error("Missing public key for signature verification");
                return;
            }

            if (!(ec.starkCurve.verify(signature, hashedTurn, public_key))) {
                console.error(`Invalid turn #${turn.turn.turn} signature`);
                return;
            }

            //Save the timestamp to calculate dealy
            if (player_for_turn != _gameRooomStore.myPlayerNumber) {
                this.lastTurnReceived = Date.now();
            }

            //Advance the state
            if (!this.advance_state(player_for_turn, BigInt(turn.turn.turn), BigInt(turn.turn.action))) {
                console.error(`Couldn't advance state with valid turn #${turn.turn.turn}`)
            }

            this.addTurn(turn);

            let new_player = this.playerNumberFromTurn(BigInt(this.currentState.turn));
            if (this.internalStatus == INTERNAL_STATUS.PLAYING && new_player == _gameRooomStore.myPlayerNumber) {
                this.playTurn();
            }
        },

        recalculateCurrentState(replace_local_storage = false) {
            console.log(`game: recalculateCurrentState(${replace_local_storage})`);

            //First, delete all turns with tunr number < checkpoint
            let countDeleted = 0;
            for (let i = this.turns.length - 1; i >= 0; i--) {
                if (BigInt(this.turns[i].turn.turn) < BigInt(this.checkpoint.data.turn)) {
                    this.turns.splice(i, 1);
                    countDeleted++;
                }
            }
            if (countDeleted > 0) console.log(`  - Deleted ${countDeleted} turns`);

            //Now process the new state from the currentState
            if (this.currentState == null) {
                this.currentState = JSON.parse(JSON.stringify(this.checkpoint.data));
            };

            if (this.currentState == null) {
                return this.gameError("No checkpoint or current state found when recalculating state");
            }

            this.turns.sort((a, b) => { return Number(BigInt(a.turn.turn) - BigInt(b.turn.turn)) });

            for (let i = 0; i < this.turns.length; i++) {
                let turn = this.turns[i];
                if (BigInt(this.turns[i].turn.turn) == BigInt(this.currentState.turn)) {
                    this.advance_state(this.playerNumberFromTurn(BigInt(turn.turn.turn)), BigInt(turn.turn.turn), BigInt(turn.turn.action));
                }
            }
        },

        addTurn(new_turn) {
            console.log(`game: addTurn(#${new_turn.turn.turn})`);

            //Add new_turn to this.turns
            if (this.turns.length == 0) {
                this.turns.push(new_turn);
            } else {
                let last_turn = this.turns[this.turns.length - 1];
                if (BigInt(last_turn.turn.turn) == (BigInt(new_turn.turn.turn) - 1n)) {
                    this.turns.push(new_turn);
                } else if (BigInt(last_turn.turn.turn) >= (BigInt(new_turn.turn.turn))) {
                    console.log("TURN ALREADY SAVED TO MEMORY");
                } else {
                    return console.error("NON CONSECUTIVE TURN");
                }
            }

            //Add new_turn to localStorage
            let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
            if (storedGameData != null && storedGameData != undefined) {
                storedGameData = JSON.parse(storedGameData);
            } else {
                this.gameError("No stored game data found when syncing");
            }
            if (!("turns" in storedGameData)) {
                storedGameData.turns = [new_turn];
            } else {
                if (storedGameData.turns.length == 0) {
                    storedGameData.turns.push(new_turn);
                } else {
                    let last_turn = storedGameData.turns[storedGameData.turns.length - 1];
                    if (BigInt(last_turn.turn.turn) == (BigInt(new_turn.turn.turn) - 1n)) {
                        storedGameData.turns.push(new_turn);
                    } else if (BigInt(last_turn.turn.turn) >= (BigInt(new_turn.turn.turn))) {
                        console.log("TURN ALREADY SAVED TO STORAGE");
                    } else {
                        return console.error("NON CONSECUTIVE TURN");
                    }
                }
            }

            localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));
        },

        createPartialCheckpoint(target_turn, send_after = true) {
            console.log(`game: createPartialCheckpoint(${target_turn})`);

            //Check if its really necessary to create a partial checkpoint
            if (BigInt(this.checkpoint.data.turn) >= target_turn) {
                console.error("Checkpoint is already ahead of target turn");
                return;
            }

            let new_data = JSON.parse(JSON.stringify(this.checkpoint.data));

            //Loop the turn until reaching the target turn
            this.turns.sort((a, b) => { return Number(BigInt(a.turn.turn) - BigInt(b.turn.turn)) });
            for (let i = 0; i < this.turns.length; i++) {
                let TURN = this.turns[i];
                if (BigInt(TURN.turn.turn) >= target_turn) {
                    break;
                }

                if (BigInt(TURN.turn.turn) == BigInt(new_data.turn)) {
                    new_data = this.state_transition(new_data, BigInt(TURN.turn.action));
                }
            }

            if (BigInt(new_data.turn) != target_turn) {
                console.error("Failed to create partial checkpoint");
                return;
            }

            //Create the actual checkpoint
            let new_checkpoint = {
                data: JSON.parse(JSON.stringify(new_data)),
                hash: null,
                on_chain: false,
                signatures: [null, null]
            };

            //Calculate the hash of the state
            let state_hash = this.getCheckpointHash(JSON.parse(JSON.stringify(new_data)));
            new_checkpoint.hash = state_hash;

            //Sign the hash
            let signedCheckpoint = ec.starkCurve.sign(state_hash, this.keys.privateKey);

            new_checkpoint.signatures[_gameRooomStore.myPlayerNumber] = {
                r: '0x' + signedCheckpoint.r.toString(16),
                s: '0x' + signedCheckpoint.s.toString(16)
            };

            //Double check that this checkpoint is > older checkpoint
            if (send_after) {
                if (BigInt(new_checkpoint.data.turn) > BigInt(this.checkpoint.data.turn)) {
                    _sendMessage({
                        type: MESSAGE_TYPE.SYNC,
                        data: {
                            checkpoint: new_checkpoint,
                            turns: []
                        }
                    });
                }
            }

            return new_checkpoint;
        },

        updateCheckpoint(checkpoint) {
            console.log(`game: getCheckpointFromBlockchain()`);
            //Update the localStorage checpoint and this.checkpoint
            //Alos deletes old turns from localStorage and this.turns
            //DOES NOT CHECK SIGNATURES!

            if (BigInt(checkpoint.data.turn) >= BigInt(this.checkpoint.data.turn)) {
                let storedGameData = localStorage.getItem(_gameRoomFactoryStore.localKey);
                if (storedGameData != null && storedGameData != undefined) {
                    storedGameData = JSON.parse(storedGameData);
                } else {
                    this.gameError("No stored game data found when syncing");
                }

                this.checkpoint = JSON.parse(JSON.stringify(checkpoint));
                storedGameData.checkpoint = JSON.parse(JSON.stringify(checkpoint));

                //Delete turns that are older than the checkpoint (in localStorage)
                let turns_to_delete = [];
                for (let i = 0; i < storedGameData.turns.length; i++) {
                    if (BigInt(storedGameData.turns[i].turn.turn) < BigInt(checkpoint.data.turn)) {
                        turns_to_delete.push(i);
                    }
                }
                for (let i = turns_to_delete.length - 1; i >= 0; i--) {
                    storedGameData.turns.splice(turns_to_delete[i], 1);
                }

                //Delete turns that are older than the checkpoint (in this.turns)
                turns_to_delete = [];
                for (let i = 0; i < this.turns.length; i++) {
                    if (BigInt(this.turns[i].turn.turn) < BigInt(checkpoint.data.turn)) {
                        turns_to_delete.push(i);
                    }
                }
                for (let i = turns_to_delete.length - 1; i >= 0; i--) {
                    this.turns.splice(turns_to_delete[i], 1);
                }

                //Save the new checkpoint and turns to localStorage
                localStorage.setItem(_gameRoomFactoryStore.localKey, JSON.stringify(storedGameData));

                this.recalculateCurrentState();
            } else {
                console.error("Won't update checkpoint to older state")
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

            let manual_hash = ec.starkCurve.pedersen(BigInt(state_as_array_of_felts[0]), BigInt(state_as_array_of_felts[1]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[2]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[3]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[4]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[5]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[6]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[7]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[8]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[9]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[10]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[11]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[12]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[13]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[14]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[15]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[16]));
            manual_hash = ec.starkCurve.pedersen(manual_hash, BigInt(state_as_array_of_felts[17]));

            return manual_hash;
        },

        showPartialExit() {
            console.log("game: showPartialExit()");
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
            this.$patch(JSON.parse(JSON.stringify(_initialState)));
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
            if (_messageTimer != null) {
                clearTimeout(_messageTimer);
                _messageTimer = null;
            }
        }
    }
});


