pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract EverLand is ERC721Enumerable, Ownable {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    Counters.Counter[] private m_LandCounter;

    uint256 private constant MAX_SUPPLY = 124884;
    uint256 private constant MAX_PURCHASE = 200;

    address private PGAIAA = 0xa8b062dE9dB7D22D6Ad6ef64Dc6FE53B3cba4A80; // 0x723B17718289A91AF252D616DE2C77944962d122;

    uint256 private m_EpicPrice = 350; // $350
    uint256 private m_RegularPrice = 175; // $175

    bytes32 private m_MerkleRoot;

    uint256 private m_Reserve = 50000;

    bool private m_IsMintable = false;
    bool private m_IsPublic = false;
    uint256 private m_SaleDate = 1648756800;

    uint256 private m_MarketingCommission = 25;

    struct Auction {
        uint256 price;
        string unit;
        uint32 id;
        address creator;
    }

    struct WhiteListAmounts {
        uint256 epic;
        uint256 regular;
    }

    struct validateLand {
        string landType;
        uint256 landSize;
    }

    mapping(uint256 => Auction) private m_Auctions;
    mapping(address => WhiteListAmounts) public m_WhiteListAmounts;

    uint256 private gaiaUSDC =
        (((79357452196816930849001 * (10**18)) /
            uint256(1868548345305467327315244)) *
            1588085682360 *
            (10**12)) / uint256(1586020149070416559561266);

    constructor() ERC721("Eever", "EEVER") {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);

        uint256 gaiaBalance = IERC20(PGAIAA).balanceOf(address(this));
        IERC20(PGAIAA).transfer(msg.sender, gaiaBalance);
    }

    function mint(
        uint256 _countOfLands,
        uint256 _landSize,
        uint256 _landType
    ) external {
        require(m_IsPublic, "Sale must be active to mint Lands");
        require(m_SaleDate < block.timestamp, "You can not mint yet");
        require(
            _countOfLands > 0 && _countOfLands <= MAX_PURCHASE,
            "Can only mint 200 tokens at a time"
        );
        require(
            totalSupply().add(_countOfLands) <= MAX_SUPPLY,
            "Purchase would exceed max supply of Lands"
        );
        uint256 countOfLands = 0;
        while (_countOfLands > 0) {
            uint256 tokenId = generateTokenId(
                m_LandCounter[_landSize * 2 + _landType].current(),
                _landSize,
                _landType
            );

            require(_validateIdOfLand(tokenId), "No Land Id");
            if (_exists(tokenId)) {
                m_LandCounter[_landSize * 2 + _landType].increment();
                continue;
            }

            // require(tokenId <= MAX_SUPPLY);
            _safeMint(msg.sender, tokenId);
            countOfLands = countOfLands + _landSize * _landSize;
            _countOfLands = _countOfLands.sub(1);
        }
        // uint256 gaiaUSDC = getTokenPrice();
        uint256 price = keccak256(abi.encodePacked((_landType))) ==
            keccak256(abi.encodePacked(("epic")))
            ? ((m_EpicPrice * countOfLands) * (10**36)) / gaiaUSDC
            : ((m_RegularPrice * countOfLands) * (10**36)) / gaiaUSDC;
        require(IERC20(PGAIAA).transferFrom(msg.sender, address(this), price));
    }

    function selectedMint(
        uint256 _countOfLands,
        uint256[] memory _ids,
        uint256 _index,
        uint256 _amount,
        bytes32[] memory _merkleProof
    ) external {
        require(m_IsMintable, "Sale must be active to mint Lands");
        require(
            _countOfLands > 0 && _countOfLands <= MAX_PURCHASE,
            "Can only mint 200 tokens at a time"
        );
        require(
            _ids.length == _countOfLands,
            "Length of id array must be count params"
        );
        for (uint256 i = 0; i < _countOfLands; i++) {
            for (uint256 j = i + 1; j < _countOfLands; j++) {
                require(_ids[i] != _ids[j], "ids must be not same each other");
            }
        }
        for (uint256 i = 0; i < _countOfLands; i++) {
            require(_validateIdOfLand(_ids[i]), "No Land Id");
            require(_exists(_ids[i]) == false, "Lands were already minted");
        }
        require(
            totalSupply().add(_countOfLands) <= MAX_SUPPLY,
            "Purchase would exceed max supply of Lands"
        );
        uint256 epicLands = 0;
        uint256 regularLands = 0;
        for (uint256 i = 0; i < _countOfLands; i++) {
            validateLand memory data = _validateTypeOfLand(_ids[i]);
            if (
                keccak256(abi.encodePacked((data.landType))) ==
                keccak256(abi.encodePacked(("epic")))
            ) {
                epicLands = epicLands + data.landSize * data.landSize;
            } else {
                regularLands = epicLands + data.landSize * data.landSize;
            }
        }
        require(
            m_WhiteListAmounts[msg.sender].regular + regularLands <=
                _amount / 2 &&
                m_WhiteListAmounts[msg.sender].epic + epicLands <=
                _amount - _amount / 2,
            "WhiteList OverAmount"
        );

        bytes32 node = keccak256(abi.encodePacked(_index, msg.sender, _amount));
        require(
            MerkleProof.verify(_merkleProof, m_MerkleRoot, node),
            "Invalid proof."
        );

        m_WhiteListAmounts[msg.sender].epic =
            m_WhiteListAmounts[msg.sender].epic +
            epicLands;
        m_WhiteListAmounts[msg.sender].epic =
            m_WhiteListAmounts[msg.sender].regular +
            regularLands;

        for (uint256 i = 0; i < _countOfLands; i++) {
            _safeMint(msg.sender, _ids[i]);
        }
    }

    function generateTokenId(
        uint256 _id,
        uint256 _landSize,
        uint256 _landType
    ) private pure returns (uint256) {
        return (_landSize * 2 + _landType) * 100000 + _id;
    }

    function isWhiteListVerify(
        uint256 _index,
        address _account,
        uint256 _amount,
        bytes32[] calldata _merkleProof
    ) public view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(_index, _account, _amount));
        return MerkleProof.verify(_merkleProof, m_MerkleRoot, node);
    }

    function getTokenPrice() public view returns (uint256) {
        address pairAddress1 = address(
            0x885eb7D605143f454B4345aea37ee8bc457EC730
        );
        IUniswapV2Pair pair1 = IUniswapV2Pair(pairAddress1);
        (uint256 Res0, uint256 Res1, ) = pair1.getReserves();
        uint256 price1 = (Res1 * (10**18)) / Res0;

        address pairAddress2 = address(
            0xCD578F016888B57F1b1e3f887f392F0159E26747
        );
        IUniswapV2Pair pair2 = IUniswapV2Pair(pairAddress2);
        (uint256 Re0, uint256 Re1, ) = pair2.getReserves();
        uint256 price2 = (Re0 * (10**30)) / Re1;
        return (price1 * price2) / (10**18);
    }

    function _validateTypeOfLand(uint256 _id)
        private
        pure
        returns (validateLand memory)
    {
        validateLand memory data;
        if (_id >= 510000 && _id <= 510019) {
            data.landType = "epic";
            data.landSize = 24;
        } else if (_id >= 500000 && _id <= 500031) {
            data.landType = "regular";
            data.landSize = 24;
        } else if (_id >= 410000 && _id <= 410069) {
            data.landType = "epic";
            data.landSize = 12;
        } else if (_id >= 400000 && _id <= 400129) {
            data.landType = "regular";
            data.landSize = 12;
        } else if (_id >= 310000 && _id <= 310269) {
            data.landType = "epic";
            data.landSize = 6;
        } else if (_id >= 300000 && _id <= 300539) {
            data.landType = "regular";
            data.landSize = 6;
        } else if (_id >= 210000 && _id <= 211079) {
            data.landType = "epic";
            data.landSize = 3;
        } else if (_id >= 200000 && _id <= 202169) {
            data.landType = "regular";
            data.landSize = 3;
        } else if (_id >= 100000 && _id <= 138959) {
            data.landType = "epic";
            data.landSize = 1;
        } else if (_id >= 0 && _id <= 81611) {
            data.landType = "regular";
            data.landSize = 1;
        }
        return data;
    }

    function _validateIdOfLand(uint256 _id) private pure returns (bool) {
        return
            (_id >= 510000 && _id <= 510019) &&
            (_id >= 500000 && _id <= 500031) &&
            (_id >= 410000 && _id <= 410069) &&
            (_id >= 400000 && _id <= 400129) &&
            (_id >= 310000 && _id <= 310269) &&
            (_id >= 300000 && _id <= 300539) &&
            (_id >= 210000 && _id <= 211079) &&
            (_id >= 200000 && _id <= 202169) &&
            (_id >= 100000 && _id <= 138959) &&
            (_id >= 0 && _id <= 81611);
    }

    function openTrade(
        uint32 _id,
        uint256 _price,
        string memory _unit
    ) external {
        require(m_IsMintable, "Sale must be active to mint GaiaLand");
        require(ownerOf(_id) == msg.sender, "sender is not owner");
        require(m_Auctions[_id].creator != msg.sender, "Already opened");
        m_Auctions[_id] = Auction({
            price: _price,
            unit: _unit,
            creator: msg.sender,
            id: _id
        });
    }

    function closeTrade(uint256 _id) external {
        require(m_IsMintable, "Sale must be active to mint GaiaLand");
        require(ownerOf(_id) == msg.sender, "sender is not owner");
        require(m_Auctions[_id].creator == msg.sender, "Already closed");
        delete m_Auctions[_id];
    }

    function buy(uint256 _id) external payable {
        require(m_IsMintable, "Sale must be active to mint GaiaLand");
        _validate(_id);
        require(m_Auctions[_id].creator == msg.sender, "Already closed");
        require(
            m_Auctions[_id].price <= msg.value,
            "Error, price is not match"
        );
        address _previousOwner = m_Auctions[_id].creator;
        address _newOwner = msg.sender;

        uint256 _commissionValue = msg.value.mul(m_MarketingCommission).div(
            1000
        );
        uint256 _sellerValue = msg.value.sub(_commissionValue);
        payable(_previousOwner).transfer(_sellerValue);
        _transfer(_previousOwner, _newOwner, _id);
        delete m_Auctions[_id];
    }

    function buyToken(uint256 _id, uint256 _price) external {
        require(m_IsMintable, "Sale must be active to mint GaiaLand");
        _validate(_id);
        require(m_Auctions[_id].creator == msg.sender, "Already closed");
        require(m_Auctions[_id].price <= _price, "Error, price is not match");
        address _previousOwner = m_Auctions[_id].creator;
        address _newOwner = msg.sender;

        uint256 _commissionValue = _price.mul(m_MarketingCommission).div(1000);
        uint256 _sellerValue = _price.sub(_commissionValue);

        require(
            IERC20(PGAIAA).transferFrom(
                msg.sender,
                address(this),
                _commissionValue
            )
        );
        require(
            IERC20(PGAIAA).transferFrom(
                msg.sender,
                _previousOwner,
                _sellerValue
            )
        );

        _transfer(_previousOwner, _newOwner, _id);
        delete m_Auctions[_id];
    }

    function transferLand(uint256 _id, address _to) external {
        require(m_IsMintable, "Sale must be active to mint GaiaLand");
        require(_to != address(0), "Can not send to address(0)");
        require(ownerOf(_id) == msg.sender, "sender is not owner");
        if (m_Auctions[_id].creator == msg.sender) {
            delete m_Auctions[_id];
        }
        transferFrom(msg.sender, _to, _id);
    }

    function _validate(uint256 _id) internal view {
        require(
            m_Auctions[_id].creator == msg.sender,
            "Item not listed currently"
        );
        require(msg.sender != ownerOf(_id), "Can not buy what you own");
    }

    // ######## EverLand Config #########

    // function setBaseURI(string memory baseURI) external onlyOwner {
    //     _setBaseURI(baseURI);
    // }

    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function getMaxPurchase() external pure returns (uint256) {
        return MAX_PURCHASE;
    }

    function setEpicPrice(uint256 _epicPrice) external onlyOwner {
        m_EpicPrice = _epicPrice;
    }

    function getEpicPrice() external view returns (uint256) {
        return m_EpicPrice;
    }

    function setRegularPrice(uint256 _regularPrice) external onlyOwner {
        m_RegularPrice = _regularPrice;
    }

    function getRegularPrice() external view returns (uint256) {
        return m_RegularPrice;
    }

    function setMintEnabled(bool _enabled) external onlyOwner {
        m_IsMintable = _enabled;
    }

    function getMintEnabled() external view returns (bool) {
        return m_IsMintable;
    }

    function setPublicMintEnabled(bool _enabled) external onlyOwner {
        m_IsPublic = _enabled;
    }

    function getPublicMintEnabled() external view returns (bool) {
        return m_IsPublic;
    }

    function setSaleDate(uint256 _date) external onlyOwner {
        m_SaleDate = _date;
    }

    function getSaleDate() external view returns (uint256) {
        return m_SaleDate;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        m_MerkleRoot = _merkleRoot;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return m_MerkleRoot;
    }

    function setReserve(uint256 _reserve) external onlyOwner {
        m_Reserve = _reserve;
    }

    function getReserve() external view returns (uint256) {
        return m_Reserve;
    }

    function setPGAIAContract(address _address) external onlyOwner {
        PGAIAA = _address;
    }

    function getPGAIAContract() external view returns (address) {
        return PGAIAA;
    }

    function setMarketingCommission(uint256 _commission) external onlyOwner {
        m_MarketingCommission = _commission;
    }

    function getMarketingCommission() external view returns (uint256) {
        return m_MarketingCommission;
    }
}
