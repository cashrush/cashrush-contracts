// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "operator-filter-registry/src/DefaultOperatorFilterer.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract CashRushNft is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    ERC2981,
    DefaultOperatorFilterer,
    EIP712,
    ERC721Votes,
    Ownable
{
    using Strings for uint256;
    using Counters for Counters.Counter;

    uint256 private constant MAX_SUPPLY = 5000;
    Counters.Counter private _tokenIdCounter;

    // Metadata
    string private constant _name = "CashRush";
    string private constant _symbol = "CASHRUSH";
    string private _contractURI = "";
    string private _baseURL = "";
    string private _baseExtension = "";
    bool private _revealed = false;
    string private _notRevealedURI = "";

    // CashRush
    address public immutable game;
    address payable public devWallet;
    mapping(uint256 => bool) public isStaked;

    uint256 public totalRewards;
    mapping(uint256 => uint256) public rewards;

    event Received(address indexed account, uint256 value);

    constructor(
        address _game,
        address _devWallet,
        address royaltyReceiver,
        uint96 royaltyNumerator
    ) public ERC721(_name, _symbol) EIP712(_name, "1") {
        _tokenIdCounter.increment();
        game = _game;
        devWallet = payable(_devWallet);
        _setDefaultRoyalty(royaltyReceiver, royaltyNumerator);
    }

    // CashRush
    function stake(uint256[] memory tokenIds) external {
        _stake(tokenIds, true);
    }

    function unstake(uint256[] memory tokenIds) external {
        _stake(tokenIds, false);
    }

    function _stake(uint256[] memory tokenIds, bool state) private {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenIds[i] != tokenIds[j], "Duplicate tokenId");
            }
            require(ownerOf(tokenIds[i]) == _msgSender(), "Not token owner");
            isStaked[tokenIds[i]] = state;
        }
    }

    modifier whenNotStaked(uint256 tokenId) {
        require(!isStaked[tokenId], "Token is staked");
        _;
    }

    // Получение дохода от игры
    function accumulated(uint256[] memory tokenIds)
        external
        view
        returns (uint256)
    {
        uint256 share = (totalRewards + address(this).balance) / totalSupply();
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j], "Duplicate tokenId");
            }
            require(ownerOf(tokenId) == _msgSender(), "Not token owner");
            uint256 rewards = rewards[tokenId];
            if (rewards < share) {
                uint256 toPay = share - rewards;
                total += toPay;
            }
        }
        return total;
    }

    function claim(uint256[] memory tokenIds) external {
        uint256 share = (totalRewards + address(this).balance) / totalSupply();
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j], "Duplicate tokenId");
            }
            require(ownerOf(tokenId) == _msgSender(), "Not token owner");
            uint256 rewards = rewards[tokenId];
            if (rewards < share) {
                uint256 toPay = share - rewards;
                rewards[tokenId] += toPay;
                total += toPay;
            }
        }
        if (total > 0) {
            address payable recipient = payable(_msgSender());
            recipient.transfer(total);
        }
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Mint
    function safeMint(address to, uint256 tokenCount)
        external
        payable
        onlyOwner
    {
        require((totalSupply() + tokenCount) <= MAX_SUPPLY, "MAX_SUPPLY");
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
        }
        //  TODO сразу отправляем средства
        devWallet.transfer(msg.value);
    }

    // Extra
    function rawOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(owner);
        require(0 < tokenCount, "ERC721Enumerable: owner index out of bounds");
        uint256[] memory tokenIds = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    // Metadata
    function reveal() external onlyOwner {
        _revealed = true;
    }

    function setNotRevealedURI(string memory uri_) external onlyOwner {
        _notRevealedURI = uri_;
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory uri_) external onlyOwner {
        _contractURI = uri_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (!_revealed) return _notRevealedURI;

        return
            string(
                abi.encodePacked(_baseURL, tokenId.toString(), _baseExtension)
            );
    }

    function setBaseURI(string memory uri_) external onlyOwner {
        _baseURL = uri_;
    }

    function setBaseExtension(string memory fileExtension) external onlyOwner {
        _baseExtension = fileExtension;
    }

    // Royalty
    function setDefaultRoyalty(address royaltyReceiver, uint96 royaltyNumerator)
        external
        onlyOwner
    {
        _setDefaultRoyalty(royaltyReceiver, royaltyNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    // Override
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) whenNotStaked(tokenId) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Votes) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
        // TODO тут можно обновлять в игре статус - но  может дорого стоить покупка/продажа на маркетплейсе
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721, IERC721) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
