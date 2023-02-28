// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract CashRushNftDataStore {
    uint8 private constant TOTAL_CARDS = 14;

    bool public dataIsFrozen = false;
    mapping(uint256 => uint8) public tokenType;

    event DataFrozen(bool isFrozen);
    event TypeUpdated(uint256 indexed tokenId, uint8 prevValue, uint8 newValue);

    function _uploadTypes(uint256 shift, bytes memory types) internal {
        require(!dataIsFrozen, "Data is frozen");
        for (uint256 i = 0; i < types.length; i++) {
            uint256 tokenId = shift + i;
            uint8 value = uint8(types[i]);
            emit TypeUpdated(tokenId, tokenType[tokenId], value);
            tokenType[tokenId] = value;
        }
    }

    function _freezeData() internal {
        emit DataFrozen(true);
        dataIsFrozen = true;
    }

    function tokenRate(uint256 tokenId) public view returns (uint256) {
        uint8 ttype = tokenType[tokenId];
        // 100/10000 = 0.01 = 1.00%
        if (ttype == uint8(0)) {
            return 0; // Undefined NFTs - 0.00%
        }
        if (ttype >= uint8(1) && ttype <= uint8(2)) {
            return 20; // Legendary NFTs - 0.20%
        }
        if (ttype >= uint8(3) && ttype <= uint8(5)) {
            return 10; // Rare NFTs - 0.10%
        }
        //if (ttype >= uint8(6) && ttype <= uint8(TOTAL_CARDS)) {
        return 5; // Common NFTs - 0.05%
        //}
    }

    function tokensMaxRate(uint256[] memory tokenIds)
        public
        view
        returns (uint256 maxRate)
    {
        uint256 tokenMaxRate = 0; // 0 - 20
        bool[] memory set = new bool[](TOTAL_CARDS + 1);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 trate = tokenRate(tokenId); // 0 - 20
            uint8 ttype = tokenType[tokenId];
            set[ttype] = true;
            tokenMaxRate = _max(trate, tokenMaxRate);
        }

        //  hidden combinations
        if (set[5]) {
            if (set[1] || set[3] || set[8] || set[11]) {
                return 500; // 5.00%
            }
        }
        if (set[9] && set[12]) {
            return 500; // 5.00%
        }
        if (set[10]) {
            if (set[1] || set[4]) {
                return 500; // 5.00%
            }
        }

        // sets
        if (
            set[1] &&
            set[2] &&
            set[3] &&
            set[4] &&
            set[5] &&
            set[6] &&
            set[7] &&
            set[8] &&
            set[9] &&
            set[10] &&
            set[11] &&
            set[12] &&
            set[13] &&
            set[14]
        ) {
            return 100; // Fully-Stacked Deck - 1.00%
        }
        if (set[1] && set[2]) {
            return 30; // Set of Legendary NFTs - 0.30%
        }
        if (set[3] && set[4] && set[5]) {
            return 20; // Set of Rare NFTs - 0.20%
        }
        if (
            set[6] &&
            set[7] &&
            set[8] &&
            set[9] &&
            set[10] &&
            set[11] &&
            set[12] &&
            set[13] &&
            set[14]
        ) {
            return _max(15, tokenMaxRate); // Set of Common NFTs - 0.15%
        }

        return tokenMaxRate; // cards max rate
    }

    function _max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }
}
