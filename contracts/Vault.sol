// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./JamoProtocol.sol";

contract MyVault is ERC4626 {
    JamoProtocol immutable jamoProtocol;
    IERC20 immutable asset;

    //1 => 10
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _protocolAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        jamoProtocol = JamoProtocol(_protocolAddress);
        asset = IERC20(_asset);
    }

    function totalAssets() public view override returns (uint256) {
        //return totalDeposits - totalPNLOfTraders
    }

    function getDeposistedAmount() public view returns (uint) {
        return asset.balanceOf(address(this));
    }
}
