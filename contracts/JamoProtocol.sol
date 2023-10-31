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

    //Events

    //Errors

    error NoLiquidityError();

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
    uint256 constant multiplierFactor = 1 ether; //1 e 18
    //address constant BTCUSDPriceFeed = 0xA39434A63A52E749F02807ae27335515BA4b07F7;

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

    constructor(address collacteral) {
        //set the collateral token here:
        collacteralToken = IERC20(collacteral);
        dataFeed = AggregatorV3Interface(
            0xA39434A63A52E749F02807ae27335515BA4b07F7 //Goerli address of BTC/USD
        );
    }

    function openPosition(uint256 collacteral, uint8 investmentType) public {
        //check if pool can be deposisted into
        _withdrawTokenFromUser(collacteral);

        //get the price of the assets:
        int btcPrice = getThePriceOfBTCInUSD();
        btcPrice = btcPrice / 100000000;
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

        uint256 sizeOfToken = (multiplierFactor * amountBorrowed) /
            uint256(btcPrice);
        newPosition.tokenSize = sizeOfToken;
        newPosition.positionStatus = PositionStatus.opened;
        newPosition.isLong = investmentType == 1 ? false : true;
        newPosition.timestamp = block.timestamp;
        //add the position to the user position array
        userPreviousPosition[userPreviousPosition.length] = newPosition;
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
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return answer;
    }

    //modifiers

    //state variables

    //functions

    //open positions
    //close positions
    //liquidate position
    //check health factor of a position
    //check if the pool value is within the allowed value
    //check if positions can be opened
    //check if deposits can be withdrawn
}
