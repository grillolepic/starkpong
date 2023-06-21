import { defineStore } from 'pinia';
import { Contract, CallData } from 'starknet';
import { useStarknetStore } from './starknet';
import { formatEther, formatEtherForDisplay } from '@/helpers/ethereumHelpers';
import {
    gameTokenAddress,
    gameTokenFaucetAddress
} from '@/helpers/blockchainConstants';

import GAME_TOKEN_ABI from '@/stores/abi/GameToken.json' assert { type: 'json' };
import GAME_TOKEN_FAUCET_ABI from '@/stores/abi/GameTokenFaucet.json' assert { type: 'json' };
import { isNavigationFailure } from 'vue-router';

let _starknetStore = null;
let _gameTokenContract = null;
let _gameTokenFaucetContract = null;

let _initialState = {
    tokenName: 'PONG',
    loadingBalance: true,
    balance: 0n,

    loadingFaucetStatus: true,
    faucetReady: false,
    nextClaim: null
}

export const useGameTokenStore = defineStore('game_token', {
    state: () => {
        return { ..._initialState }
    },

    getters: {
        balanceForDisplay: (state) => formatEtherForDisplay(state.balance)
    },

    actions: {
        async init() {
            console.log('game_token: init()');
            _starknetStore = useStarknetStore();
        },

        loggedIn() {
            console.log('game_token: loggedIn()');
            if (_starknetStore.isStarknetReady) {
                _gameTokenContract = new Contract(GAME_TOKEN_ABI, gameTokenAddress[_starknetStore.chainId], _starknetStore.account);
                if (_starknetStore.isTestnet) {
                    _gameTokenFaucetContract = new Contract(GAME_TOKEN_FAUCET_ABI, gameTokenFaucetAddress[_starknetStore.chainId], _starknetStore.account);
                    this.updateFaucetStatus();
                }
                this.updateBalance();
            }
        },

        async updateBalance() {
            console.log('starknet: updateBalance()');
            if (!_starknetStore.isStarknetReady) {
                return this.balance = 0n;
            }

            let response = await _gameTokenContract.balanceOf(_starknetStore.address);
            this.$patch({
                loadingBalance: false,
                balance: response
            });
        },

        async updateFaucetStatus() {
            console.log('starknet: updateFaucetStatus()');
            if (!_starknetStore.isStarknetReady || !_starknetStore.isTestnet) {
                return this.$patch({
                    loadingFaucetStatus: false,
                    faucetReady: false,
                    nextClaim: null
                });
            }

            let tokens_left = await _gameTokenFaucetContract.tokens_left();
            let time_until_next_claim = await _gameTokenFaucetContract.time_until_next_claim(_starknetStore.address);

            if (tokens_left >= 500000000000000000000n) {
                if (time_until_next_claim == 0n) {
                    return this.$patch({
                        loadingFaucetStatus: false,
                        faucetReady: true,
                        nextClaim: null
                    });
                }
            }

            let last_claim = await _gameTokenFaucetContract.last_claim(_starknetStore.address);
            last_claim += 86400n;

            console.log(new Date(Number(last_claim * 1000n)));

            return this.$patch({
                loadingFaucetStatus: false,
                faucetReady: false,
                nextClaim: (new Date(Number(last_claim * 1000n))).toLocaleString()
            });
        },

        async claim() {
            console.log('game_token: claim()');
            if (!_starknetStore.isStarknetReady || !_starknetStore.isTestnet) {
                return;
            }

           let claimCall = await _gameTokenFaucetContract.populate("claim", []);
            if (await _starknetStore.sendTransactions([claimCall])) {
                this.updateFaucetStatus();
                this.updateBalance();
            }
        },

        loggedOut() {
            console.log('game_token: loggedOut()');
            _gameTokenContract = null;
            this.$patch({ ..._initialState });
            this.initialized = true;
        }
    }
});