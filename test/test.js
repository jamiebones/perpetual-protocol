const {
  loadFixture,
  time
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers, network } = require("hardhat");
const { expect } = require("chai");
require("dotenv").config();

const etherConstant = 1_000_000_000_000_000_000;

describe("JamoProtocol", function () {

  async function deployContractFixture() {
    // Contracts are deployed using the first signer/account by default
    const tokenToTransfer = ethers.parseEther("1000");
    const [owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo] = await ethers.getSigners();
    const USDCContract = await ethers.deployContract("USDC");
    await USDCContract.waitForDeployment();

    const PriceFeedContract = await ethers.deployContract("PriceFeedMock");
    await PriceFeedContract.waitForDeployment();
    const JamoProtocolContract = await ethers.deployContract("JamoProtocol", [USDCContract.target, PriceFeedContract.target]);
    await JamoProtocolContract.waitForDeployment();
    const VaultContract = await ethers.deployContract("MyVault", [USDCContract.target, "Prep", "PR", JamoProtocolContract.target]);
    await VaultContract.waitForDeployment();
    //give tokens to address
    await USDCContract.connect(owner).transfer(traderOne.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(traderTwo.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(liquidityProviderOne.address, tokenToTransfer);
    await USDCContract.connect(owner).transfer(liquidityProviderTwo.address, tokenToTransfer);
    await JamoProtocolContract.connect(owner).setVaultInContract(VaultContract.target);
    await PriceFeedContract.setLatestPrice(30000 * 1e8);
    return { owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract, PriceFeedContract };
  }

  async function generalOperationFixture() {
    const { traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract, PriceFeedContract } = await loadFixture(deployContractFixture);
    const allowance = ethers.parseEther("300");
    const liquidityAmount = ethers.parseEther("300");
    //grant allowance
    await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, liquidityAmount);
    await USDCContract.connect(liquidityProviderTwo).approve(VaultContract.target, liquidityAmount);
    await USDCContract.connect(traderOne).approve(JamoProtocolContract.target, allowance);
    await USDCContract.connect(traderTwo).approve(JamoProtocolContract.target, allowance);
    //provide liquidity
    await VaultContract.connect(liquidityProviderOne).deposit(liquidityAmount, liquidityProviderOne.address);
    await VaultContract.connect(liquidityProviderTwo).deposit(liquidityAmount, liquidityProviderTwo.address);

    return { traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract, PriceFeedContract }
  }


  describe("Protocol operations", function () {
    // it("Should set vault contract address ", async function () {
    //   // const { owner, traderOne, traderTwo, liquidityProviderOne, liquidityProviderTwo, USDCContract, JamoProtocolContract, VaultContract } = await loadFixture(deployContractFixture);
    //   // JamoProtocol = JamoProtocolContract;
    //   // Vault = VaultContract;
    //   // await JamoProtocolContract.connect(owner).setVaultInContract(VaultContract.target)

    // });

    // it("should allow deposist of funds into the liquidity pool", async function () {
    //   const { liquidityProviderOne, USDCContract, VaultContract } = await loadFixture(deployContractFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   const beforeDeposit = await USDCContract.balanceOf(liquidityProviderOne.address);
    //   const vaultBalBefore = await VaultContract.getDeposistedAmount();
    //   await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, amountToDeposit);
    //   await VaultContract.connect(liquidityProviderOne).deposit(amountToDeposit, liquidityProviderOne.address);
    //   const vaultBalAfter = await VaultContract.getDeposistedAmount();
    //   const afterDeposit = await USDCContract.balanceOf(liquidityProviderOne.address);
    //   expect(beforeDeposit).to.be.greaterThan(afterDeposit);
    //   expect(vaultBalBefore).to.be.lessThan(vaultBalAfter);
    //   expect(vaultBalAfter).to.be.equal(amountToDeposit);
    // });

    // it("should allow the trader deposit collateral", async () => {
    //   const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1)
    //   const contractDetails = await JamoProtocolContract.getProtocolDetails();
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   expect((+userPosition[4].toString()) / etherConstant).to.be.equal((+contractDetails[3].toString() / etherConstant))
    //   //de deposisted 100 dollars multiplied by 10 to get collateral
    //   expect((+contractDetails[3].toString() / etherConstant)).to.be.equal(+amountToDeposit.toString() * 10 / etherConstant)
    //   expect((+userPosition[3].toString()) / etherConstant).to.be.greaterThan(0);
    //   console.log("contract details => ", +(contractDetails[3].toString()) / etherConstant,
    //     +(contractDetails[5].toString()) / etherConstant)
    // });

    // it("should allow the trader deposit both long and shsrt assets", async () => {
    //   const { traderOne, traderTwo, JamoProtocolContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   const amountToDeposit2 = ethers.parseEther("200");
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1)
    //   //open a long position 
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
    //   const shortPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   const longPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 1);
    //   const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
    //   expect(+contractDetailsAfter[2].toString() / etherConstant).to.be.equal(1000) //amount deposisted * 10 ( 100 * 10 )
    //   expect(+contractDetailsAfter[3].toString() / etherConstant).to.be.equal(1000)
    //   expect(+contractDetailsAfter[4].toString() / etherConstant).to.be.greaterThan(0);
    //   console.log("short position", shortPosition);

    //   console.log("long position", longPosition);

    //   await JamoProtocolContract.connect(traderTwo).openPosition(amountToDeposit2, 2);
    //   const contractDetailsAfterTraderTwoDeposit = await JamoProtocolContract.getProtocolDetails();
    //   expect(+contractDetailsAfterTraderTwoDeposit[2].toString() / etherConstant).to.be.equal(3000)
    // });


    // it("should allow a user increase their position", async () => {
    //   const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   const amountToDeposit2 = ethers.parseEther("50");
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
    //   const shortPositionBeforeIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   //increase the short position
    //   await JamoProtocolContract.connect(traderOne).increasePosition(0, amountToDeposit2);
    //   const shortPositionAfterIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);

    //   console.log("before ", shortPositionBeforeIncrease)
    //   console.log("after ", shortPositionAfterIncrease)
    //   expect(+shortPositionAfterIncrease[2].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[2].toString() / etherConstant)
    //   expect(+shortPositionAfterIncrease[3].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[3].toString() / etherConstant)
    //   expect(+shortPositionAfterIncrease[4].toString() / etherConstant).to.be.greaterThan(+shortPositionBeforeIncrease[4].toString() / etherConstant)
    // });

    // it("should allow a user close their position with profit when longing", async () => {
    //   const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("200");
    //   const balBefore = await USDCContract.balanceOf(traderOne.address);
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
    //   //set the price of BTC
    //   PriceFeedContract.setLatestPrice(30600 * 1e8);
    //   await JamoProtocolContract.connect(traderOne).closePosition(0);
    //   const balAfter = await USDCContract.balanceOf(traderOne.address);
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString());
    //   console.log("userPosition ", userPosition)
    //   console.log("balance before =>", +balBefore.toString() / etherConstant);
    //   console.log("balance after =>", +balAfter.toString() / etherConstant);
    // });

    // it("should allow a user close their long position with a loss ", async () => {
    //   const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("200");
    //   const balBefore = await USDCContract.balanceOf(traderOne.address);

    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
    //   const protocolDetailsBefore = await JamoProtocolContract.getProtocolDetails();
    //   //set the price of BTC
    //   PriceFeedContract.setLatestPrice(29800 * 1e8); //selling at a loss here
    //   await JamoProtocolContract.connect(traderOne).closePosition(0);
    //   const protocolDetailsAfter = await JamoProtocolContract.getProtocolDetails();
    //   const balAfter = await USDCContract.balanceOf(traderOne.address);
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   expect(+balAfter.toString()).to.be.lessThan(+balBefore.toString());
    //   //assert if the long intrest in token was reduced
    //   expect(+protocolDetailsBefore[2].toString() / etherConstant).to.be.greaterThan(+protocolDetailsAfter[2].toString() / etherConstant)
    //   expect(+protocolDetailsBefore[4].toString() / etherConstant).to.be.greaterThan(+protocolDetailsAfter[4].toString() / etherConstant)
    //   console.log("userPosition ", userPosition)
    //   console.log("balance before =>", +balBefore.toString() / etherConstant);
    //   console.log("balance after =>", +balAfter.toString() / etherConstant);
    // });

    // it("should allow a user close their position with profit when shorting", async () => {
    //   const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("200");
    //   const balBefore = await USDCContract.balanceOf(traderOne.address);
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
    //   //set the price of BTC
    //   PriceFeedContract.setLatestPrice(29000 * 1e8);
    //   await JamoProtocolContract.connect(traderOne).closePosition(0);
    //   const balAfter = await USDCContract.balanceOf(traderOne.address);
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString());
    //   console.log("userPosition ", userPosition)
    //   console.log("balance before =>", +balBefore.toString() / etherConstant);
    //   console.log("balance after =>", +balAfter.toString() / etherConstant);
    // });


    // it("should allow a user close their short position with a loss ", async () => {
    //   const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("200");
    //   const balBefore = await USDCContract.balanceOf(traderOne.address);

    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
    //   const protocolDetailsBefore = await JamoProtocolContract.getProtocolDetails();
    //   //set the price of BTC
    //   PriceFeedContract.setLatestPrice(30300 * 1e8); //btc price increaed
    //   await JamoProtocolContract.connect(traderOne).closePosition(0);
    //   const protocolDetailsAfter = await JamoProtocolContract.getProtocolDetails();
    //   const balAfter = await USDCContract.balanceOf(traderOne.address);
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
    //   expect(+balAfter.toString()).to.be.lessThan(+balBefore.toString());
    //   //assert if the long intrest in token was reduced
    //   expect(+protocolDetailsBefore[3].toString() / etherConstant).to.be.greaterThan(+protocolDetailsAfter[3].toString() / etherConstant)
    //   expect(+protocolDetailsBefore[5].toString() / etherConstant).to.be.greaterThan(+protocolDetailsAfter[5].toString() / etherConstant)
    //   console.log("userPosition ", userPosition)
    //   console.log("balance before =>", +balBefore.toString() / etherConstant);
    //   console.log("balance after =>", +balAfter.toString() / etherConstant);
    // });

    // it("it should be able to liquidate a position", async () => {
    //   const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
    //   const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
    //   //set the price of BTC
    //   PriceFeedContract.setLatestPrice(2000 * 1e8); //btc price decreased
    //   await JamoProtocolContract.liquidatePosition(traderOne.address, 1);
    //   PriceFeedContract.setLatestPrice(35000 * 1e8);
    //   await JamoProtocolContract.liquidatePosition(traderOne.address, 0);
    //   const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
    //   const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 1);
    //   expect(+contractDetailsBefore[2].toString() / etherConstant).to.be.greaterThan(+contractDetailsAfter[2].toString() / etherConstant)
    //   expect(+contractDetailsBefore[3].toString() / etherConstant).to.be.greaterThan(+contractDetailsAfter[3].toString() / etherConstant)
    //   console.log("user position ", userPosition);
    // });

    // it("it should be able to calulate total PNL of Traders", async () => {
    //   const { traderOne, traderTwo, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
    //   const amountToDeposit = ethers.parseEther("100");
    //   //open a short position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 1);
    //   await JamoProtocolContract.connect(traderTwo).openPosition(amountToDeposit, 1);
    //   //open a long position
    //   await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);

    //   //set the price of BTC
    //   await PriceFeedContract.setLatestPrice(24000 * 1e8); //btc price decreased
    //   //calculate the total PNL of traders:
    //   const totalPNL = await JamoProtocolContract.calculateTotalPNLOfTraders();
    //   //calculating manually give 200 as the PNL
    //   expect(+totalPNL.toString() / etherConstant).to.be.equal(200);
    // });

    it("shoul be able to withraw deposit with intrest", async () => {
      const { traderOne, traderTwo, USDCContract, JamoProtocolContract, PriceFeedContract, VaultContract, liquidityProviderOne } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseEther("100");
      
      const balBefore = await USDCContract.balanceOf(liquidityProviderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(amountToDeposit, 2);
      await JamoProtocolContract.connect(traderTwo).openPosition(amountToDeposit, 2);
      // //set the price of BTC
      await PriceFeedContract.setLatestPrice(29900 * 1e8); //btc price increase
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      await JamoProtocolContract.connect(traderTwo).closePosition(0);
      let maxAssets = await VaultContract.maxWithdraw(liquidityProviderOne.address);
      // console.log("max assets => ", maxAssets);
      //redeem with a profit
      await VaultContract.connect(liquidityProviderOne).withdraw(maxAssets, liquidityProviderOne.address, liquidityProviderOne.address)
      const balAfter = await USDCContract.balanceOf(liquidityProviderOne.address);
      // console.log("balance before =>", +balBefore.toString() / etherConstant);
      // console.log("balance after =>", +balAfter.toString() / etherConstant);
      expect(+balAfter.toString() / etherConstant).to.be.greaterThan(+balBefore.toString() / etherConstant);
      
    })



  });


});
