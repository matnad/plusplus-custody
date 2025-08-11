## Setup

Create a `.env` file in the project root. The rpc url is used for forked mainnet tests; the gas and eth prices can be omitted and are only used to measure gas costs of functions.

```
MAINNET_RPC_URL=<https rpc url>
GAS_PRICE_WEI=<current gas price in WEI>
ETH_PRICE_USD=<current USD/Ether price in WEI>
```

Example:
```
MAINNET_RPC_URL=https://ethrpc.url
GAS_PRICE_WEI=1000000000
ETH_PRICE_USD=4000000000000000000000
```

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
