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
    error CollacteralPositionSizeError(
        uint256 positionSize,
        uint256 collacteral
    );

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
    uint256 constant usdDecimal = 100_000_000;
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

    function openPosition(
        uint256 positionSize,
        uint256 collacteral,
        uint8 investmentType
    ) public {
        //check if pool can be deposisted into
        require(initializer == 1, "vault address not set yet");
        _checkIfPositionMeetsRequirement(positionSize, collacteral);
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
        newPosition.borrowedAmount = positionSize; //18 decimals for USD
        //token size is calculating how much token the borrowed amount can buy
        //btc price => price for 1 BTC / the amount the trader is borrowing

        uint256 sizeOfToken = positionSize / uint256(btcPrice);
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
            shortOpenAssets += positionSize;
            //get the tokens size
            shortOpenIntrestInToken += sizeOfToken;
        } else {
            longOpenAssets += positionSize;
            longOpenIntrestInTokens += sizeOfToken;
        }
    }

    function increasePosition(
        uint positionIndex,
        uint256 positionSize,
        uint256 collacteral
    ) public {
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
            if (positionSize > 0 && collacteral > 0) {
                _checkIfPositionMeetsRequirement(positionSize, collacteral);
            } else if (positionSize > 0) {
                _checkIfPositionMeetsRequirement(
                    positionSize,
                    currentPosition.collacteral
                );
            } else if (collacteral > 0) {
                _checkIfPositionMeetsRequirement(
                    currentPosition.borrowedAmount,
                    collacteral
                );
            }

            currentPosition.borrowedAmount += positionSize;
            uint256 amountBorrowed = currentPosition.borrowedAmount;
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

    function decreasePosition(uint positionIndex, uint256 positionSize) public {
        //msg.sender must be the owner of the position
        UserPosition[] storage userPositions = positions[msg.sender];
        if (userPositions.length == 0) revert PositionIsEmptyError();
        //get the price of the assets:
        int btcPrice = getThePriceOfBTCInUSD();
        uint256 sizeOfToken = positionSize / uint256(btcPrice);
        UserPosition memory currentPosition = userPositions[positionIndex];
        if (currentPosition.indexPosition != positionIndex)
            revert PositionIndexDoesNotExist();
        //check if the position is opened
        uint256 _longOpenAsset;
        uint256 _longOpenIntrest;
        uint256 _shortOpenAsset;
        uint256 _shortOpenIntrest;
        if (currentPosition.positionStatus == PositionStatus.opened) {
            //calculate the PNL of the transaction
            int256 pnl = _calculateTraderPositionPNL(currentPosition);
            int256 pnlAmount = (pnl *
                int256(positionSize == 0 ? 1 : positionSize)) /
                int256(positionSize == 0 ? 1 : currentPosition.borrowedAmount); //if user is reducing the size to 0 make provision for that scenario
            //reduce the global tracking of long and shortIntrest in token

            if (currentPosition.isLong) {
                _longOpenAsset =
                    longOpenAssets +
                    positionSize -
                    currentPosition.borrowedAmount;
                _longOpenIntrest =
                    longOpenIntrestInTokens +
                    sizeOfToken -
                    currentPosition.tokenSize;
            } else {
                _shortOpenAsset =
                    shortOpenAssets +
                    positionSize -
                    currentPosition.borrowedAmount;
                _shortOpenIntrest =
                    shortOpenIntrestInToken +
                    sizeOfToken -
                    currentPosition.tokenSize;
            }
            if (pnlAmount < 0) {
                //we have a loss here. How much loss should be deduced
                int256 remainCollacteral = int256(currentPosition.collacteral) +
                    pnlAmount;
                //check if remain collacteral left is greater than 0
                //if greater than 0 check if it can be liquidated
                if (remainCollacteral > 0) {
                    //check if the maxLeverage is still being maintained
                    if (
                        int256(positionSize) / remainCollacteral <=
                        int256(maxLeverage * usdDecimal)
                    ) {
                        //we are not be liquidated here
                        //loss sent to the liquidiy pool
                        uint256 amountToTransferToPool = currentPosition
                            .collacteral - uint256(remainCollacteral);
                        currentPosition.collacteral = uint256(
                            remainCollacteral
                        );
                        //reduce the global long and short
                        if (currentPosition.isLong) {
                            _setGlobalTokenSizeForLongAndShort(
                                _longOpenAsset,
                                _longOpenIntrest,
                                0,
                                0,
                                true
                            );
                        } else {
                            _setGlobalTokenSizeForLongAndShort(
                                0,
                                0,
                                _shortOpenAsset,
                                _shortOpenIntrest,
                                true
                            );
                        }
                        //reduce the position here
                        currentPosition.borrowedAmount = positionSize;
                        currentPosition.tokenSize = sizeOfToken;
                        currentPosition.collacteral = uint256(
                            remainCollacteral
                        );
                        userPositions[positionIndex] = currentPosition;
                        collacteralToken.transfer(
                            _vaultAddress,
                            amountToTransferToPool
                        );
                    } else {
                        //position is liquidated and remaining collacteral sent
                        liquidatePosition(msg.sender, positionIndex);
                    }
                } else {
                    //whole amount is liquidated here
                    liquidatePosition(msg.sender, positionIndex);
                }
            } else {
                //we have a profit here pay back some money to the trader
                if (currentPosition.isLong) {
                    _setGlobalTokenSizeForLongAndShort(
                        _longOpenAsset,
                        _longOpenIntrest,
                        0,
                        0,
                        true
                    );
                } else {
                    _setGlobalTokenSizeForLongAndShort(
                        0,
                        0,
                        _shortOpenAsset,
                        _shortOpenIntrest,
                        true
                    );
                }
                //reduce the position here
                currentPosition.borrowedAmount = positionSize;
                currentPosition.tokenSize = sizeOfToken;
                userPositions[positionIndex] = currentPosition;
                vault.withdrawTokens(payable(msg.sender), uint256(pnlAmount));
            }
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
        return result;
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
                    longOpenAssets -= currentPosition.borrowedAmount;
                    longOpenIntrestInTokens -= currentPosition.tokenSize;

            } else {
                //shorting here
                pnl =
                    int256(currentPosition.borrowedAmount) -
                    int256(currentValue);
                shortOpenAssets -= currentPosition.borrowedAmount;
                shortOpenIntrestInToken -= currentPosition.tokenSize;
            }

            if (pnl < 0) {
                //we have a loss in the position lets calculate how
                //far loss the position is in
                int256 balAfterLoss = int256(currentPosition.collacteral) + pnl;
                if (balAfterLoss > 0) {
                    //we have to check if the position is within leverage
                    uint256 leverage = currentPosition.borrowedAmount /
                        uint256(balAfterLoss);
                    if (leverage >= maxLeverage * usdDecimal) {
                        currentPosition.positionStatus = PositionStatus
                            .liquidated;
                        userPositions[positionIndex] = currentPosition;
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
                    userPositions[positionIndex] = currentPosition;
                    collacteralToken.transfer(
                        _vaultAddress,
                        currentPosition.collacteral
                    );
                }
            }
        } else {
            revert PositionNotOpenedError();
        }
    }

    function _checkIfPositionMeetsRequirement(
        uint256 positionSize,
        uint256 collacteral
    ) private view {
        if (
            positionSize / collacteral > maxLeverage * usdDecimal &&
            positionSize / collacteral < minimumLeverage * usdDecimal
        ) {
            revert CollacteralPositionSizeError(positionSize, collacteral);
        }
    }

    function _calculateTraderPositionPNL(
        UserPosition memory position
    ) private view returns (int) {
        uint256 currentValue = (uint256(getThePriceOfBTCInUSD()) *
            position.tokenSize);
        int256 pnl;

        if (position.isLong) {
            pnl = int(currentValue) - int(position.borrowedAmount);
        } else {
            pnl = int256(position.borrowedAmount) - int256(currentValue);
        }
        return pnl;
    }

    function _setGlobalTokenSizeForLongAndShort(
        uint256 _longOpenAsset,
        uint256 _longOpenAssetInToken,
        uint256 _shortOpenIntrest,
        uint256 _shortOpenIntrestInToken,
        bool isLong
    ) private {
        if (isLong) {
            longOpenAssets = _longOpenAsset;
            longOpenIntrestInTokens = _longOpenAssetInToken;
        } else {
            shortOpenAssets = _shortOpenIntrest;
            shortOpenIntrestInToken = _shortOpenIntrestInToken;
        }
    }
}
