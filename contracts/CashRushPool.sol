// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CashRushPool is ReentrancyGuard, Ownable {
    uint256 public constant DELAY = 5 days;
    uint256 public constant SHARES = 50;
    uint256 public lastDeposit;
    uint256 public nextId;
    mapping(uint256 => address) public accounts;
    mapping(address => bool) public depositors;

    event Received(address indexed account, uint256 value);
    event Deposited(address indexed account, uint256 id, uint256 value);
    event Distributed(address indexed account, uint256 id, uint256 value);

    modifier onlyDepositors() {
        require(depositors[msg.sender], "Not allowed");
        _;
    }

    function setDepositors(address[] memory _depositors) external onlyOwner {
        for (uint256 i = 0; i < _depositors.length; i++) {
            depositors[_depositors[i]] = true;
        }
    }

    function distribute() external nonReentrant {
        require(block.timestamp >= (lastDeposit + DELAY), "Too early");
        uint256 shares = _min(SHARES, nextId);
        uint256 value = address(this).balance / shares;
        for (uint256 i = 1; i <= shares; i++) {
            uint256 id = nextId - i;
            _sendEth(payable(accounts[id]), value);
            emit Distributed(accounts[id], id, value);
        }
    }

    function _sendEth(address payable recipient, uint256 amount) private {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH_TRANSFER_FAILED");
    }

    function deposit(
        address account
    ) external payable onlyDepositors returns (bool) {
        require(msg.value > 0, "Deposit should be more than 0");
        lastDeposit = block.timestamp;
        uint256 id = nextId++;
        accounts[id] = account;
        emit Deposited(account, id, msg.value);
        return true;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        if (a < b) return a;
        else return b;
    }
}
