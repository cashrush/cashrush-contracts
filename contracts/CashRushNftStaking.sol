// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./CashRushNftDataStore.sol";

abstract contract CashRushNftStaking is
    ERC721,
    ERC721Enumerable,
    CashRushNftDataStore
{
    mapping(uint256 => bool) public isStaked;
    mapping(address => uint256) public extraRate;

    event Staked(uint256 indexed tokenId);
    event Unstaked(uint256 indexed tokenId);
    event ExtraRateSetted(address indexed account, uint256 extraRate);

    function stake(uint256[] memory tokenIds) external {
        _stake(tokenIds, true);
    }

    function unstake(uint256[] memory tokenIds) external {
        _stake(tokenIds, false);
    }

    function _stake(uint256[] memory tokenIds, bool state) private {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j], "Duplicate tokenId");
            }
            require(ownerOf(tokenId) == msg.sender, "Not token owner");
            if (isStaked[tokenId] != state) {
                if (state) emit Staked(tokenId);
                else emit Unstaked(tokenId);
            }
            isStaked[tokenId] = state;
        }

        extraRate[msg.sender] = accountRate(msg.sender);
        emit ExtraRateSetted(msg.sender, extraRate[msg.sender]);
    }

    function accountRate(address account) public view returns (uint256) {
        return tokensMaxRate(tokensStakedOfOwner(account));
    }

    function tokensStakedOfOwner(address owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(owner);
        require(0 < tokenCount, "ERC721Enumerable: owner index out of bounds");
        uint256 stakedCount = 0;
        for (uint256 i = 0; i < tokenCount; i++) {
            if (isStaked[tokenOfOwnerByIndex(owner, i)]) {
                stakedCount++;
            }
        }

        uint256[] memory tokenIds = new uint256[](stakedCount);
        stakedCount = 0;
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(owner, i);
            if (isStaked[tokenId]) {
                tokenIds[stakedCount] = tokenId;
                stakedCount++;
            }
        }
        return tokenIds;
    }

    modifier whenNotStaked(uint256 tokenId) {
        _requireMinted(tokenId);
        require(!isStaked[tokenId], "Token is staked");
        _;
    }

    // Override
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
