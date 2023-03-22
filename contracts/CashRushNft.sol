// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "operator-filter-registry/src/DefaultOperatorFilterer.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/draft-ERC721Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./CashRushNftStaking.sol";

interface ITraitsShort {
    function contractURI() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract CashRushNft is
    ERC721,
    ERC721Enumerable,
    ERC721Burnable,
    CashRushNftStaking,
    ERC2981,
    DefaultOperatorFilterer,
    EIP712,
    ERC721Votes,
    Ownable
{
    using Strings for uint256;
    using Counters for Counters.Counter;

    uint256 private constant DAY = 86_400;
    uint256 private constant MAX_SUPPLY = 4000;
    uint256 private constant FREE_MINT = 200;
    uint256 private totalMinted = 0;
    Counters.Counter private _tokenIdCounter;

    // Metadata
    string private constant _name = "CASH RUSH";
    string private constant _symbol = "CASHRUSH";
    address public TRAITS;
    string private _contractURI = "https://cashrush.gg/metadata/contract.json";
    string private _baseURL = "https://cashrush.gg/metadata/";
    string private _baseExtension = ".json";
    bool private _revealed = false;
    string private _notRevealedURI =
        "https://cashrush.gg/metadata/unrevealed.json";

    // Mints
    address payable public wallet;
    // Free Mint
    bool public isActiveFreeMint = false;
    bytes32 public merkleRoot1;
    mapping(address => uint256) public minted1;
    // WL Mint
    bool public isActiveWhitelistMint = false;
    bytes32 public merkleRoot2;
    mapping(address => uint256) public minted2;
    uint256 public price2 = 0.03 ether; // TODO
    // Public Mint
    bool public isActivePublicMint = false;
    uint256 public price3 = 0.04 ether; // TODO

    uint256 public totalRewards;
    mapping(uint256 => uint256) public rewards;
    mapping(uint256 => uint256) public rewardsLastClaim;

    address public killer;
    address public killSigner;
    uint256 public immutable chainId;

    event Received(address indexed account, uint256 value);

    event Killed(uint256 indexed tokenId);
    event KillerChanged(address indexed oldKiller, address indexed newKiller);
    event KillSignerChanged(
        address indexed oldKillSigner,
        address indexed newKillSigner
    );

    constructor(
        address _wallet,
        address royaltyReceiver,
        uint96 royaltyNumerator
    ) public ERC721(_name, _symbol) EIP712(_name, "1") {
        wallet = payable(_wallet);
        _setDefaultRoyalty(royaltyReceiver, royaltyNumerator);

        // Setting start from 1.
        _tokenIdCounter.increment();

        chainId = block.chainid;
        emit KillerChanged(killer, _msgSender());
        killer = _msgSender();
        //emit KillSignerChanged(killSigner, _msgSender());
        //killSigner = _msgSender();
    }

    // CashRush - kill
    function kill(
        uint256 tokenId,
        bytes memory signature
    ) external whenNotStaked(tokenId) {
        require(_msgSender() == killer, "Access denied");

        if (killSigner != address(0)) {
            _checkSignature(tokenId, signature);
        }

        _burn(tokenId);
        emit Killed(tokenId);
    }

    function setKiller(address newKiller) external onlyOwner {
        emit KillerChanged(killer, newKiller);
        killer = newKiller;
    }

    function setKillSigner(address newKillSigner) external onlyOwner {
        emit KillSignerChanged(killSigner, newKillSigner);
        killSigner = newKillSigner;
    }

    function _checkSignature(
        uint256 tokenId,
        bytes memory signature
    ) internal view {
        address tokenOwner = _ownerOf(tokenId);
        require(
            _signatureWallet(tokenId, tokenOwner, signature) == killSigner,
            "Not authorized"
        );
    }

    function _signatureWallet(
        uint256 tokenId,
        address tokenOwner,
        bytes memory signature
    ) private view returns (address) {
        return
            ECDSA.recover(
                keccak256(abi.encode(chainId, tokenId, tokenOwner)),
                signature
            );
    }

    // CashRush - Game fees distribution
    function accumulated(
        uint256[] memory tokenIds
    ) external view returns (uint256) {
        uint256 share = (totalRewards + address(this).balance) / totalMinted;
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                tokenId >= 1 && tokenId <= totalMinted,
                "Index out of bounds"
            );
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j]);
            }
            uint256 payedRewards = rewards[tokenId];
            if (payedRewards < share) {
                uint256 toPay = share - payedRewards;
                total += toPay;
            }
        }
        return total;
    }

    function claim(uint256[] memory tokenIds) external {
        uint256 share = (totalRewards + address(this).balance) / totalMinted;
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j]);
            }
            require(ownerOf(tokenId) == _msgSender(), "Not token owner");
            uint256 payedRewards = rewards[tokenId];
            if (payedRewards < share) {
                uint256 toPay = share - payedRewards;
                rewards[tokenId] += toPay;
                rewardsLastClaim[tokenId] = block.timestamp;
                total += toPay;
            }
        }
        if (total > 0) {
            address payable recipient = payable(_msgSender());
            recipient.transfer(total);
            totalRewards += total;
        }
    }

    function claimByOwner(uint256[] memory tokenIds) external onlyOwner {
        uint256 share = (totalRewards + address(this).balance) / totalMinted;
        uint256 total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                tokenId >= 1 && tokenId <= totalMinted,
                "Index out of bounds"
            );
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                require(tokenId != tokenIds[j]);
            }
            require(
                (rewardsLastClaim[tokenId] + DAY * 90) <= block.timestamp,
                "Not allowed"
            );
            uint256 payedRewards = rewards[tokenId];
            if (payedRewards < share) {
                uint256 toPay = share - payedRewards;
                rewards[tokenId] += toPay;
                rewardsLastClaim[tokenId] = block.timestamp;
                total += toPay;
            }
        }
        if (total > 0) {
            address payable recipient = payable(_msgSender());
            recipient.transfer(total);
            totalRewards += total;
        }
    }

    // CashRush - Mint
    function safeMint(address to, uint256 tokenCount) external onlyOwner {
        require((totalSupply() + tokenCount) <= MAX_SUPPLY, "MAX_SUPPLY");
        totalMinted += tokenCount;
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
        }
    }

    function setWallet(address _wallet) external onlyOwner {
        wallet = payable(_wallet);
    }

    function setActiveFreeMint(bool status) external onlyOwner {
        isActiveFreeMint = status;
    }

    function setActiveWhitelistMint(bool status) external onlyOwner {
        isActiveWhitelistMint = status;
    }

    function setActivePublicMint(bool status) external onlyOwner {
        isActivePublicMint = status;
    }

    function freeMint(
        address account,
        uint256 tokenCount,
        bytes32[] calldata merkleProof
    ) external {
        require(
            isActiveFreeMint && totalSupply() <= FREE_MINT,
            "Mint not active"
        );
        require((minted1[account] + tokenCount) <= 1, "Mint limit");
        require((totalSupply() + tokenCount) <= MAX_SUPPLY, "MAX_SUPPLY");
        require(
            _verify1(_leaf(account, 1), merkleProof),
            "MerkleDistributor: Invalid  merkle proof"
        );
        minted1[account] += tokenCount;
        totalMinted += tokenCount;
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(account, tokenId);
        }
    }

    function whitelistMint(
        address account,
        uint256 tokenCount,
        bytes32[] calldata merkleProof
    ) external payable {
        require(isActiveWhitelistMint, "Mint not active");
        require((minted2[account] + tokenCount) <= 5, "Mint limit");
        require(
            _verify2(_leaf(account, 1), merkleProof),
            "MerkleDistributor: Invalid  merkle proof"
        );
        require((totalSupply() + tokenCount) <= MAX_SUPPLY, "MAX_SUPPLY");
        require(msg.value == tokenCount * price2, "Incorrect value");
        wallet.transfer(msg.value);
        minted2[account] += tokenCount;
        totalMinted += tokenCount;
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(account, tokenId);
        }
    }

    function publicMint(uint256 tokenCount) external payable {
        require(isActivePublicMint, "Mint not active");
        require((totalSupply() + tokenCount) <= MAX_SUPPLY, "MAX_SUPPLY");
        require(msg.value == tokenCount * price3, "Incorrect value");
        wallet.transfer(msg.value);
        totalMinted += tokenCount;
        for (uint256 i = 0; i < tokenCount; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(_msgSender(), tokenId);
        }
    }

    function _leaf(
        address account,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }

    function _verify1(
        bytes32 leaf,
        bytes32[] memory merkleProof
    ) internal view returns (bool) {
        return MerkleProof.verify(merkleProof, merkleRoot1, leaf);
    }

    function _verify2(
        bytes32 leaf,
        bytes32[] memory merkleProof
    ) internal view returns (bool) {
        return MerkleProof.verify(merkleProof, merkleRoot2, leaf);
    }

    function setRoot1(bytes32 merkleRoot_) external onlyOwner {
        merkleRoot1 = merkleRoot_;
    }

    function setRoot2(bytes32 merkleRoot_) external onlyOwner {
        merkleRoot2 = merkleRoot_;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Extra
    function rawOwnerOf(uint256 tokenId) external view returns (address) {
        return _ownerOf(tokenId);
    }

    function tokensOfOwner(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        require(0 < tokenCount, "ERC721Enumerable: owner index out of bounds");
        uint256[] memory tokenIds = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokenIds;
    }

    // NFTs Types
    function uploadTypes(uint256 shift, bytes memory types) external onlyOwner {
        _uploadTypes(shift, types);
    }

    function freezeData() external onlyOwner {
        _freezeData();
    }

    // Metadata
    function reveal() external onlyOwner {
        _revealed = true;
    }

    function setNotRevealedURI(string memory uri_) external onlyOwner {
        _notRevealedURI = uri_;
    }

    function contractURI() external view returns (string memory) {
        if (TRAITS != address(0)) return ITraitsShort(TRAITS).contractURI();
        return _contractURI;
    }

    function setContractURI(string memory uri_) external onlyOwner {
        _contractURI = uri_;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (!_revealed) return _notRevealedURI;

        if (TRAITS != address(0)) return ITraitsShort(TRAITS).tokenURI(tokenId);

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

    function setTraits(address traits_) external onlyOwner {
        TRAITS = traits_;
    }

    // Royalty
    function setDefaultRoyalty(
        address royaltyReceiver,
        uint96 royaltyNumerator
    ) external onlyOwner {
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
    ) internal override(ERC721, ERC721Enumerable, CashRushNftStaking) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Votes) {
        super._afterTokenTransfer(from, to, tokenId, batchSize);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public override(ERC721, IERC721) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function burn(uint256 tokenId) public override whenNotStaked(tokenId) {
        super.burn(tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721, IERC721)
        whenNotStaked(tokenId)
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721, IERC721)
        whenNotStaked(tokenId)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    )
        public
        override(ERC721, IERC721)
        whenNotStaked(tokenId)
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, CashRushNftStaking, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
