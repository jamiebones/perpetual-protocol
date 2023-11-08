require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      // forking: {
      //   url: `https://mainnet.infura.io/v3/${process.env.INFURAKEY}`,
      //   blockNumber: 17973003,
        
      // }
    }
  },
  solidity: "0.8.20",
  mocha: {
    timeout: 11400000,
  },
};
