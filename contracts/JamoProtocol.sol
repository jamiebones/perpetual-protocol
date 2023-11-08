// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// Uncomment this line to use console.log
import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./Vault.sol";

enum PositionStatus {
    opened,
    closed,
    liquidated
}

contract JamoProtocol {
    using EnumerableSet for EnumerableSet.AddressSet;
    //define state variables here
    AggregatorV3Interface internal dataFeed;
    MyVault vault;

    //Events

    //Errors

    error NoLiquidityError();
    error PositionIsEmptyError();
    error PositionIndexDoesNotExist();
    error PositionAtSuppliedIndexIsNotOpenedError();
    error PositionNotOpenedError();

    //constant variables
    IERC20 public collacteralToken;

    // Create a set of addresses
    EnumerableSet.AddressSet private addressSet;

    mapping(address => UserPosition[]) public positions;

    uint256 currentValueOfThePool = 0;
    uint256 totalOpenAssets = 0;
    uint256 longOpenAssets = 0;
    uint256 shortOpenAssets = 0;
    uint256 longOpenIntrestInTokens = 0;
    uint256 shortOpenIntrestInToken = 0;
    uint256 minimumLeverage = 2; //2X
    uint256 maxLeverage = 15; //15X
    uint256 constant multiplierFactor = 1 ether; //1 e 18
    uint256 immutable maxUtilizationPercentage = 90; //20 % arbitary value
    //address constant BTCUSDPriceFeed = 0xA39434A63A52E749F02807ae27335515BA4b07F7;
    address contractDeployer;
    uint initializer;

    //investmentType 1: short 2 : long

    //define structs
    struct UserPosition {
        uint256 indexPosition;
        int256 initialAssetPrice;
        uint256 collacteral; //USDC amount dropped
        uint256 tokenSize; //Amount of BTC (token) the borrowed fund was able to get you
        uint256 borrowedAmount; //The amount that was borrowed in USD
        uint256 timestamp; //date the position was opened
        PositionStatus positionStatus; //the status of the position open, closed, liquidated
        bool isLong;
    }

    constructor(address collacteral, address priceFeedAddress) {
        //set the collateral token here:
        collacteralToken = IERC20(collacteral);
        //set the vault address here

        contractDeployer = msg.sender;
        dataFeed = AggregatorV3Interface(
            priceFeedAddress
            //0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c //Mainnet address of BTC/USD
        );
    }

    modifier onlyDeployer() {
        require(
            msg.sender == contractDeployer,
            "only deployer can call this function"
        );
        _;
    }

    modifier initialize() {
        require(initializer == 0, "vault address already set");
        _;
    }

    function setVaultInContract(
        address vaultAddress
    ) external onlyDeployer initialize {
        vault = MyVault(vaultAddress);
        initializer = 1;
    }

    function openPosition(uint256 collacteral, uint8 investmentType) public {
        //check if pool can be deposisted into
        require(initializer == 1, "vault address not set yet");
        _withdrawTokenFromUser(collacteral);
        require(isLiquidityEnough(), "Not enough liquidity");
        //get the price of the assets:
        int btcPrice = getThePriceOfBTCInUSD();

        //calculate the levarage they can get;
        UserPosition memory newPosition;

        //get the user position array current index;
        UserPosition[] storage userPreviousPosition = positions[msg.sender];
        uint256 newpositionIndex = 0;
        if (userPreviousPosition.length > 0) {
            newpositionIndex = userPreviousPosition.length;
        }

        newPosition.indexPosition = newpositionIndex;
        newPosition.initialAssetPrice = btcPrice;
        newPosition.collacteral = collacteral;

        //borrowed amount is 10 x of collacteral
        uint256 amountBorrowed = collacteral * 10;
        newPosition.borrowedAmount = amountBorrowed;
        //token size is calculating how much token the borrowed amount can buy
        //btc price => price for 1 BTC / the amount the trader is borrowing

        uint256 sizeOfToken = amountBorrowed / uint256(btcPrice);
        newPosition.tokenSize = sizeOfToken;
        newPosition.positionStatus = PositionStatus.opened;
        newPosition.isLong = investmentType == 1 ? false : true;
        newPosition.timestamp = block.timestamp;
        //add the position to the user position array
        userPreviousPosition.push(newPosition);
        positions[msg.sender] = userPreviousPosition;
        //add it to the EnumerableSet
        addressSet.add(msg.sender);
        //increament the totalOpenAsset variable
        if (investmentType == 1) {
            //shortOpenAssets
            shortOpenAssets += amountBorrowed;
            //get the tokens size
            shortOpenIntrestInToken += sizeOfToken;
        } else {
            longOpenAssets += amountBorrowed;
            longOpenIntrestInTokens += sizeOfToken;
        }
    }

    function increasePosition(uint positionIndex, uint collacteral) public {
        //msg.sender must be the owner of the position
        UserPosition[] storage userPositions = positions[msg.sender];
        if (userPositions.length == 0) revert PositionIsEmptyError();
        UserPosition memory currentPosition = userPositions[positionIndex];
        if (currentPosition.indexPosition != positionIndex)
            revert PositionIndexDoesNotExist();
        //we are performing the increase here
        //check if the position is opened
        if (currentPosition.positionStatus == PositionStatus.opened) {
            //this is where we finally increased the position
            _withdrawTokenFromUser(collacteral);
            require(isLiquidityEnough(), "Not enough liquidity");

            uint256 amountBorrowed = collacteral * 10;
            currentPosition.borrowedAmount += amountBorrowed;

            //get the price of the assets:
            int btcPrice = getThePriceOfBTCInUSD();

            uint256 sizeOfToken = amountBorrowed / uint256(btcPrice);
            currentPosition.collacteral += collacteral;
            currentPosition.tokenSize += sizeOfToken;

            if (currentPosition.isLong) {
                longOpenAssets += amountBorrowed;
                longOpenIntrestInTokens += sizeOfToken;
            } else {
                longOpenAssets += amountBorrowed;
                longOpenIntrestInTokens += sizeOfToken;
            }
            //we are done so we saved everything back as we increasse the position
            userPositions[positionIndex] = currentPosition;
        } else {
            revert PositionAtSuppliedIndexIsNotOpenedError();
        }
    }

    function closePosition(uint positionIndex) public returns (bool) {
        UserPosition[] storage userPositions = positions[msg.sender];
        if (userPositions.length == 0 || positionIndex > userPositions.length)
            revert PositionIsEmptyError();
        require(isLiquidityEnough(), "Not enough liquidity");
        UserPosition memory currentPosition = userPositions[positionIndex];
        //we are performing the increase here
        //check if the position is opened
        if (currentPosition.positionStatus == PositionStatus.opened) {
            //this is where we calculate and possibly close the position
            uint256 currentValue = (uint256(getThePriceOfBTCInUSD()) *
                currentPosition.tokenSize);

            address payable receiverAddress = payable(msg.sender);
            if (currentPosition.isLong) {
                int pnlLong = int(currentValue) -
                    int(currentPosition.borrowedAmount);
                if (pnlLong > 0) {
                    //we have a profit situation;
                    //withdraw the profit and also the collacteral and send to the
                    uint256 amountToReceive = uint256(pnlLong) +
                        currentPosition.collacteral;
                    //CEI
                    currentPosition.positionStatus = PositionStatus.closed;
                    userPositions[positionIndex] = currentPosition;
                    //subtract the longopenintrest and openIntrestInTokens from the saved variables
                    longOpenAssets -= currentPosition.collacteral;
                    longOpenIntrestInTokens -= currentPosition.tokenSize;
                    //calculate and transfer the tokens
                    vault.withdrawTokens(receiverAddress, amountToReceive);
                    return true;
                    //the protocol owns the fault.....
                } else {
                    //we have a loss here that must be withdrawn from the collateral
                    //console.log("pnlLong ", pnlLong);
                    int256 amountLeftAfterLoss = int256(
                        currentPosition.collacteral
                    ) + pnlLong;
                    currentPosition.positionStatus = PositionStatus.closed;
                    userPositions[positionIndex] = currentPosition;
                    //subtract the longopenintrest and openIntrestInTokens from the saved variables
                    longOpenAssets -= currentPosition.collacteral;
                    longOpenIntrestInTokens -= currentPosition.tokenSize;
                    //calculate and transfer the tokens
                    if (amountLeftAfterLoss > 0) {
                        //transfer what is left to the trader and close the position
                        vault.withdrawTokens(
                            receiverAddress,
                            uint256(amountLeftAfterLoss)
                        );
                    }
                    return true;
                }
            } else {
                //we have shorting here
                int256 pnlShort = int256(currentPosition.borrowedAmount) -
                    int256(currentValue);

                if (pnlShort > 0) {
                    //we have a profit situation;
                    //withdraw the profit and also the collacteral and send to the
                    uint256 amountToReceive = uint256(pnlShort) +
                        currentPosition.collacteral;
                    //CEI
                    currentPosition.positionStatus = PositionStatus.closed;
                    userPositions[positionIndex] = currentPosition;
                    //subtract the sopenintrest and openIntrestInTokens from the saved variables
                    shortOpenAssets -= currentPosition.collacteral;
                    shortOpenIntrestInToken -= currentPosition.tokenSize;
                    //calculate and transfer the tokens
                    vault.withdrawTokens(receiverAddress, amountToReceive);
                    return true;
                    //the protocol owns the fault.....
                } else {
                    //the loss state of the shorting of tokens
                    //we have a loss here that must be withdrawn from the collateral
                    int256 amountLeftAfterLoss = int256(
                        currentPosition.collacteral
                    ) + pnlShort;
                    console.log(
                        "short borrowed amount =>",
                        currentPosition.collacteral
                    );

                    currentPosition.positionStatus = PositionStatus.closed;
                    userPositions[positionIndex] = currentPosition;
                    //subtract the longopenintrest and openIntrestInTokens from the saved variables
                    shortOpenAssets -= currentPosition.collacteral;
                    shortOpenIntrestInToken -= currentPosition.tokenSize;
                    //calculate and transfer the tokens
                    if (amountLeftAfterLoss > 0) {
                        //transfer what is left to the trader and close the position
                        vault.withdrawTokens(
                            receiverAddress,
                            uint256(amountLeftAfterLoss)
                        );
                    }
                    return true;
                }
            }
        } else {
            //possition is not open so we revert
            revert PositionNotOpenedError();
        }
    }

    function liquidatePosition(address userAddress, uint positionIndex) public {
        UserPosition[] storage userPositions = positions[userAddress];
        address payable receiverAddress = payable(userAddress);
        if (userPositions.length == 0 || positionIndex > userPositions.length)
            revert PositionIsEmptyError();
        require(isLiquidityEnough(), "Not enough liquidity");
        UserPosition memory currentPosition = userPositions[positionIndex];
        //we are performing the increase here
        //check if the position is opened
        if (currentPosition.positionStatus == PositionStatus.opened) {
            //calculate the leverage of the position
            uint256 currentValue = (uint256(getThePriceOfBTCInUSD()) *
                currentPosition.tokenSize);
            if (currentPosition.isLong) {
                //get the pnl of the position
                int256 pnlLong = int256(currentValue) -
                    int256(currentPosition.borrowedAmount);
                if (pnlLong < 0) {
                    //we have a loss in the position lets calculate how
                    //far loss the position is in
                    int256 balAfterLoss = int256(currentPosition.collacteral) +
                        pnlLong;
                    if (balAfterLoss > 0) {
                        //we have to check if the position is within leverage
                        uint256 leverage = currentPosition.borrowedAmount /
                            uint256(balAfterLoss);
                        console.log("leverage =>", leverage);
                        if (leverage >= maxLeverage) {
                            //liquidate reduce the longOpenAssets and longOpenIntrestInTokens
                            currentPosition.positionStatus = PositionStatus
                                .liquidated;
                            userPositions[positionIndex] = currentPosition;
                            longOpenAssets -= currentPosition.collacteral;
                            longOpenIntrestInTokens -= currentPosition
                                .tokenSize;
                            vault.withdrawTokens(
                                receiverAddress,
                                uint256(balAfterLoss)
                            );
                        }
                    } else {
                        //negative value of collacteral left. Liquidate the position and nothing back
                        currentPosition.positionStatus = PositionStatus
                            .liquidated;
                        userPositions[positionIndex] = currentPosition;
                        longOpenAssets -= currentPosition.collacteral;
                        longOpenIntrestInTokens -= currentPosition.tokenSize;
                    }
                }
            } else {
                //we are dealing with the shorting of tokens here
                //get the pnl of the position
                int256 pnlShort = int256(currentPosition.borrowedAmount) -
                    int256(currentValue);
                if (pnlShort < 0) {
                    //we have a loss in the position lets calculate how
                    //far loss the position is in
                    int256 balAfterLoss = int256(currentPosition.collacteral) +
                        pnlShort;
                    if (balAfterLoss > 0) {
                        //we have to check if the position is within leverage
                        uint256 leverage = currentPosition.borrowedAmount /
                            uint256(balAfterLoss);
                        if (leverage >= maxLeverage) {
                            //liquidate reduce the longOpenAssets and longOpenIntrestInTokens
                            currentPosition.positionStatus = PositionStatus
                                .liquidated;
                            userPositions[positionIndex] = currentPosition;
                            shortOpenAssets -= currentPosition.collacteral;
                            shortOpenIntrestInToken -= currentPosition
                                .tokenSize;
                            vault.withdrawTokens(
                                receiverAddress,
                                uint256(balAfterLoss)
                            );
                        }
                    } else {
                        //negative value of collacteral left. Liquidate the position and snd nothing back
                        currentPosition.positionStatus = PositionStatus
                            .liquidated;
                        userPositions[positionIndex] = currentPosition;
                        shortOpenAssets -= currentPosition.collacteral;
                        shortOpenIntrestInToken -= currentPosition.tokenSize;
                    }
                }
            }
        } else {
            revert PositionNotOpenedError();
        }
    }

    function calculateTotalPNLOfTraders() public view returns (int) {
        uint256 borrowedAssetLong = longOpenAssets; //total borrowed long asset
        //the current value of the longassetInTokens * currentPriceOfBTC
        uint256 currentValueofAssetLong = ((longOpenIntrestInTokens) *
            uint256(getThePriceOfBTCInUSD())) / (multiplierFactor);
        int256 pnlLong = int256(currentValueofAssetLong - borrowedAssetLong);
        //for shorting assets. The same thing but in the reversed order
        uint256 borrowedAssetShort = shortOpenAssets; //total borrowed short asset
        uint256 currentValueofAssetShort = ((shortOpenIntrestInToken) *
            uint256(getThePriceOfBTCInUSD())) / (multiplierFactor);
        int256 pnlShort = int256(borrowedAssetShort - currentValueofAssetShort);
        //add the pnlshort and long together to get the exact value;
        return pnlLong + pnlShort;
    }

    function isLiquidityEnough() public view returns (bool) {
        return
            shortOpenAssets +
                (longOpenIntrestInTokens * uint256(getThePriceOfBTCInUSD())) <
            (((vault.getDeposistedAmount() * maxUtilizationPercentage) / 100) *
                1 ether);
    }

    function _withdrawTokenFromUser(uint256 amount) private {
        require(
            collacteralToken.allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );
        require(
            collacteralToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
    }

    function getThePriceOfBTCInUSD() public view returns (int) {
        //makes use of 8 decimal
        // prettier-ignore
        (,int answer,,,/*uint80 answeredInRound*/) = dataFeed.latestRoundData();
        //divide by the number of digits to get the real USD value
        return answer / 100000000;
    }

    function getProtocolDetails()
        public
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return (
            currentValueOfThePool,
            totalOpenAssets,
            longOpenAssets,
            shortOpenAssets,
            longOpenIntrestInTokens,
            shortOpenIntrestInToken
        );
    }

    function getPositionByAddressAndIndex(
        address userAddress,
        uint positionIndex
    ) public view returns (UserPosition memory userPosition) {
        UserPosition[] memory position = positions[userAddress];
        return position[positionIndex];
    }
}
