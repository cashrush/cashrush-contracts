// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

interface iNftKill {
    function kill(uint256 tokenId, bytes memory signature) external;
}

contract CashRushNftKiller is Ownable {
    iNftKill public nft;
    bytes public signature;
    mapping(address => bool) public admins;

    constructor(address nft_) {
        nft = iNftKill(nft_);
    }

    modifier onlyAdmins() {
        require(admins[msg.sender], "Not allowed");
        _;
    }

    function setAdmins(
        address[] memory admins_,
        bool status
    ) external onlyOwner {
        for (uint256 i = 0; i < admins_.length; i++) {
            admins[admins_[i]] = status;
        }
    }

    function kill(uint256[] memory tokenIds) external onlyAdmins {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            nft.kill(tokenIds[i], signature);
        }
    }
}
