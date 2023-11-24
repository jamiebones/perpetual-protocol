const {
  loadFixture,
  time
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers, network } = require("hardhat");
const { expect } = require("chai");
require("dotenv").config();

const etherConstant = 1_000_000_000_000_000_000;
const usdcConstant = 100_000_000

describe("JamoProtocol", function () {

  async function deployContractFixture() {
    // Contracts are deployed using the first signer/account by default
    const tokenToTransfer = ethers.parseUnits("1000", 8);
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
    const allowance = ethers.parseUnits("300", 8);
    const liquidityAmount = ethers.parseUnits("300", 8);
    //grant allowance
    await USDCContract.connect(liquidityProviderOne).approve(VaultContract.target, liquidityAmount);
    await USDCContract.connect(liquidityProviderTwo).approve(VaultContract.target, liquidityAmount);
    await USDCContract.connect(traderOne).approve(JamoProtocolContract.target, allowance);
    await USDCContract.connect(traderTwo).approve(JamoProtocolContract.target, allowance);
    //provide liquidity
    console.log("vault contract address => ", VaultContract.target);
    await VaultContract.connect(liquidityProviderOne).deposit(liquidityAmount, liquidityProviderOne.address);

    await VaultContract.connect(liquidityProviderTwo).deposit(liquidityAmount, liquidityProviderTwo.address);
    console.log("shares of provider ", (await VaultContract.balanceOf(liquidityProviderOne.address)));
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

    it("should allow the trader deposit collateral", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseUnits("25", 8);
      const positionSizeUSD = ethers.parseUnits("100", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSizeUSD, amountToDeposit, 1)
      const contractDetails = await JamoProtocolContract.getProtocolDetails();
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect((+userPosition[3].toString()) / usdcConstant).to.be.equal((+contractDetails[3].toString() / usdcConstant))
      //de deposisted 100 dollars multiplied by 10 to get collateral

      expect((+userPosition[2].toString()) / usdcConstant).to.be.greaterThan(0);
      console.log("contract details => ", +(contractDetails[3].toString()) / usdcConstant,
        +(contractDetails[5].toString()) / usdcConstant)
    });

    it("should revert because maxleverage is exceeded", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseUnits("1", 8);
      const positionSizeUSD = ethers.parseUnits("1", 8);
      //open a short position
      expect(await JamoProtocolContract.connect(traderOne).openPosition(positionSizeUSD, amountToDeposit, 1)).to.be.revertedWithCustomError(JamoProtocolContract, "CollacteralPositionSizeError");

    });

    it("should allow the trader deposit both long and short assets", async () => {
      const { traderOne, traderTwo, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseUnits("14", 8);
      const amountToDeposit2 = ethers.parseUnits("18", 8);
      const positionSize = ethers.parseUnits("200", 8)
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, amountToDeposit, 1)
      //open a long position 
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, amountToDeposit, 2);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsAfter[2].toString() / usdcConstant).to.be.equal(200)
      expect(+contractDetailsAfter[3].toString() / usdcConstant).to.be.equal(200)
      expect(+contractDetailsAfter[4].toString() / usdcConstant).to.be.greaterThan(0);

      await JamoProtocolContract.connect(traderTwo).openPosition(positionSize, amountToDeposit2, 2);
      const contractDetailsAfterTraderTwoDeposit = await JamoProtocolContract.getProtocolDetails();
      console.log("contract details after", contractDetailsAfterTraderTwoDeposit);
      expect(+contractDetailsAfterTraderTwoDeposit[2].toString() / usdcConstant).to.be.equal(400)
    });

    // currentValueOfThePool,
    // totalOpenAssets,
    // longOpenAssets,
    // shortOpenAssets,
    // longOpenIntrestInTokens,
    // shortOpenIntrestInToken


    it("should allow a user increase their collacteral", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseUnits("100", 8);
      const increaseCollacteral = ethers.parseUnits("50", 8);
      const positionSize = ethers.parseUnits("400", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, amountToDeposit, 1);
      const shortPositionBeforeIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      //increase the short position
      await JamoProtocolContract.connect(traderOne).increasePosition(0, 0, increaseCollacteral);
      const shortPositionAfterIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);

      console.log("position data before => ", shortPositionBeforeIncrease)
      console.log("position data after => ", shortPositionAfterIncrease)

      expect(+shortPositionAfterIncrease[1].toString() / usdcConstant).to.be.greaterThan(+shortPositionBeforeIncrease[1].toString() / usdcConstant)
      expect(+shortPositionAfterIncrease[2].toString() / usdcConstant).to.be.greaterThan(+shortPositionBeforeIncrease[2].toString() / usdcConstant)

    });

    it("should should revert when collacteral and position greater than maxLeverage", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const amountToDeposit = ethers.parseUnits("100", 8);
      const increaseCollacteral = ethers.parseUnits("50", 8);
      const increasePositionSize = ethers.parseUnits("50", 8);
      const positionSize = ethers.parseUnits("400", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, amountToDeposit, 1);
      //increase the short position
      await JamoProtocolContract.connect(traderOne).increasePosition(0, increasePositionSize, increaseCollacteral);
      expect(await JamoProtocolContract.connect(traderOne).increasePosition(0, increasePositionSize, increaseCollacteral)).to.be.revertedWithCustomError(JamoProtocolContract, "CollacteralPositionSizeError")
    });


    it("should allow a trader decrease their position and earn profit", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteral = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("1000", 8);
      const decreasepositionSize = ethers.parseUnits("500", 8);

      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteral, 2);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      //set the price of BTC
      await PriceFeedContract.setLatestPrice(30500 * 1e8);
      const userPositionBefore = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      //decrease position
      await JamoProtocolContract.connect(traderOne).decreasePosition(0, decreasepositionSize);
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsAfter[2].toString()).to.be.lessThan(+contractDetailsBefore[2].toString());
      expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString());
      expect(+contractDetailsAfter[4].toString()).to.be.lessThan(+contractDetailsBefore[4].toString());
      console.log("userPosition before => ", userPositionBefore)
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
      const userPositionAfter = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      // console.log("userPosition after => ", userPositionAfter);
      // console.log("details before =>", contractDetailsBefore)
      // console.log("details after =>", contractDetailsAfter)
    });

    it("should allow a trader decrease their position and lose money by slashing collacteral", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract, VaultContract } = await loadFixture(generalOperationFixture);
      const collacteral = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("1000", 8);
      const decreasepositionSize = ethers.parseUnits("200", 8);
      const balBefore = await USDCContract.balanceOf(VaultContract.target);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteral, 2);
      //set the price of BTC
      await PriceFeedContract.setLatestPrice(29000 * 1e8);
      const userPositionBefore = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      //decrease position
      await JamoProtocolContract.connect(traderOne).decreasePosition(0, decreasepositionSize);
      const balAfter = await USDCContract.balanceOf(VaultContract.target);
      const userPositionAfter = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+userPositionAfter[1].toString()).to.be.lessThan(+userPositionBefore[1].toString());
      expect(+balAfter.toString() / usdcConstant).to.be.greaterThan(+balBefore.toString() / usdcConstant);
      console.log("userPosition before => ", userPositionBefore)
      console.log("userPosition after => ", userPositionAfter);
      console.log("vault balance before => ", +balBefore.toString() / usdcConstant);
      console.log("vault balance after => ", +balAfter.toString() / usdcConstant);
    });

    it("should allow a trader decrease their position and be liquidated", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract, VaultContract } = await loadFixture(generalOperationFixture);
      const collacteral = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("1000", 8);
      const decreasepositionSize = ethers.parseUnits("500", 8);
      const balBefore = await USDCContract.balanceOf(VaultContract.target);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteral, 2);
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      //set the price of BTC
      await PriceFeedContract.setLatestPrice(15000 * 1e8);
      //decrease position
      await JamoProtocolContract.connect(traderOne).decreasePosition(0, decreasepositionSize);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      const balAfter = await USDCContract.balanceOf(VaultContract.target);
      const userPositionAfter = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+userPositionAfter[5].toString()).to.be.equals(2);
      expect(+balAfter.toString() / usdcConstant).to.be.greaterThan(+balBefore.toString() / usdcConstant);
      console.log("details before => ", contractDetailsBefore)
      console.log("details after => ", contractDetailsAfter);
      console.log("vault balance before => ", +balBefore.toString() / usdcConstant);
      console.log("vault balance after => ", +balAfter.toString() / usdcConstant);
    });

    it("should allow a trader increase their position", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const increasePosition = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("400", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      const shortPositionBeforeIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      //increase the short position
      await JamoProtocolContract.connect(traderOne).increasePosition(0, increasePosition, 0);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      const shortPositionAfterIncrease = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      console.log("position data before => ", shortPositionBeforeIncrease)
      console.log("position data after => ", shortPositionAfterIncrease)
      expect(+shortPositionAfterIncrease[2].toString() / usdcConstant).to.be.greaterThan(+shortPositionBeforeIncrease[2].toString() / usdcConstant)
      expect(+shortPositionAfterIncrease[3].toString() / usdcConstant).to.be.greaterThan(+shortPositionBeforeIncrease[3].toString() / usdcConstant)
      expect(contractDetailsAfter[2].toString() / usdcConstant).to.be.greaterThan(+contractDetailsBefore[2].toString() / usdcConstant)
      expect(contractDetailsAfter[4].toString() / usdcConstant).to.be.greaterThan(+contractDetailsBefore[4].toString() / usdcConstant)
    });

    it("should allow a user close their position with profit when longing", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("2500", 8)
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2);
      //set the price of BTC
      PriceFeedContract.setLatestPrice(30500 * 1e8);
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString());
      console.log("userPosition ", userPosition)
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
    });

    it("should allow a user close their long position with a loss ", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract, VaultContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("2000", 8);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2);
      const vaultBalBefore = await USDCContract.balanceOf(VaultContract.target);
      const protocolDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      //set the price of BTC
      PriceFeedContract.setLatestPrice(29800 * 1e8); //selling at a loss here
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      const vaultBalAfter = await USDCContract.balanceOf(VaultContract.target);
      const protocolDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+balAfter.toString()).to.be.lessThan(+balBefore.toString());
      //assert if the long intrest in token was reduced
      expect(+protocolDetailsBefore[2].toString() / usdcConstant).to.be.greaterThan(+protocolDetailsAfter[2].toString() / usdcConstant)
      expect(+protocolDetailsBefore[4].toString() / usdcConstant).to.be.greaterThan(+protocolDetailsAfter[4].toString() / usdcConstant)
      expect(+vaultBalAfter.toString() / usdcConstant).to.be.greaterThan(+vaultBalBefore.toString() / usdcConstant)
      console.log("userPosition ", userPosition)
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
    });

    it("should allow a user close their position with profit when shorting", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("300", 8);
      const positionSize = ethers.parseUnits("3600", 8);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      //set the price of BTC
      PriceFeedContract.setLatestPrice(29000 * 1e8);
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString());
      console.log("userPosition ", userPosition)
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
    });


    it("should allow a user close their short position with a loss ", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("200", 8);
      const positionSize = ethers.parseUnits("2000", 8);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      const protocolDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      //set the price of BTC
      PriceFeedContract.setLatestPrice(30300 * 1e8); //btc price increaed
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      const protocolDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      const userPosition = await JamoProtocolContract.getPositionByAddressAndIndex(traderOne.address, 0);
      expect(+balAfter.toString()).to.be.lessThan(+balBefore.toString());
      //assert if the long intrest in token was reduced
      expect(+protocolDetailsBefore[3].toString() / usdcConstant).to.be.greaterThan(+protocolDetailsAfter[3].toString() / usdcConstant)
      expect(+protocolDetailsBefore[5].toString() / usdcConstant).to.be.greaterThan(+protocolDetailsAfter[5].toString() / usdcConstant)
      console.log("userPosition ", userPosition)
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
    });

    it("it should be able to liquidate a position", async () => {
      const { traderOne, USDCContract, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1); //short
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2); //long
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      //set the price of BTC
      await PriceFeedContract.setLatestPrice(20000 * 1e8); //btc price decreased
      await JamoProtocolContract.liquidatePosition(traderOne.address, 1);
      await PriceFeedContract.setLatestPrice(45000 * 1e8);
      await JamoProtocolContract.liquidatePosition(traderOne.address, 0);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsBefore[2].toString() / usdcConstant).to.be.greaterThan(+contractDetailsAfter[2].toString() / usdcConstant)
      expect(+contractDetailsBefore[3].toString() / usdcConstant).to.be.greaterThan(+contractDetailsAfter[3].toString() / usdcConstant)

    });

    it("it should be able to calulate total PNL of Traders", async () => {
      const { traderOne, traderTwo, JamoProtocolContract, PriceFeedContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      await JamoProtocolContract.connect(traderTwo).openPosition(positionSize, collacteralAmount, 1);
      //open a long position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2);

      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();

      console.log("contract details => ", contractDetailsAfter);

      //set the price of BTC
      await PriceFeedContract.setLatestPrice(24000 * 1e8); //btc price decreased
      //calculate the total PNL of traders:
      const totalPNL = await JamoProtocolContract.calculateTotalPNLOfTraders();
      //calculating manually give 20.00008 as the PNL
      expect(+totalPNL.toString() / usdcConstant).to.be.equal(20.00008);
    });

    it("should return the correct asset used by the Vault ", async () => {
      const { USDCContract, VaultContract } = await loadFixture(deployContractFixture);
      const address = await VaultContract.asset();
      expect(address).to.be.equal(USDCContract.target);
    })

    it("shoul be able to withraw deposit with intrest", async () => {
      const { traderOne, traderTwo, USDCContract, JamoProtocolContract, PriceFeedContract, VaultContract, liquidityProviderOne } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      const balBefore = await USDCContract.balanceOf(liquidityProviderOne.address);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2);
      await JamoProtocolContract.connect(traderTwo).openPosition(positionSize, collacteralAmount, 2);
      // //set the price of BTC
      await PriceFeedContract.setLatestPrice(29500 * 1e8); //btc price increase
      await JamoProtocolContract.connect(traderOne).closePosition(0);
      await JamoProtocolContract.connect(traderTwo).closePosition(0);
      let maxAssets = await VaultContract.maxWithdraw(liquidityProviderOne.address);
      console.log("max assets dropped => ", maxAssets);
      const valAssetBalance = await USDCContract.balanceOf(VaultContract.target);
      const sharesLiquidityMan = await VaultContract.balanceOf(liquidityProviderOne.address);
      console.log("asset of vault => ", +valAssetBalance.toString() / usdcConstant);
      console.log("shares of liquidity person => ", +sharesLiquidityMan.toString() / usdcConstant);
      await VaultContract.connect(liquidityProviderOne).withdraw(maxAssets, liquidityProviderOne.address, liquidityProviderOne.address)
      const balAfter = await USDCContract.balanceOf(liquidityProviderOne.address);
      console.log("balance before =>", +balBefore.toString() / usdcConstant);
      console.log("balance after =>", +balAfter.toString() / usdcConstant);
      expect(+balAfter.toString() / usdcConstant).to.be.greaterThan(+balBefore.toString() / usdcConstant);

    })

    it("it should allow a trader to reduced their collacteral", async () => {
      const { traderOne, JamoProtocolContract, USDCContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      const reducedCollacteral = ethers.parseUnits("10", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      await JamoProtocolContract.connect(traderOne).decreaseCollacteral(0, positionSize, reducedCollacteral);
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString())
      console.log("bal before => ", +balBefore.toString()/ usdcConstant);
      console.log("bal after => ", +balAfter.toString()/ usdcConstant);
    });

    it("it should allow a trader to reduced their collacteral via positionSize in shorting and longing", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      const reducedPosition = ethers.parseUnits("10", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 2);
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      await JamoProtocolContract.connect(traderOne).decreaseCollacteral(0, reducedPosition, 0);
      await JamoProtocolContract.connect(traderOne).decreaseCollacteral(1, reducedPosition, 0);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      expect(+contractDetailsAfter[3].toString()).to.be.lessThan(+contractDetailsBefore[3].toString())
      expect(+contractDetailsAfter[2].toString()).to.be.lessThan(+contractDetailsBefore[2].toString())
    });

    it("it should allow a trader to reduced both position and collacteral", async () => {
      const { traderOne, JamoProtocolContract, USDCContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      const reducedPosition = ethers.parseUnits("10", 8);
      const reducedCollacteral = ethers.parseUnits("10", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      const balBefore = await USDCContract.balanceOf(traderOne.address);
      const contractDetailsBefore = await JamoProtocolContract.getProtocolDetails();
      await JamoProtocolContract.connect(traderOne).decreaseCollacteral(0, reducedPosition, reducedCollacteral);
      const contractDetailsAfter = await JamoProtocolContract.getProtocolDetails();
      const balAfter = await USDCContract.balanceOf(traderOne.address);
      expect(+balAfter.toString()).to.be.greaterThan(+balBefore.toString())
      expect(+contractDetailsAfter[3].toString()).to.be.lessThan(+contractDetailsBefore[3].toString())
    });

    it("it should throw an error when the max leverage is exceeded", async () => {
      const { traderOne, JamoProtocolContract } = await loadFixture(generalOperationFixture);
      const collacteralAmount = ethers.parseUnits("100", 8);
      const positionSize = ethers.parseUnits("100", 8);
      const reducedPosition = ethers.parseUnits("90", 8);
      const reducedCollacteral = ethers.parseUnits("90", 8);
      //open a short position
      await JamoProtocolContract.connect(traderOne).openPosition(positionSize, collacteralAmount, 1);
      expect(await JamoProtocolContract.connect(traderOne).decreaseCollacteral(0, reducedPosition, reducedCollacteral)).to.be.revertedWithCustomError(JamoProtocolContract, "CollacteralPositionSizeError")
    });


  });

});
