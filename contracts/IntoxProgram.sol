// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

// NTOX PROGRAM

// when profit reaches 200% of his investment(Staking+DR+IDR+Leader Bonus), earning will stop. if he want to continue receiving earning from DR, IDR, Leader Bonus and Staking, He needs to open a new stake again.

// referral
// 10% direct
// 2% 2nd level
// 1%  3rd to 5th level.

// leaders bonus
// when direct referral withdrawn his earnings, extra 10% will go to upline wallet.

// 15% system fee. for withdrawal.
// no minimum withdraw.

// admin fee: 10% every deposit goes to 5 wallets.

contract IntoxProgram {
    address payable[] private adminWallets;
    uint256[] private referalBonus = [10, 2, 1, 1, 1];
    mapping(address => UserInvestment) public usersInvestments;
    IERC20 private intoVerseToken;

    IntoxPlan[] private planArray;

    //Errors
    error NoMoreTokenAvailableToWithdraw();
    error BalanceTooLowForSelectedPlan();
    error ActivePlanAlreadyRunning();

    //define structs
    struct IntoxPlan {
        uint8 planType; //1 2 3 4 and 5
        uint256 planCost;
        uint256 dailyReward;
    }

    struct UserInvestment {
        address userAddress;
        address upline;
        IntoxPlan planType;
        bool planActive; //only one plan can be active at once
        uint256 planStarting; //the first time the plan started
        uint256 lastWithdrawTime;
        uint256 totalAmountWithdrawn; //this is the calulation of all the money accured to the fellow
        uint256 referralBonus; //this is where the accured referral bonus is stored
    }

    constructor(
        address payable[] memory _adminWallets,
        address _intoVersTokenAddress
    ) {
        //set the array value
        _setPlanArrayData();
        adminWallets = _adminWallets;
        intoVerseToken = IERC20(_intoVersTokenAddress);
    }

    function investInProgram(uint256 planType, address uplineAddress) public {
        //planType - 0 to get the index where the plan is stored
        uint256 plan = planType - 1;
        IntoxPlan memory selectedPlan = planArray[plan];
        //check if the user have the balance for the plan
        if (checkTokenBalance() < selectedPlan.planCost) {
            revert BalanceTooLowForSelectedPlan();
        }
        //create the Plan
        address uplineAddressStorage;
        if (uplineAddress != address(0)) {
            uplineAddressStorage = uplineAddress;
        }
        UserInvestment memory userInvestment = UserInvestment({
            userAddress: msg.sender,
            upline: uplineAddressStorage,
            planType: planArray[plan],
            planActive: true,
            planStarting: block.timestamp,
            lastWithdrawTime: 0,
            totalAmountWithdrawn: 0,
            referralBonus: 0
        });
        uint256 amountToWithdrawnFromUser = selectedPlan.planCost;
        uint256 directUplineBonus = (amountToWithdrawnFromUser * 10) / 100;
        uint256 secondLevelBonus = (amountToWithdrawnFromUser * 2) / 100;
        uint256 thirdToFifthLevelBonus = (amountToWithdrawnFromUser * 1) / 100;
        uint256 adminDepositBonus = (amountToWithdrawnFromUser * 10) / 100;

        //check if the user already have an active plan running
        UserInvestment memory prevInvestment = usersInvestments[msg.sender];
        //transfer the token to the contract
        require(
            intoVerseToken.transferFrom(
                msg.sender,
                address(this),
                amountToWithdrawnFromUser
            ),
            "transfer failed"
        );
        if (prevInvestment.planActive == true) {
            //we already have an active plan
            revert ActivePlanAlreadyRunning();
        }
        //calculate the referral bonus
        uint256 timeToLoop = 0;
        address currentUpline = uplineAddressStorage;
        while (timeToLoop < 5 && currentUpline != address(0)) {
            UserInvestment storage currentInvestment = usersInvestments[
                currentUpline
            ];
            if (currentInvestment.upline != address(0)) {
                //we have an upline give them their share of the loot
                if (timeToLoop == 0) {
                    currentInvestment.referralBonus += directUplineBonus;
                } else if (timeToLoop == 1) {
                    currentInvestment.referralBonus += secondLevelBonus;
                } else if (
                    timeToLoop == 2 || timeToLoop == 3 || timeToLoop == 4
                ) {
                    currentInvestment.referralBonus += thirdToFifthLevelBonus;
                }
                //get the token value
            } else {
                break;
            }
            currentUpline = currentInvestment.upline;
            timeToLoop++;
        }

        //withdraw the Token from the user
        _shareAdminDepositBonus(adminDepositBonus);
        //add the new investment play
        usersInvestments[msg.sender] = userInvestment;
    }

    function checkTokenBalance() public view returns (uint256) {
        uint256 userBalance = intoVerseToken.balanceOf(msg.sender);
        return userBalance;
    }

    function _setPlanArrayData() private {
        IntoxPlan memory planOne = IntoxPlan({
            planType: 1,
            planCost: 60,
            dailyReward: 5 //0.5 multiplying by 10
        });
        IntoxPlan memory planTwo = IntoxPlan({
            planType: 2,
            planCost: 150,
            dailyReward: 6 //0.6
        });
        IntoxPlan memory planThree = IntoxPlan({
            planType: 3,
            planCost: 300,
            dailyReward: 7 //0.7%
        });
        IntoxPlan memory planFour = IntoxPlan({
            planType: 4,
            planCost: 650,
            dailyReward: 8 //0.8
        });
        IntoxPlan memory planFive = IntoxPlan({
            planType: 5,
            planCost: 3000,
            dailyReward: 10 //1%
        });

        planArray[0] = planOne;
        planArray[1] = planTwo;
        planArray[2] = planThree;
        planArray[3] = planFour;
        planArray[4] = planFive;
    }

    function _shareAdminDepositBonus(uint _amountToShare) private {
        //loop through and share the token token
        uint256 index = 0;
        for (index; index < adminWallets.length; index++) {
            uint256 amountToShare = _amountToShare / adminWallets.length;
            require(
                intoVerseToken.transfer(adminWallets[index], amountToShare),
                "transfer failed"
            );
        }
    }
}
