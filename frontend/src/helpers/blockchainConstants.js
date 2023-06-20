const etherAddress = {
    '0x534e5f4d41494e': '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
    '0x534e5f474f45524c49': '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7'
};

const pongTokenAddress = {
    '0x534e5f4d41494e': '',
    '0x534e5f474f45524c49': '0x076d616a4566c5cd5d46fe83cf7511f62f868d15e55b60d2ea56103239db2337'
};

const networkNames = {
    '0x534e5f4d41494e': 'StarkNet Mainnet',
    '0x534e5f474f45524c49': 'StarkNet Goerli Testnet'
};

const serverNetworkTag = {
    '0x534e5f4d41494e': 'starknet',
    '0x534e5f474f45524c49': 'starknet_goerli'
};

const gameFactoryAddress = {
    '0x534e5f4d41494e': '',
    '0x534e5f474f45524c49': '0x02909102709cbd49f3d5cccc85056bc489c81b09baecdc98f44bb4cb0f7b9a74'
};

const supportedChainIds = ['0x534e5f474f45524c49'];
const defaultChainId = '0x534e5f474f45524c49';

function isTestnet(chainId) {
    return chainId != '0x534e5f4d41494e';
}

export {
    etherAddress,
    pongTokenAddress,
    networkNames,
    serverNetworkTag,
    gameFactoryAddress,
    supportedChainIds,
    defaultChainId,
    isTestnet
}