require("@nomicfoundation/hardhat-toolbox");
const PRIVATE_KEY = "17628c53eb64de620ebd399dfa953551763b06c4db4f1beaa2a78abe61422dea";
// Replace with your actual private key. This is a dummy key and should not be used in production.

// Ensure your configuration variables are set before executing the script
const { vars } = require("hardhat/config");

// Go to https://infura.io, sign up, create a new API key
// in its dashboard, and add it to the configuration variables
const SEPOLIA_RPC_URL = "https://eth-sepolia.g.alchemy.com/v2/oFfvEpXYjGo8Nj4QQIkU3kXd6Z0JvfJZ";
const BSC_RPC_URL = "https://56.rpc.thirdweb.com/4e74a8cc63319adbdf4ca0f672467a7c";
const BSC_TESTNET_RPC_URL = "https://97.rpc.thirdweb.com/4e74a8cc63319adbdf4ca0f672467a7c";
const BASE_RPC_URL = "https://base-mainnet.g.alchemy.com/v2/VwsudXzil6Fin9wYCZCp8HU4_zm5LYQM";

// Add your Sepolia account private key to the configuration variables
// To export your private key from Coinbase Wallet, go to
// Settings > Developer Settings > Show private key
// To export your private key from Metamask, open Metamask and
// go to Account Details > Export Private Key
// Beware: NEVER put real Ether into testing accounts

const ETHERSCAN_API_KEY = "3XEJWR18EUG1PYTAEH1167W2T3X6KHIBYR";
const BSC_API_KEY = "VHDNU7NTSR8FB96TE1V5YWNZPP5UDBU1DX";
const BASE_API_KEY = "RRFR7W2J47DXYUMVXQ1PHFN5W4PFME36TG";

module.exports = {
  solidity: "0.8.20",
  networks: {
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: [PRIVATE_KEY],
    },
    bsc: {
      url: BSC_RPC_URL,
      accounts: [PRIVATE_KEY],
    },
    bscTestnet: {
      url: BSC_TESTNET_RPC_URL,
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: BASE_RPC_URL,
      accounts: [PRIVATE_KEY],
    }
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY,
      bsc: BSC_API_KEY,
      bscTestnet: BSC_API_KEY,
      base: BASE_API_KEY,
    }
  },
};