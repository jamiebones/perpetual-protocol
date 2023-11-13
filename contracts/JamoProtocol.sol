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
    address private _vaultAddress;

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
        _vaultAddress = vaultAddress;
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

    function closePosition(uint positionIndex) public {
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
            bool isLong = false;
            int256 pnl;
            address payable receiverAddress = payable(msg.sender);
            if (currentPosition.isLong) {
                isLong = true;
                pnl = int(currentValue) - int(currentPosition.borrowedAmount);
            } else {
                //shorting here
                pnl =
                    int256(currentPosition.borrowedAmount) -
                    int256(currentValue);
            }
            if (pnl > 0) {
                //we have a profit situation;
                //withdraw the profit and also the collacteral and send to the
                //CEI
                currentPosition.positionStatus = PositionStatus.closed;
                userPositions[positionIndex] = currentPosition;
                if (isLong) {
                    //subtract the longopenintrest and openIntrestInTokens from the saved variables
                    longOpenAssets -= currentPosition.collacteral;
                    longOpenIntrestInTokens -= currentPosition.tokenSize;
                } else {
                    //subtract the sopenintrest and openIntrestInTokens from the saved variables
                    shortOpenAssets -= currentPosition.collacteral;
                    shortOpenIntrestInToken -= currentPosition.tokenSize;
                }
                //calculate and transfer the tokens
                collacteralToken.transfer(
                    receiverAddress,
                    currentPosition.collacteral
                );
                vault.withdrawTokens(receiverAddress, uint256(pnl));
            } else {
                //we have a loss here that must be withdrawn from the collateral
                //console.log("pnlLong ", pnlLong);
                int256 amountLeftAfterLoss = int256(
                    currentPosition.collacteral
                ) + pnl;
                currentPosition.positionStatus = PositionStatus.closed;
                userPositions[positionIndex] = currentPosition;
                if (isLong) {
                    //subtract the longopenintrest and openIntrestInTokens from the saved variables
                    longOpenAssets -= currentPosition.collacteral;
                    longOpenIntrestInTokens -= currentPosition.tokenSize;
                } else {
                    //subtract the sopenintrest and openIntrestInTokens from the saved variables
                    shortOpenAssets -= currentPosition.collacteral;
                    shortOpenIntrestInToken -= currentPosition.tokenSize;
                }

                //calculate and transfer the tokens
                if (amountLeftAfterLoss > 0) {
                    //transfer what is left to the trader and close the position
                    //collacteral is going to the vault
                    uint256 amountTotransferToPool = currentPosition
                        .collacteral - uint256(amountLeftAfterLoss);
                    collacteralToken.transfer(
                        _vaultAddress,
                        amountTotransferToPool
                    );
                    collacteralToken.transfer(
                        receiverAddress,
                        uint256(amountLeftAfterLoss)
                    );
                } else {
                    collacteralToken.transfer(
                        _vaultAddress,
                        currentPosition.collacteral
                    );
                }
            }
        } else {
            //possition is not open so we revert
            revert PositionNotOpenedError();
        }
    }

    
    function calculateTotalPNLOfTraders() public view returns (int) {
        uint256 borrowedAssetLong = longOpenAssets; //total borrowed long asset

        //the current value of the longassetInTokens * currentPriceOfBTC
        uint256 currentValueofAssetLong = longOpenIntrestInTokens *
            uint256(getThePriceOfBTCInUSD());

        int256 pnlLong = int256(currentValueofAssetLong) -
            int256(borrowedAssetLong);
        //for shorting assets. The same thing but in the reversed order
        uint256 borrowedAssetShort = shortOpenAssets; //total borrowed short asset

        uint256 currentValueofAssetShort = ((shortOpenIntrestInToken) *
            uint256(getThePriceOfBTCInUSD()));
        int256 pnlShort = int256(borrowedAssetShort) -
            int256(currentValueofAssetShort);
        //add the pnlshort and long together to get the exact value;
        int256 result = pnlLong + pnlShort;
        if (result < 0) {
            return 0;
        } else {
            return result;
        }
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
            int256 pnl;
            bool isLong = false;
            if (currentPosition.isLong) {
                //get the pnl of the position
                isLong = true;
                pnl =
                    int256(currentValue) -
                    int256(currentPosition.borrowedAmount);
            } else {
                //shorting here
                pnl =
                    int256(currentPosition.borrowedAmount) -
                    int256(currentValue);
            }

            if (pnl < 0) {
                //we have a loss in the position lets calculate how
                //far loss the position is in
                int256 balAfterLoss = int256(currentPosition.collacteral) + pnl;
                if (balAfterLoss > 0) {
                    //we have to check if the position is within leverage
                    uint256 leverage = currentPosition.borrowedAmount /
                        uint256(balAfterLoss);
                    if (leverage >= maxLeverage) {
                        currentPosition.positionStatus = PositionStatus
                            .liquidated;
                        if (isLong) {
                            userPositions[positionIndex] = currentPosition;
                            longOpenAssets -= currentPosition.collacteral;
                            longOpenIntrestInTokens -= currentPosition
                                .tokenSize;
                        } else {
                            //shorting here
                            userPositions[positionIndex] = currentPosition;
                            shortOpenAssets -= currentPosition.collacteral;
                            shortOpenIntrestInToken -= currentPosition
                                .tokenSize;
                        }
                        uint256 liquidityMoney = currentPosition.collacteral -
                            uint256(balAfterLoss);
                        collacteralToken.transfer(
                            receiverAddress,
                            uint256(balAfterLoss)
                        );
                        collacteralToken.transfer(
                            _vaultAddress,
                            liquidityMoney
                        );
                        //send money to liquidity pool also
                    }
                } else {
                    //negative value of collacteral left. Liquidate the position and nothing back
                    //do longing and shorting here
                    currentPosition.positionStatus = PositionStatus.liquidated;
                    if (isLong) {
                        userPositions[positionIndex] = currentPosition;
                        longOpenAssets -= currentPosition.collacteral;
                        longOpenIntrestInTokens -= currentPosition.tokenSize;
                    } else {
                        //shorting here
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
}
