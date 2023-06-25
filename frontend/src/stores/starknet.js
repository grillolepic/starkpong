import { defineStore } from 'pinia';
import { connect, disconnect } from '@argent/get-starknet';
import { Contract, validateAndParseAddress, Provider, constants } from 'starknet';
import { formatEther } from '@/helpers/ethereumHelpers';
import { useGameTokenStore } from './game_token';
import { useGameRoomFactoryStore } from './game_room_factory';
import { useGameRoomStore } from './game_room';
import { useGameStore } from './game';
import {
  etherAddress,
  networkNames,
  supportedChainIds,
  defaultChainId,
  isTestnet
} from '@/helpers/blockchainConstants';

import ETH_ABI from '@/stores/abi/eth.json' assert { type: 'json' };

let _starknet = null;
let _gameTokenStore;
let _gameRoomFactoryStore;
let _gameRoomStore;
let _gameStore;

let _etherContract = null;
let _fixed_mainnet_provider = new Provider({ sequencer: { network: constants.NetworkName.SN_MAIN } });

let _initialState = {
  initialized: false,
  connecting: false,
  connected: false,
  address: '',
  starkName: null,
  chainId: null,
  networkName: null,
  networkOk: false,
  balance: "0",

  transaction: {
    status: null,
    link: null,
    error: null
  }
}

export const useStarknetStore = defineStore('starknet', {
  state: () => {
    return JSON.parse(JSON.stringify(_initialState));
  },

  getters: {
    account: (state) => {
      if (_starknet != null) {
        return _starknet.account
      }
      return null
    },
    shortAddress: (state) => {
      return (len) => {
        if (state.address.length == 0) {
          return ''
        }
        if (state.starkName != null) {
          return state.starkName
        }
        return `${state.address.substring(0, Math.floor(len / 2))}...${state.address.substring(
          state.address.length - Math.floor(len / 2)
        )}`
      }
    },
    currentOrDefaultChainId: (state) => (state.chainId == null) ? defaultChainId : state.chainId,
    isStarknetConnected: () => (_starknet == null) ? false : _starknet.isConnected,
    isStarknetReady: (state) => (state.connected && state.networkOk),
    isTestnet: (state) => isTestnet(state.currentOrDefaultChainId),
    balanceFormat: (state) => formatEther(BigInt(state.balance)),
    fixedMainnetProvider: () => _fixed_mainnet_provider
  },

  actions: {
    async init() {
      console.log('starknet: init()');
      if ('true' === localStorage.getItem('wasConnected')) {
        _starknet = await connect({ showList: false });
        await _starknet?.enable();
        if (_starknet?.isConnected) {
          this.login();
        }
      }
      _gameTokenStore = useGameTokenStore();
      _gameRoomFactoryStore = useGameRoomFactoryStore();
      _gameRoomStore = useGameRoomStore();
      _gameStore = useGameStore();
      this.initialized = true;
    },

    async connectStarknet() {
      console.log('starknet: connectStarknet()');
      _starknet = await connect({
        modalOptions: { theme: 'dark' }
      });
      await _starknet?.enable();
      if (_starknet?.isConnected) {
        this.login();
      }
    },

    async login() {
      if (_starknet?.isConnected) {
        console.log('starknet: login()');

        let address = validateAndParseAddress(_starknet.selectedAddress);
        let { chainId } = _starknet.provider;
        let network_name = networkNames[chainId];
        let network_ok = supportedChainIds.includes(chainId);

        this.$patch({
          connecting: false,
          connected: true,
          address: address,
          chainId: chainId,
          networkName: network_name,
          networkOk: network_ok
        })

        _starknet.off('accountsChanged', this.handleAccountsChanged);
        _starknet.on('accountsChanged', this.handleAccountsChanged);

        this.findStarkDomain();

        if (network_ok) {
          _etherContract = new Contract(ETH_ABI, etherAddress[chainId], _starknet.account);
          await this.updateBalance();

          _gameTokenStore.loggedIn();
          _gameRoomFactoryStore.loggedIn()
        }

        localStorage.setItem('wasConnected', true);

      } else {
        this.logout()
      }
    },

    async findStarkDomain() {
      console.log('starknet: findStarkDomain()');

      let stark_domain = null
      try {
        stark_domain = await _fixed_mainnet_provider.getStarkName(this.address);
      } catch (err) { }

      this.starkName = stark_domain;
    },

    async updateBalance() {
      console.log('starknet: updateBalance()');
      if (_starknet == null || _etherContract == null) {
        return (this.balance = "0");
      }

      let response = await _etherContract.balanceOf(this.address);
      this.balance = response.toString();
    },

    resetTransaction() {
      console.log("starknet: resetTransaction()");
      this.$patch({
        transaction: {
          status: null,
          link: null,
          error: null
        }
      });
    },

    async sendTransactions(tx_array) {
      console.log("starknet: transaction()");
      try {
        if (_starknet != null) {
          this.transaction.status = 0;
          let result = await _starknet.account.execute(tx_array);

          this.transaction.link = `https://${this.isTestnet ? 'testnet.' : ''}starkscan.co/tx/${result.transaction_hash}`;
          this.transaction.status = 1;
          await _starknet.provider.waitForTransaction(result.transaction_hash);

          await sleep(5000);

          this.transaction.status = 2;
          this.updateBalance();
          return true;
        }
      } catch (err) {
        console.log(err);
        this.transaction.error = err.toString().replace("Error: ", "");
        this.transaction.status = -1;
        this.updateBalance();
      }
      return false;
    },

    handleAccountsChanged(accounts) {
      console.log(`starknet: handleAccountsChanged(${accounts})`);
      if (_starknet.selectedAddress != this.address) {
        this.login();
      }
    },

    logout() {
      console.log('starknet: logout()');
      _starknet.off('accountsChanged', this.handleAccountsChanged);
      this.$patch(_initialState);
      this.initialized = true;
      _etherContract = null;
      _starknet = null;
      disconnect({
        clearLastWallet: true
      });
      _gameTokenStore.loggedOut();
      _gameRoomFactoryStore.loggedOff();
    }
  }
})

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}