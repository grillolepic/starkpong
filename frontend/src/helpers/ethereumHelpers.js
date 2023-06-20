import { uint256 } from 'starknet';

function formatEther(amount) {
    let bn = uint256.uint256ToBN(amount).toString();
    let currentStr = ''
    if (bn.length > 18) {
        let extraZeros = bn.length - 18
        currentStr = bn.substring(0, extraZeros) + '.' + bn.substring(extraZeros + 1)
    } else {
        let zerosMissing = 18 - bn.length
        currentStr = '0.' + '0'.repeat(zerosMissing) + bn
    }
    return currentStr
}

export { formatEther };