// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface iNft {
    function extraRate(address account) external view returns (uint256 _rate);
}

contract CashRush is ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    uint256 private constant PSN = 10_000;
    uint256 private constant PSNH = 5_000;

    uint256 private constant ONE_DAY = 86_400;
    uint256 private constant ONE_WEEK = 604_800;

    uint256 private constant PERIOD = 100;
    uint256 private constant LOOT_TO_HIRE_1MOBSTER = PERIOD * ONE_DAY;

    uint256 private constant MIN_REINVEST = 0.05 ether;
    uint256 private constant MIN_DEPOSIT = 0.05 ether;
    uint256 private constant DEPOSIT_STEP = 2 ether;

    uint256 private constant DEV_FEE_PERCENT = 300;
    uint256 private constant NFT_FEE_PERCENT = 300;
    uint256 private constant POOL_FEE_PERCENT = 50;
    uint256 private constant MOBSTER_KILL_PERCENT = 500;
    uint256 private constant REF_PERCENT = 500;
    uint256 private constant DECIMALS = 10000;

    address payable public root;
    address payable public devWallet;
    address payable public nftWallet;
    address public poolWallet;

    bool public initialized = false;
    uint256 public initializedAt;

    struct User {
        address user;
        uint256 totalDeposit;
        uint256 totalReinvest;
        uint256 totalRefIncome;
        uint256 totalRefs;
        uint256 mobsters;
        uint256 loot;
        uint256 lastClaim;
    }
    mapping(address => User) public users;

    struct Referral {
        address payable inviter;
        address payable user;
    }
    mapping(address => Referral) public referrers;

    uint256 public marketLoot;
    bool private isPurchase = false;

    modifier whenInitialized() {
        require(initialized, "NOT INITIALIZED");
        _;
    }

    event Purchase(
        address indexed user,
        address indexed inviter,
        uint256 eth,
        uint256 loot
    );
    event Hiring(address indexed user, uint256 loot, uint256 mobsters);
    event Sale(address indexed user, uint256 loot, uint256 eth);

    event DevWalletChanged(address prevAddr, address newAddr);
    event NftWalletChanged(address prevAddr, address newAddr);
    event PoolWalletChanged(address prevAddr, address newAddr);

    constructor(address _devWallet, address _nftWallet, address _poolWallet) {
        emit DevWalletChanged(devWallet, _devWallet);
        emit NftWalletChanged(nftWallet, _nftWallet);
        emit PoolWalletChanged(poolWallet, _poolWallet);
        devWallet = payable(_devWallet);
        nftWallet = payable(_nftWallet);
        poolWallet = payable(_poolWallet);

        referrers[_msgSender()] = Referral(
            payable(_msgSender()),
            payable(_msgSender())
        );
        root = payable(_msgSender());
    }

    function setDevWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Is zero address");
        emit DevWalletChanged(devWallet, newWallet);
        devWallet = payable(newWallet);
    }

    function getMaxDeposit(address _user) public view returns (uint256) {
        User memory user = users[_user];
        uint256 weeksPast = 1 +
            block.timestamp.sub(initializedAt).mul(10).div(ONE_WEEK).div(10);
        uint256 maxDepositSinceInitialisation = DEPOSIT_STEP.mul(weeksPast);
        return
            maxDepositSinceInitialisation.sub(
                user.totalDeposit.add(user.totalReinvest)
            );
    }

    // deposit
    function buyLoot(address payable inviter) external payable nonReentrant {
        require(msg.value >= MIN_DEPOSIT, "DEPOSIT MINIMUM VALUE");
        require(
            msg.value <= getMaxDeposit(_msgSender()),
            "DEPOSIT VALUE EXCEEDS MAXIMUM"
        );

        if (inviter == _msgSender() || inviter == address(0)) {
            inviter = root;
        }
        if (referrers[_msgSender()].inviter != address(0)) {
            inviter = referrers[_msgSender()].inviter;
        }
        require(referrers[inviter].user == inviter, "INVITER MUST EXIST");
        if (referrers[_msgSender()].user == address(0))
            referrers[_msgSender()] = Referral(inviter, payable(_msgSender()));

        User memory user;
        if (users[_msgSender()].totalDeposit > 0) {
            user = users[_msgSender()];
        } else {
            user = User(_msgSender(), 0, 0, 0, 0, 0, 0, block.timestamp);
            users[inviter].totalRefs++;
        }
        user.totalDeposit = user.totalDeposit.add(msg.value);

        uint256 lootBought = _calculateLootBuy(
            msg.value,
            SafeMath.sub(getBalance(), msg.value)
        );
        lootBought = SafeMath.sub(
            lootBought,
            _allFees(lootBought, inviter != root)
        );
        user.loot = user.loot.add(lootBought);
        users[_msgSender()] = user;
        emit Purchase(_msgSender(), inviter, msg.value, lootBought);

        uint256 devFee = _devFee(msg.value);
        _sendEth(devWallet, devFee);
        uint256 nftFee = _nftFee(msg.value);
        _sendEth(nftWallet, nftFee);
        uint256 poolFee = _poolFee(msg.value);
        _sendToPoolWallet(_msgSender(), poolFee);

        if (inviter != root) {
            uint256 refFee = _refFee(msg.value);
            _sendEth(inviter, refFee);
        }

        isPurchase = true;
        hireMobsters();
        isPurchase = false;
    }

    // reinvest
    function hireMobsters() public whenInitialized {
        User memory user = users[_msgSender()];

        uint256 hasLoot = getMyLoot(_msgSender());
        if (!isPurchase) {
            require(
                (user.lastClaim + 7 * ONE_DAY) <= block.timestamp,
                "Too early"
            );

            uint256 ethValue = calculateLootSell(hasLoot);
            require(ethValue >= MIN_REINVEST, "REINVEST MINIMUM VALUE");
            require(
                ethValue <= getMaxDeposit(_msgSender()),
                "DEPOSIT VALUE EXCEEDS MAXIMUM"
            );
            user.totalReinvest += ethValue;
        }

        uint256 newMobsters = hasLoot.div(LOOT_TO_HIRE_1MOBSTER);
        user.mobsters = user.mobsters.add(newMobsters);
        user.loot = 0;
        user.lastClaim = block.timestamp;
        users[_msgSender()] = user;
        emit Hiring(_msgSender(), hasLoot, newMobsters);

        // boost market to nerf miners hoarding
        marketLoot = marketLoot.add(hasLoot.div(5)); // +20%
    }

    // withdraw
    function sellLoot() external whenInitialized nonReentrant {
        User memory user = users[_msgSender()];
        require((user.lastClaim + 7 * ONE_DAY) <= block.timestamp, "Too early");

        uint256 hasLoot = getMyLoot(_msgSender());
        uint256 ethValue = calculateLootSell(hasLoot);
        require(getBalance() >= ethValue, "NOT ENOUGH BALANCE");

        uint256 devFee = _devFee(ethValue);
        _sendEth(devWallet, devFee);
        uint256 nftFee = _nftFee(ethValue);
        _sendEth(nftWallet, nftFee);

        ethValue = ethValue.sub(devFee.add(nftFee));

        user.loot = 0;
        user.lastClaim = block.timestamp;
        user.mobsters = user.mobsters.sub(_mobstersKillFee(user.mobsters));
        users[_msgSender()] = user;
        marketLoot = marketLoot.add(hasLoot);

        _sendEth(payable(_msgSender()), ethValue);
        emit Sale(_msgSender(), hasLoot, ethValue);
    }

    function _calculateTrade(
        uint256 rt,
        uint256 rs,
        uint256 bs
    ) private pure returns (uint256) {
        //(PSN*bs)/(PSNH+((PSN*rs+PSNH*rt)/rt));
        return
            SafeMath.div(
                SafeMath.mul(PSN, bs),
                SafeMath.add(
                    PSNH,
                    SafeMath.div(
                        SafeMath.add(
                            SafeMath.mul(PSN, rs),
                            SafeMath.mul(PSNH, rt)
                        ),
                        rt
                    )
                )
            );
    }

    function _calculateLootBuy(
        uint256 eth,
        uint256 contractBalance
    ) private view returns (uint256) {
        return _calculateTrade(eth, contractBalance, marketLoot);
    }

    function calculateLootBuy(uint256 eth) external view returns (uint256) {
        return _calculateLootBuy(eth, getBalance());
    }

    function calculateLootSell(uint256 loot) public view returns (uint256) {
        return _calculateTrade(loot, marketLoot, getBalance());
    }

    function _sendToPoolWallet(address from, uint256 value) private {
        (bool success, bytes memory data) = poolWallet.call{value: value}(
            abi.encodeWithSignature("deposit(address)", from)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "ETH_TRANSFER_FAILED"
        );
    }

    function _sendEth(address payable recipient, uint256 amount) private {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    // 3+3+0.5 +5
    function _allFees(
        uint256 amount,
        bool withRef
    ) private pure returns (uint256) {
        if (withRef)
            return
                _devFee(amount) +
                _nftFee(amount) +
                _poolFee(amount) +
                _refFee(amount);
        return _devFee(amount) + _nftFee(amount) + _poolFee(amount);
    }

    function _devFee(uint256 amount) private pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(amount, DEV_FEE_PERCENT), DECIMALS);
    }

    function _nftFee(uint256 amount) private pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(amount, NFT_FEE_PERCENT), DECIMALS);
    }

    function _poolFee(uint256 amount) private pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(amount, POOL_FEE_PERCENT), DECIMALS);
    }

    function _mobstersKillFee(uint256 amount) private pure returns (uint256) {
        return
            SafeMath.div(SafeMath.mul(amount, MOBSTER_KILL_PERCENT), DECIMALS);
    }

    function _refFee(uint256 amount) private pure returns (uint256) {
        return SafeMath.div(SafeMath.mul(amount, REF_PERCENT), DECIMALS);
    }

    function seedMarket() external payable onlyOwner {
        require(marketLoot == 0);
        initialized = true;
        initializedAt = block.timestamp;
        marketLoot = LOOT_TO_HIRE_1MOBSTER * 100_000;
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getMyMobsters(address _user) external view returns (uint256) {
        return users[_user].mobsters;
    }

    function getMyLoot(address _user) public view returns (uint256) {
        return users[_user].loot.add(getMyLootSinceLastHire(_user));
    }

    function getMyLootSinceLastHire(
        address _user
    ) public view returns (uint256) {
        User memory user = users[_user];
        uint256 secondsPassed = _min(
            LOOT_TO_HIRE_1MOBSTER,
            block.timestamp.sub(user.lastClaim)
        );
        uint256 extraRate = iNft(nftWallet).extraRate(_user);
        secondsPassed = secondsPassed.add(
            secondsPassed.mul(extraRate).div(100)
        );
        secondsPassed = _min(LOOT_TO_HIRE_1MOBSTER, secondsPassed);
        return secondsPassed.mul(user.mobsters);
    }

    function getMyRewards(address _user) external view returns (uint256) {
        uint256 hasLoot = getMyLoot(_user);
        uint256 ethValue = calculateLootSell(hasLoot);
        return ethValue;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
