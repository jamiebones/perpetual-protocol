// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract PriceFeedMock {
    int private price;

    constructor() {
        price = 2000;
    }

    function setLatestPrice(int _price) public {
        price = _price;
    }

    function latestRoundData() public view returns (uint80, int, uint, uint, uint80) {
        return (0, price, 0, 0, 0);
    }
}