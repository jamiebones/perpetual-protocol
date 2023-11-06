const {
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers } = require("hardhat");
const { expect } = require("chai");

const etherConstant = 1_000_000_000_000_000_000;

describe("JamoProtocol", function () {

  async function deployContractFixture() {
    // Contracts are deployed using the first signer/account by default
    const tokenToTransfer = ethers.parseEther("1000");
    const [owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo] = await ethers.getSigners();

    console.log("Starting deployment of USDC Contract");
    const USDCContract = await ethers.deployContract("USDC");
    await USDCContract.waitForDeployment();

    console.log("finish deploying USDC Contract to => ", USDCContract.target);

    console.log("Starting deployment of JamoProtocol ");
    const JamoProtocolContract = await ethers.deployContract("JamoProtocol", [USDCContract.target]);
    await JamoProtocolContract.waitForDeployment();
    console.log("finish deploying JamoProtocol to => ", JamoProtocolContract.target);

    console.log("Starting deployment of VaultContract ");
    const VaultContract = await ethers.deployContract("MyVault", [USDCContract.target, "Prep", "PR", JamoProtocolContract.target]);
    await VaultContract.waitForDeployment();
    console.log("finish deploying VaultContract to => ", VaultContract.target);

    //give tokens to address
    await USDCContract.connect(owner).transfer(traderOne.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(traderTwo.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(liquidityProviderOne.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(liquidityProviderTwo.address, tokenToTransfer);
    await JamoProtocolContract.connect(owner).setVaultInContract(VaultContract.target)
    return { owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract };
  }

  describe("Deployment", function () {
    let JamoProtocol;
    let Vault;
    it("Should set vault contract address ", async function () {
      // const { owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
      // JamoProtocol = JamoProtocolContract;
      // Vault = VaultContract;
      // await JamoProtocolContract.connect(owner).setVaultInContract(VaultContract.target)

    });

    it("should allow deposist of funds into the contract", async function () {
      const { liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
      const amountToDeposit = ethers.parseEther("100");
      const beforeDeposit = await USDCContract.balanceOf(liquidityProviderOne.address);
      const vaultBalBefore = await VaultContract.getDeposistedAmount();
      console.log("before depositing ", beforeDeposit);
      await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, amountToDeposit);
      await VaultContract.connect(liquidityProviderOne).deposit(amountToDeposit, liquidityProviderOne.address);
      const vaultBalAfter = await VaultContract.getDeposistedAmount();
      const afterDeposit = await USDCContract.balanceOf(liquidityProviderOne.address);
      expect(beforeDeposit).to.be.greaterThan(afterDeposit);
      expect(vaultBalBefore).to.be.lessThan(vaultBalAfter);
      expect(vaultBalAfter).to.be.equal(amountToDeposit);
      console.log("after depositing : ", afterDeposit);
    });

    it("should allow the trader deposit collateral", async () => {
      const { owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
      const amountToDeposit = ethers.parseEther("100");
      //provide liquidity to the protocol
      await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, amountToDeposit);
      await VaultContract.connect(liquidityProviderOne).deposit(amountToDeposit, liquidityProviderOne.address);

      //set allowance to allow the protocol withdraw the USDC
      await USDCContract.connect(traderOne).approve(JamoProtocolContract.target, amountToDeposit);

      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1)
      const contractDetails = await JamoProtocolContract.getProtocolDetails();
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect((+userPosition[4].toString()) / etherConstant).to.be.equal((+contractDetails[3].toString() / etherConstant))
      console.log("user position => ", userPosition)
      //de deposisted 100 dollars multiplied by 10 to get collateral
      expect((+contractDetails[3].toString() / etherConstant)).to.be.equal(+amountToDeposit.toString() * 10 / etherConstant)

      //     0n,
      // 25690n,
      // 100000000000000000000n,
      // 38925652004671078n,
      // 1000000000000000000000n,
      // 1692740495n,
      // 0n,
      // false

      console.log("contract details => ", +(contractDetails[3].toString()) / etherConstant,
        +(contractDetails[5].toString()) / etherConstant)
    });




  });


});
