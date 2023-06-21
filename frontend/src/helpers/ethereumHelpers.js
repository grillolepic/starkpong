import { uint256 } from 'starknet';

function formatEther(amount) {
    let bn = amount.toString();
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

function formatEtherForDisplay(amount) {
    amount = parseFloat(formatEther(amount));
    let digits = 2;

    const lookup = [
      { value: 1, symbol: "" },
      { value: 1e3, symbol: "K" },
      { value: 1e6, symbol: "M" },
      { value: 1e9, symbol: "G" },
      { value: 1e12, symbol: "T" },
      { value: 1e15, symbol: "P" },
      { value: 1e18, symbol: "E" }
    ];
    const rx = /\.0+$|(\.[0-9]*[1-9])0+$/;
    var item = lookup.slice().reverse().find(function(item) {
      return amount >= item.value;
    });
    return item ? (amount / item.value).toFixed(digits).replace(rx, "$1") + item.symbol : "0";
  }

export { formatEther, formatEtherForDisplay };