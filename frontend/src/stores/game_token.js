import { defineStore } from 'pinia';
import { Contract } from 'starknet';
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
    balance: "0",

    loadingFaucetStatus: true,
    faucetReady: false,
    nextClaim: null
}

export const useGameTokenStore = defineStore('game_token', {
    state: () => {
        return JSON.parse(JSON.stringify(_initialState));
    },

    getters: {
        tokenContract: (_) => _gameTokenContract,
        balanceAsFloat: (state) => formatEther(BigInt(state.balance)),
        balanceForDisplay: (state) => formatEtherForDisplay(BigInt(state.balance))
    },

    actions: {
        loggedIn() {
            console.log('game_token: loggedIn()');
            _starknetStore = useStarknetStore();
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
            console.log('game_token: updateBalance()');
            if (!_starknetStore.isStarknetReady) {
                return this.balance = "0";
            }

            let response = await _gameTokenContract.balanceOf(_starknetStore.address);
            this.$patch({
                loadingBalance: false,
                balance: response.toString()
            });
        },

        async updateFaucetStatus() {
            console.log('game_token: updateFaucetStatus()');
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
            this.$patch(JSON.parse(JSON.stringify(_initialState)));
        }
    }
});