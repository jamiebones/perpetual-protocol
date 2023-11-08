// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./JamoProtocol.sol";

contract MyVault is ERC4626 {
    JamoProtocol immutable jamoProtocol;
    IERC20 immutable assetToken;
    address immutable protocolAddress;

    //1 => 10
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _protocolAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        jamoProtocol = JamoProtocol(_protocolAddress);
        assetToken = IERC20(_asset);
        protocolAddress = _protocolAddress;
    }

    function totalAssets() public view override returns (uint256) {
        //return totalDeposits - totalPNLOfTraders
        int256 result = int256(assetToken.balanceOf(address(this))) -
            jamoProtocol.calculateTotalPNLOfTraders();
        if (result > 0) {
            return uint256(result);
        }
        return 0;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256) {
        //check the liquidity here
        require(jamoProtocol.isLiquidityEnough(), "Not enough liquidity");
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function getDeposistedAmount() public view returns (uint) {
        return assetToken.balanceOf(address(this));
    }

    function withdrawTokens(
        address payable receiverAddress,
        uint256 amount
    ) external onlyProtocol {
        //who can call this function
        require(assetToken.balanceOf(address(this)) > amount, "Insufficient funds for payout");
        require(
            assetToken.transfer(receiverAddress, amount),
            "transfer failed"
        );
    }

    modifier onlyProtocol() {
        require(msg.sender == protocolAddress, "Not the protocol");
        _;
    }
}
