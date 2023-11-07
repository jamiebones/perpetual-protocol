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

  describe("Protocol operations", function () {
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
      //de deposisted 100 dollars multiplied by 10 to get collateral
      expect((+contractDetails[3].toString() / etherConstant)).to.be.equal(+amountToDeposit.toString() * 10 / etherConstant)
      expect((+userPosition[3].toString()) / etherConstant).to.be.greaterThan(0);
      console.log("contract details => ", +(contractDetails[3].toString()) / etherConstant,
        +(contractDetails[5].toString()) / etherConstant)
    });

    it("should allow the trader deposit both long and shsrt assets", async () => {
      const { traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
      const amountToDeposit = ethers.parseEther("100");
      const amountToDeposit2 = ethers.parseEther("200");
      const allowance = ethers.parseEther("200");
      const liquidityAmount = ethers.parseEther("200");
      //grant allowance

      await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, liquidityAmount);
      await USDCContract.connect(liquidityProviderTwo).approve(VaultContract.target, liquidityAmount);
      await USDCContract.connect(traderOne).approve(JamoProtocolContract.target, allowance);
      await USDCContract.connect(traderTwo).approve(JamoProtocolContract.target, allowance);
      //provide liquidity
      await VaultContract.connect(liquidityProviderOne).deposit(liquidityAmount, liquidityProviderOne.address);
      await VaultContract.connect(liquidityProviderTwo).deposit(liquidityAmount, liquidityProviderTwo.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1)
      //open a long position 
      await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
      const shortPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      const longPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 1);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsAfter[2].toString() / etherConstant).to.be.equal(1000) //amount deposisted * 10 ( 100 * 10 )
      expect(+contractDetailsAfter[3].toString() / etherConstant).to.be.equal(1000)
      expect(+contractDetailsAfter[4].toString() / etherConstant).to.be.greaterThan(0);
      console.log("short position", shortPosition);

      console.log("long position", longPosition);

      await JamoProtocolContract.connect(traderTwo).openPosition(amountToDeposit2, 2);
      const contractDetailsAfterTraderTwoDeposit = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsAfterTraderTwoDeposit[2].toString() / etherConstant).to.be.equal(3000)
    });


    it("should allow a user increase their position", async () => {
      const { traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
      const amountToDeposit = ethers.parseEther("100");
      const amountToDeposit2 = ethers.parseEther("50");
      const allowance = ethers.parseEther("200");
      const liquidityAmount = ethers.parseEther("200");
      //grant allowance

      await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, liquidityAmount);
      await USDCContract.connect(liquidityProviderTwo).approve(VaultContract.target, liquidityAmount);
      await USDCContract.connect(traderOne).approve(JamoProtocolContract.target, allowance);
      await USDCContract.connect(traderTwo).approve(JamoProtocolContract.target, allowance);
      //provide liquidity
      await VaultContract.connect(liquidityProviderOne).deposit(liquidityAmount, liquidityProviderOne.address);
      await VaultContract.connect(liquidityProviderTwo).deposit(liquidityAmount, liquidityProviderTwo.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
      const shortPositionBeforeIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      //increase the short position
      await JamoProtocolContract.connect(traderOne).increasePosition(0, amountToDeposit2);
      const shortPositionAfterIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);

      console.log("before ", shortPositionBeforeIncrease)
      console.log("after ", shortPositionAfterIncrease)
      expect(+shortPositionAfterIncrease[2].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[2].toString() / etherConstant)
      expect(+shortPositionAfterIncrease[3].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[3].toString() / etherConstant)
      expect(+shortPositionAfterIncrease[4].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[4].toString() / etherConstant)
    })




  });


});
